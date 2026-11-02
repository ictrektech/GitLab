# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::KnowledgeGraph::ToggleNamespaceService, feature_category: :knowledge_graph do
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be(:owner) { create(:user, owner_of: group) }

  describe '#execute' do
    subject(:result) { described_class.new(group: group, current_user: owner, enabled: enabled).execute }

    before do
      stub_saas_features(gitlab_com_subscriptions: true)
      stub_licensed_features(orbit: true)
      stub_feature_flags(orbit_promo_access_gate: false)
    end

    context 'when user is not authorized' do
      let_it_be(:developer) { create(:user, developer_of: group) }
      let(:enabled) { true }

      subject(:result) { described_class.new(group: group, current_user: developer, enabled: enabled).execute }

      it 'returns a forbidden error' do
        expect(result).to be_error
        expect(result.reason).to eq(:forbidden)
      end
    end

    context 'when enabling' do
      let(:enabled) { true }

      before do
        stub_feature_flags(orbit_trial: false)
      end

      it 'creates an enabled namespace record' do
        expect { result }.to change { Analytics::KnowledgeGraph::EnabledNamespace.count }.by(1)
        expect(result).to be_success
        expect(result[:group]).to eq(group)
        expect(result[:group].knowledge_graph_enabled_namespace).to be_present
      end

      it 'records a beta enrollment' do
        result

        expect(group.reload.orbit_namespace_enrollment).to be_beta
      end

      context 'when the group has a trial enrollment' do
        before do
          create(:orbit_namespace_enrollment, namespace: group)
        end

        it 'keeps the trial enrollment' do
          result

          expect(group.reload.orbit_namespace_enrollment).to be_trial
        end
      end

      context 'when already enabled' do
        before do
          create(:knowledge_graph_enabled_namespace, namespace: group)
        end

        it 'is idempotent' do
          expect { result }.not_to change { Analytics::KnowledgeGraph::EnabledNamespace.count }
          expect(result).to be_success
        end
      end

      context 'when a concurrent request creates the record first' do
        it 'handles the race condition gracefully' do
          allow_next_instance_of(Analytics::KnowledgeGraph::EnabledNamespace) do |record|
            allow(record).to receive(:save!).and_wrap_original do |_method, *_args|
              raise ActiveRecord::RecordNotUnique
            end
          end

          expect(result).to be_success
        end
      end

      context 'when the group is excluded from indexing' do
        before do
          allow(Ability).to receive(:allowed?)
            .with(owner, :update_knowledge_graph_setting, group).and_return(true)
          create(:knowledge_graph_excluded_namespace, namespace: group)
        end

        it 'returns the validation error and records no enrollment' do
          expect(result).to be_error
          expect(result.message).to eq(
            'This top-level group is excluded. Remove the exclusion to turn on GitLab Orbit.'
          )
          expect(group.reload.orbit_namespace_enrollment).to be_nil
        end
      end

      context 'when the enrollment cannot be recorded' do
        before do
          allow(Analytics::Orbit::NamespaceEnrollment).to receive(:record_beta)
            .and_raise(ActiveRecord::StatementInvalid)
        end

        it 'does not enable Orbit' do
          expect { result }.to raise_error(ActiveRecord::StatementInvalid)
          expect(group.reload.knowledge_graph_enabled_namespace).to be_nil
        end
      end
    end

    context 'when enabling on self-managed' do
      let(:enabled) { true }

      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        stub_feature_flags(orbit_trial: false)
      end

      it 'records a direct enrollment' do
        expect(result).to be_success
        expect(group.reload.orbit_namespace_enrollment).to be_direct
      end

      context 'when the group has a beta enrollment' do
        before do
          create(:orbit_namespace_enrollment, :beta, namespace: group)
        end

        it 'turns the beta enrollment into a direct enrollment' do
          expect(result).to be_success
          expect(group.reload.orbit_namespace_enrollment).to be_direct
        end
      end
    end

    context 'when enabling with the orbit_trial flag on' do
      let(:enabled) { true }

      before do
        stub_feature_flags(orbit_trial: group)
      end

      context 'when the group has an active trial' do
        before do
          allow(::Analytics::Orbit::Trial).to receive(:status_for).with(group).and_return(
            instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: true)
          )
        end

        it 'enables Orbit without writing a beta enrollment' do
          expect { result }.to change { Analytics::KnowledgeGraph::EnabledNamespace.count }.by(1)
          expect(result).to be_success
          expect(group.reload.orbit_namespace_enrollment).to be_nil
        end

        context 'when GitLab turned Orbit off for an earlier trial end' do
          let!(:enrollment) { create(:orbit_namespace_enrollment, namespace: group, trial_ended_at: 1.day.ago) }

          it 'clears the trial end so the ended-trials cron checks the group again' do
            expect(result).to be_success
            expect(enrollment.reload.trial_ended_at).to be_nil
          end
        end
      end

      context 'when the group has a beta enrollment' do
        before do
          create(:orbit_namespace_enrollment, :beta, namespace: group)
        end

        it 'enables Orbit without consulting CDot and keeps the beta enrollment' do
          expect(::Analytics::Orbit::Trial).not_to receive(:status_for)

          expect { result }.to change { Analytics::KnowledgeGraph::EnabledNamespace.count }.by(1)
          expect(result).to be_success
          expect(group.reload.orbit_namespace_enrollment).to be_beta
        end
      end

      context 'when the trial has ended' do
        before do
          allow(::Analytics::Orbit::Trial).to receive(:status_for).with(group).and_return(
            instance_double(
              ::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: false, trial_ended?: true
            )
          )
        end

        it 'blocks the enable' do
          expect { result }.not_to change { Analytics::KnowledgeGraph::EnabledNamespace.count }
          expect(result).to be_error
          expect(result.reason).to eq(:trial_ended)
          expect(result.message).to eq(
            'The GitLab Orbit trial for this group has ended. Add GitLab Credits to turn it on again.'
          )
        end
      end

      context 'when the group has no trial' do
        before do
          allow(::Analytics::Orbit::Trial).to receive(:status_for).with(group).and_return(
            instance_double(
              ::Gitlab::SubscriptionPortal::ProductTrialResponse,
              trial_active?: false, trial_ended?: false, state: :trial_eligible
            )
          )
        end

        it 'blocks the enable as trial required' do
          expect { result }.not_to change { Analytics::KnowledgeGraph::EnabledNamespace.count }
          expect(result).to be_error
          expect(result.reason).to eq(:trial_required)
          expect(result.message).to eq('Start a trial to turn on GitLab Orbit for this group.')
        end
      end

      context 'when CDot is unreachable' do
        before do
          allow(::Analytics::Orbit::Trial).to receive(:status_for).with(group)
            .and_raise(::Gitlab::SubscriptionPortal::ProductTrialResponse::Error)
        end

        it 'reports the failure to Sentry and blocks the enable as unavailable' do
          expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
            an_instance_of(::Gitlab::SubscriptionPortal::ProductTrialResponse::Error), gl_namespace_id: group.id
          )

          expect { result }.not_to change { Analytics::KnowledgeGraph::EnabledNamespace.count }
          expect(result).to be_error
          expect(result.reason).to eq(:unavailable)
        end
      end

      context 'when the instance is not GitLab.com' do
        before do
          stub_saas_features(gitlab_com_subscriptions: false)
        end

        it 'enables Orbit without consulting CDot' do
          expect(::Analytics::Orbit::Trial).not_to receive(:status_for)

          expect { result }.to change { Analytics::KnowledgeGraph::EnabledNamespace.count }.by(1)
          expect(result).to be_success
        end
      end
    end

    context 'when enabling under the promo gate with no trial and no add-on' do
      let(:enabled) { true }

      before do
        stub_feature_flags(orbit_promo_access_gate: group, orbit_trial: false)
      end

      it 'asks for a purchase, because no trial can start' do
        expect(result.reason).to eq(:purchase_required)
        expect(result.message).to eq('Contact sales to get GitLab Orbit for this group.')
      end
    end

    context 'when enabling on an instance under the promo gate with no trial' do
      let(:enabled) { true }

      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        stub_feature_flags(orbit_promo_access_gate: true, orbit_trial: false)
      end

      it 'turns on Orbit without a trial or a purchase' do
        expect { result }.to change { Analytics::KnowledgeGraph::EnabledNamespace.count }.by(1)
        expect(result).to be_success
      end

      context 'when the instance has a trial started in CustomersDot' do
        before do
          stub_feature_flags(orbit_trial: true)
          allow(::License).to receive(:current).and_return(build(:license))
          allow(::License.current).to receive(:online_cloud_license?).and_return(true)
          allow(::Analytics::Orbit::Trial).to receive(:request_instance_status).and_return(
            instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: true)
          )
        end

        it 'gives access without a trial enrollment' do
          expect(result).to be_success
          expect(group.reload.orbit_namespace_enrollment).to be_nil
          expect(Analytics::Orbit::Billing.account_for(group)).to be_entitled
        end
      end
    end

    context 'when enabling with the Orbit promo access gate' do
      let(:enabled) { true }

      before do
        stub_feature_flags(orbit_promo_access_gate: group, orbit_trial: group)
      end

      context 'when the group has an active orbit_promo add-on' do
        before do
          create(:gitlab_subscription_add_on_purchase, :orbit_promo, namespace: group)
        end

        it 'enables Orbit without consulting CDot' do
          expect(::Analytics::Orbit::Trial).not_to receive(:status_for)

          expect { result }.to change { Analytics::KnowledgeGraph::EnabledNamespace.count }.by(1)
          expect(result).to be_success
        end

        it 'records a direct enrollment' do
          result

          expect(group.reload.orbit_namespace_enrollment).to be_direct
        end

        it 'turns a beta enrollment into a direct enrollment' do
          create(:orbit_namespace_enrollment, :beta, namespace: group)

          result

          expect(group.reload.orbit_namespace_enrollment).to be_direct
        end

        it 'keeps the end of an earlier trial' do
          enrollment = create(:orbit_namespace_enrollment, namespace: group, trial_ended_at: 1.day.ago)

          expect { result }.not_to change { enrollment.reload.trial_ended_at }
        end

        context 'when the group is Free' do
          before do
            stub_licensed_features(orbit: false)
          end

          it 'enables Orbit' do
            expect(result).to be_success
            expect(group.reload.knowledge_graph_enabled_namespace).to be_present
          end
        end
      end

      context 'when the group has an active trial' do
        before do
          allow(::Analytics::Orbit::Trial).to receive(:status_for).with(group).and_return(
            instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: true)
          )
        end

        it 'enables Orbit' do
          expect { result }.to change { Analytics::KnowledgeGraph::EnabledNamespace.count }.by(1)
          expect(result).to be_success
        end

        it 'records a trial enrollment for a trial that Sales added in CustomersDot, so the group gets access' do
          result

          expect(group.reload.orbit_namespace_enrollment).to be_trial
          expect(Analytics::Orbit::Billing.account_for(group)).to be_entitled
        end

        it 'turns a beta enrollment into a trial enrollment' do
          create(:orbit_namespace_enrollment, :beta, namespace: group)

          result

          expect(group.reload.orbit_namespace_enrollment).to be_trial
        end

        it 'clears the end of an earlier trial, so the trial gives access again' do
          enrollment = create(:orbit_namespace_enrollment, namespace: group, trial_ended_at: 1.day.ago)

          expect { result }.to change { enrollment.reload.trial_ended_at }.to(nil)
        end
      end

      context 'when the group has a beta enrollment and no trial' do
        before do
          create(:orbit_namespace_enrollment, :beta, namespace: group)
          allow(::Analytics::Orbit::Trial).to receive(:status_for).with(group).and_return(
            instance_double(
              ::Gitlab::SubscriptionPortal::ProductTrialResponse,
              trial_active?: false, trial_ended?: false, state: :trial_eligible
            )
          )
        end

        it 'blocks the enable as trial required' do
          expect { result }.not_to change { Analytics::KnowledgeGraph::EnabledNamespace.count }
          expect(result.reason).to eq(:trial_required)
        end
      end

      context 'when the orbit_trial flag is disabled for the group' do
        before do
          stub_feature_flags(orbit_trial: false)
        end

        it 'blocks the enable without consulting CDot and records no beta enrollment' do
          expect(::Analytics::Orbit::Trial).not_to receive(:status_for)

          expect { result }.not_to change { Analytics::KnowledgeGraph::EnabledNamespace.count }
          expect(result.reason).to eq(:purchase_required)
          expect(group.reload.orbit_namespace_enrollment).to be_nil
        end

        it 'records a direct enrollment for a group with the add-on' do
          create(:gitlab_subscription_add_on_purchase, :orbit_promo, namespace: group)

          expect(result).to be_success
          expect(group.reload.orbit_namespace_enrollment).to be_direct
        end
      end
    end

    context 'when disabling' do
      let(:enabled) { false }

      context 'when currently enabled' do
        before do
          create(:knowledge_graph_enabled_namespace, namespace: group)
        end

        it 'removes the enabled namespace record' do
          expect { result }.to change { Analytics::KnowledgeGraph::EnabledNamespace.count }.by(-1)
          expect(result).to be_success
          expect(result[:group].knowledge_graph_enabled_namespace).to be_nil
        end

        it 'keeps the enrollment' do
          create(:orbit_namespace_enrollment, :beta, namespace: group)

          expect { result }.not_to change { Analytics::Orbit::NamespaceEnrollment.count }
        end
      end

      context 'when already disabled' do
        it 'is idempotent' do
          expect { result }.not_to change { Analytics::KnowledgeGraph::EnabledNamespace.count }
          expect(result).to be_success
        end
      end

      context 'when destroy fails' do
        before do
          record = create(:knowledge_graph_enabled_namespace, namespace: group)
          allow(record).to receive(:destroy).and_return(false)
          record.errors.add(:base, 'could not be removed')
          allow(group).to receive(:knowledge_graph_enabled_namespace).and_return(record)
        end

        it 'returns an error' do
          expect(result).to be_error
          expect(result.message).to eq('could not be removed')
        end
      end
    end

    context 'when group is not a root namespace' do
      let_it_be(:subgroup) { create(:group, parent: group) }
      let(:enabled) { true }

      subject(:result) do
        described_class.new(group: subgroup, current_user: owner, enabled: enabled).execute
      end

      it 'returns an authorization error' do
        expect(result).to be_error
        expect(result.reason).to eq(:forbidden)
      end
    end
  end
end
