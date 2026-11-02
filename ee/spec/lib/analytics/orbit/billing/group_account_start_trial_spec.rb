# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::Billing::GroupAccount, '#start_trial', feature_category: :knowledge_graph do
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be(:owner) { create(:user, owner_of: group) }

  let(:client) { ::Gitlab::SubscriptionPortal::Client }
  let(:trial) { instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: true) }
  let(:current_user) { owner }

  subject(:result) { described_class.new(group).start_trial(by: current_user) }

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_trial: group)

    allow(client).to receive(:start_product_trial)
      .with(trial_type: :orbit, namespace_id: group.id)
      .and_return(::Gitlab::SubscriptionPortal::StartProductTrialResponse.new(success: true))
    allow(client).to receive(:expire_product_trial_cache)
    allow(::Analytics::Orbit::Trial).to receive(:status_for).with(group).and_return(trial)
  end

  it 'records a trial enrollment and turns on Orbit' do
    expect(result).to be_success
    expect(group.reload.orbit_namespace_enrollment).to be_trial
    expect(group.knowledge_graph_enabled_namespace).to be_present
  end

  it 'tracks the orbit_trial_started event' do
    expect { result }
      .to trigger_internal_events('orbit_trial_started')
      .with(namespace: group, user: owner)
      .and not_trigger_internal_events('orbit_trial_start_failed')
  end

  context 'when CDot reports an existing trial that has ended' do
    let(:trial) { instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: false) }

    before do
      allow(client).to receive(:start_product_trial).and_return(
        ::Gitlab::SubscriptionPortal::StartProductTrialResponse.new(
          success: false, error_code: :trial_already_active
        )
      )
    end

    it 'records the trial enrollment but does not turn on Orbit' do
      expect(result).to be_error
      expect(result.reason).to eq(:trial_ended)
      expect(group.reload.orbit_namespace_enrollment).to be_trial
      expect(group.knowledge_graph_enabled_namespace).to be_nil
    end

    it 'tracks the failure with the trial_ended label' do
      expect { result }
        .to trigger_internal_events('orbit_trial_start_failed')
        .with(namespace: group, user: owner, additional_properties: { label: 'trial_ended' })
        .and not_trigger_internal_events('orbit_trial_started')
    end
  end

  context 'when CDot reports an existing trial that is still active' do
    before do
      allow(client).to receive(:start_product_trial).and_return(
        ::Gitlab::SubscriptionPortal::StartProductTrialResponse.new(
          success: false, error_code: :trial_already_active
        )
      )
    end

    it 'turns on Orbit' do
      expect(result).to be_success
      expect(group.reload.knowledge_graph_enabled_namespace).to be_present
    end

    it 'tracks no event' do
      expect { result }.to not_trigger_internal_events('orbit_trial_started', 'orbit_trial_start_failed')
    end
  end

  context 'when the group has a beta enrollment' do
    before do
      create(:orbit_namespace_enrollment, :beta, namespace: group)
    end

    it 'starts the trial and turns the beta enrollment into a trial enrollment' do
      expect(result).to be_success
      expect(group.reload.orbit_namespace_enrollment).to be_trial
    end

    context 'when the beta cleanup deletes the enrollment after the trial row was recorded' do
      before do
        allow(::Analytics::Orbit::NamespaceEnrollment).to receive(:convert_beta_to_trial)
          .and_wrap_original do |original, *args|
          ::Analytics::Orbit::NamespaceEnrollment.where(namespace_id: group.id).delete_all
          original.call(*args)
        end
      end

      it 'still ends up with a trial enrollment' do
        expect(result).to be_success
        expect(group.reload.orbit_namespace_enrollment).to be_trial
      end
    end

    context 'when CDot reports that the trial has ended' do
      let(:trial) { instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: false) }

      it 'keeps the beta enrollment, so the group gets no trial access' do
        expect(result.reason).to eq(:trial_ended)
        expect(group.reload.orbit_namespace_enrollment).to be_beta
      end
    end

    context 'when the orbit_promo_access_gate flag is disabled' do
      before do
        stub_feature_flags(orbit_promo_access_gate: false)
      end

      it 'is forbidden, never calls CDot, and keeps the beta enrollment' do
        expect(client).not_to receive(:start_product_trial)

        expect(result).to be_error
        expect(result.reason).to eq(:forbidden)
        expect(group.reload.orbit_namespace_enrollment).to be_beta
      end

      it 'tracks no event' do
        expect { result }.to not_trigger_internal_events('orbit_trial_started', 'orbit_trial_start_failed')
      end
    end
  end

  context 'when CDot rejects the group as ineligible' do
    before do
      allow(client).to receive(:start_product_trial).and_return(
        ::Gitlab::SubscriptionPortal::StartProductTrialResponse.new(
          success: false, error_code: :ineligible, error_message: 'subscription_not_allowed'
        )
      )
    end

    it 'returns the ineligible message and records no enrollment' do
      expect(result).to be_error
      expect(result.reason).to eq(:ineligible)
      expect(result.message).to eq('Contact sales to get GitLab Orbit for this group.')
      expect(group.reload.orbit_namespace_enrollment).to be_nil
    end

    it 'tracks the CDot reason' do
      expect { result }
        .to trigger_internal_events('orbit_trial_start_failed')
        .with(namespace: group, user: owner,
          additional_properties: { label: 'ineligible', property: 'subscription_not_allowed' })
    end
  end

  context 'when CDot does not know the group' do
    before do
      allow(client).to receive(:start_product_trial).and_return(
        ::Gitlab::SubscriptionPortal::StartProductTrialResponse.new(success: false, error_code: :not_found)
      )
    end

    it 'tracks not_found as the CDot reason' do
      expect { result }
        .to trigger_internal_events('orbit_trial_start_failed')
        .with(namespace: group, user: owner, additional_properties: { label: 'ineligible', property: 'not_found' })
    end
  end

  context 'when CDot is unreachable' do
    before do
      allow(client).to receive(:start_product_trial)
        .and_raise(::Gitlab::SubscriptionPortal::StartProductTrialResponse::Error, 'boom')
    end

    it 'reports the failure to Sentry and records no enrollment' do
      expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
        an_instance_of(::Gitlab::SubscriptionPortal::StartProductTrialResponse::Error),
        hash_including(gl_namespace_id: group.id)
      )

      expect(result).to be_error
      expect(result.reason).to eq(:unavailable)
      expect(group.reload.orbit_namespace_enrollment).to be_nil
    end
  end

  context 'when Orbit cannot be turned on' do
    before do
      allow_next_instance_of(::Analytics::KnowledgeGraph::ToggleNamespaceService) do |service|
        allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'Toggle failed'))
      end
    end

    it 'returns the toggle message and keeps the trial enrollment' do
      expect(result).to be_error
      expect(result.reason).to eq(:unavailable)
      expect(result.message).to eq('Toggle failed')
      expect(group.reload.orbit_namespace_enrollment).to be_trial
    end

    it 'tracks the failure with the unavailable label' do
      expect { result }
        .to trigger_internal_events('orbit_trial_start_failed')
        .with(namespace: group, user: owner, additional_properties: { label: 'unavailable' })
        .and not_trigger_internal_events('orbit_trial_started')
    end
  end

  context 'when the group is excluded from indexing' do
    before do
      create(:knowledge_graph_excluded_namespace, namespace: group)
    end

    it 'reports that the group cannot be indexed and never calls CDot' do
      expect(client).not_to receive(:start_product_trial)

      expect(result).to be_error
      expect(result.reason).to eq(:cannot_be_indexed)
    end
  end

  context 'when the user is a maintainer' do
    let(:current_user) { create(:user, maintainer_of: group) }

    it 'is forbidden' do
      expect(result).to be_error
      expect(result.reason).to eq(:forbidden)
    end

    it 'tracks no event' do
      expect { result }.to not_trigger_internal_events('orbit_trial_started', 'orbit_trial_start_failed')
    end
  end
end
