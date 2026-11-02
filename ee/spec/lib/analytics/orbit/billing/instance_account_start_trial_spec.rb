# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::Billing::InstanceAccount, '#start_trial', :enable_admin_mode,
  feature_category: :knowledge_graph do
  let_it_be(:admin) { create(:admin) }
  let(:current_license) { ::License.current || build(:license) }
  let_it_be(:user) { create(:user) }

  let(:client) { ::Gitlab::SubscriptionPortal::Client }
  let(:active_trial) { instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: true) }
  let(:current_user) { admin }

  subject(:result) { described_class.new.start_trial(by: current_user) }

  before do
    stub_saas_features(gitlab_com_subscriptions: false)
    stub_config(knowledge_graph: { 'enabled' => true })
    stub_feature_flags(orbit_trial: true, orbit_promo_access_gate: false)
    stub_licensed_features(orbit: true)
    allow(::License).to receive(:current).and_return(current_license)
    allow(current_license).to receive(:online_cloud_license?).and_return(true)
    allow(::Gitlab::CurrentSettings).to receive(:uuid).and_return('instance-uuid')

    allow(client).to receive(:start_product_trial)
      .with(trial_type: :orbit, instance_id: 'instance-uuid')
      .and_return(::Gitlab::SubscriptionPortal::StartProductTrialResponse.new(success: true))
    allow(client).to receive(:expire_product_trial_cache)
    allow(::Analytics::Orbit::Trial).to receive(:status_for_instance).and_return(active_trial)
  end

  context 'when the user is not an administrator' do
    let(:current_user) { user }

    it 'returns a forbidden error without consulting CDot' do
      expect(client).not_to receive(:start_product_trial)

      expect(result).to be_error
      expect(result.reason).to eq(:forbidden)
    end
  end

  it 'starts the trial and expires the cache' do
    expect(client).to receive(:expire_product_trial_cache).with(trial_type: :orbit, instance_id: 'instance-uuid')

    expect(result).to be_success
  end

  it 'tracks the started event and writes an audit event on a new trial' do
    expect(::Gitlab::Audit::Auditor).to receive(:audit).with(hash_including(name: 'orbit_instance_trial_start'))

    expect { result }
      .to trigger_internal_events('orbit_instance_trial_started')
      .with(user: admin)
      .and not_trigger_internal_events('orbit_instance_trial_start_failed')
  end

  context 'when writing the audit event fails' do
    before do
      allow(::Gitlab::Audit::Auditor).to receive(:audit).and_raise(StandardError, 'audit failed')
    end

    it 'still starts the trial and tracks the error' do
      expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(an_instance_of(StandardError))

      expect(result).to be_success
    end
  end

  context 'when the trial already exists (409)' do
    before do
      allow(client).to receive(:start_product_trial).and_return(
        ::Gitlab::SubscriptionPortal::StartProductTrialResponse.new(success: false, error_code: :trial_already_active)
      )
    end

    it 'succeeds without a started event or a second audit event' do
      expect(::Gitlab::Audit::Auditor).not_to receive(:audit)
      expect { result }.not_to trigger_internal_events('orbit_instance_trial_started')

      expect(result).to be_success
    end
  end

  it 'reads the trial again after starting it in the same request' do
    eligible = instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse)
    active = instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse)
    allow(::Analytics::Orbit::Trial).to receive(:request_instance_status).and_return(eligible, active)
    account = described_class.new

    expect(account.trial).to be(eligible)

    account.start_trial(by: current_user)

    expect(account.trial).to be(active)
  end

  context 'when CDot reports the instance is ineligible' do
    before do
      allow(client).to receive(:start_product_trial).and_return(
        ::Gitlab::SubscriptionPortal::StartProductTrialResponse.new(
          success: false, error_code: :ineligible, error_message: 'subscription_not_allowed'
        )
      )
    end

    it 'returns an ineligible error and tracks the failure with the CDot reason' do
      expect { result }
        .to trigger_internal_events('orbit_instance_trial_start_failed')
        .with(user: admin, additional_properties: { label: 'ineligible', property: 'subscription_not_allowed' })

      expect(result).to be_error
      expect(result.reason).to eq(:ineligible)
    end
  end

  context 'when the started trial is not active' do
    let(:active_trial) { instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: false) }

    it 'returns a trial_ended error' do
      expect(result).to be_error
      expect(result.reason).to eq(:trial_ended)
    end
  end

  context 'when CDot is unreachable' do
    before do
      allow(client).to receive(:start_product_trial)
        .and_raise(::Gitlab::SubscriptionPortal::ProductTrialResponse::Error)
    end

    it 'reports the failure and returns unavailable' do
      expect(::Gitlab::ErrorTracking).to receive(:track_exception)

      expect(result).to be_error
      expect(result.reason).to eq(:unavailable)
    end
  end
end
