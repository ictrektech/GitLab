# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::Transfer::TopLevelGroupService, :aggregate_failures, feature_category: :organization do
  let_it_be(:old_organization) { create(:organization) }
  let_it_be(:new_organization) { create(:organization) }
  let_it_be(:user) { create(:user, organization: old_organization) }
  let_it_be_with_refind(:group) { create(:group, organization: old_organization) }

  let(:groups_param) { group }
  let(:organization_param) { new_organization }
  let(:current_user_param) { user }

  let(:skip_authorization_param) { false }

  subject(:service) do
    described_class.new(
      groups: groups_param,
      new_organization: organization_param,
      current_user: current_user_param,
      skip_authorization: skip_authorization_param
    )
  end

  before_all do
    group.add_owner(user)
    new_organization.add_owner(user)
  end

  describe '#execute' do
    context 'when transfer is successful' do
      it 'logs an audit event for the transferred group' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
          hash_including(
            name: 'group_transferred_to_organization',
            author: user,
            scope: group,
            target: new_organization,
            message: "Transferred group to organization #{new_organization.name}",
            additional_details: {
              source_organization_id: old_organization.id,
              target_organization_id: new_organization.id
            }
          )
        ).and_call_original

        service.execute
      end

      context 'when there is no acting user (system-initiated transfer)' do
        let(:current_user_param) { nil }
        let(:skip_authorization_param) { true }

        it 'logs an audit event with a system author' do
          expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
            hash_including(
              name: 'group_transferred_to_organization',
              author: an_instance_of(::Gitlab::Audit::UnauthenticatedAuthor),
              scope: group,
              target: new_organization,
              message: "Transferred group to organization #{new_organization.name}"
            )
          ).and_call_original

          service.execute
        end

        it 'creates the audit event' do
          expect { service.execute }.to change { AuditEventReader.count }.by(1)
        end
      end

      context 'with multiple groups' do
        let_it_be_with_refind(:group2) { create(:group, organization: old_organization) }
        let_it_be_with_refind(:group3) { create(:group, organization: old_organization) }

        let(:groups_param) { [group, group2, group3] }

        before_all do
          group2.add_owner(user)
          group3.add_owner(user)
        end

        it 'logs an audit event for each transferred group' do
          expect(::Gitlab::Audit::Auditor).to receive(:audit).exactly(3).times.and_call_original

          service.execute
        end

        it 'creates audit events for all transferred groups' do
          expect { service.execute }.to change { AuditEventReader.count }.by(3)
        end
      end

      context 'when a group is already on the target organization' do
        let_it_be_with_refind(:moved_group) { create(:group, organization: new_organization, owners: user) }

        let(:groups_param) { [group, moved_group] }

        it 'logs an audit event only for the group that moved' do
          expect(::Gitlab::Audit::Auditor).to receive(:audit).with(hash_including(scope: group)).once.and_call_original
          expect(::Gitlab::Audit::Auditor).not_to receive(:audit).with(hash_including(scope: moved_group))

          expect(service.execute).to be_success
        end
      end
    end

    context 'when transfer fails' do
      let(:organization_param) { nil }

      it 'does not log an audit event' do
        expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

        service.execute
      end
    end

    context 'when transfer fails due to validation' do
      let_it_be(:parent_group) { create(:group, organization: old_organization) }
      let_it_be(:subgroup) { create(:group, parent: parent_group) }

      let(:groups_param) { subgroup }

      before_all do
        parent_group.add_owner(user)
      end

      it 'does not log an audit event' do
        expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

        service.execute
      end
    end

    describe 'subscription validation', :saas_gitlab_com_subscriptions do
      let_it_be_with_refind(:paid_group) do
        create(:group_with_plan, plan: :premium_plan, organization: old_organization, owners: user)
      end

      let_it_be_with_refind(:other_paid_group) do
        create(:group_with_plan, plan: :ultimate_plan, organization: old_organization, owners: user)
      end

      let_it_be_with_refind(:free_group) do
        create(:group_with_plan, plan: :free_plan, organization: old_organization, owners: user)
      end

      let_it_be_with_refind(:trial_group) do
        create(
          :group_with_active_trial,
          organization: old_organization,
          owners: user
        )
      end

      let_it_be_with_refind(:expired_trial_group) do
        create(
          :group_with_expired_trial,
          organization: old_organization,
          owners: user
        )
      end

      shared_examples 'rejects the transfer' do
        it 'returns an error and does not transfer the groups' do
          result = service.execute

          expect(result).to be_error
          expect(result.message).to eq(
            'There can only be one top-level group with a GitLab subscription in an Organization.'
          )
          expect(Array(groups_param).map { |g| g.reload.organization_id }).to all(eq(old_organization.id))
        end

        it 'does not log an audit event' do
          expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

          service.execute
        end
      end

      shared_examples 'allows the transfer' do
        it 'transfers the groups' do
          expect(service.execute).to be_success
        end
      end

      context 'when transferring multiple paid groups at once' do
        let(:groups_param) { [paid_group, other_paid_group] }

        it_behaves_like 'rejects the transfer'
      end

      context 'when transferring a paid group and trial group' do
        let(:groups_param) { [paid_group, trial_group] }

        it_behaves_like 'rejects the transfer'
      end

      context 'when transferring a paid group and an expired trial group' do
        let(:groups_param) { [paid_group, expired_trial_group] }

        it_behaves_like 'allows the transfer'
      end

      context 'when the organization already has a paid top-level group' do
        let_it_be_with_refind(:already_transferred_paid_group) do
          create(:group_with_plan, plan: :premium_plan, organization: new_organization, owners: user)
        end

        context 'when transferring a paid group' do
          let(:groups_param) { paid_group }

          it_behaves_like 'rejects the transfer'
        end

        context 'when transferring a free group' do
          let(:groups_param) { free_group }

          it_behaves_like 'allows the transfer'
        end
      end

      context 'when transferring a single paid group' do
        let(:groups_param) { [paid_group, free_group] }

        it_behaves_like 'allows the transfer'
      end

      context 'when transferring into the default organization' do
        let_it_be(:default_organization) { create(:organization, :default, owners: user) } # rubocop:disable Gitlab/RSpec/AvoidCreateDefaultOrganization -- we need to explicitly test transferring into default org for rollback

        let(:groups_param) { [paid_group, other_paid_group] }
        let(:organization_param) { default_organization }

        it_behaves_like 'allows the transfer'
      end

      context 'when GitLab.com subscriptions are not available' do
        let(:groups_param) { [paid_group, other_paid_group] }

        before do
          stub_saas_features(gitlab_com_subscriptions: false)
        end

        it_behaves_like 'allows the transfer'
      end
    end
  end
end
