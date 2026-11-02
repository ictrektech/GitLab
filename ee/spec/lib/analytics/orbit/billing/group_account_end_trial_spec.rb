# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::Billing::GroupAccount, '#end_trial_if_over', feature_category: :knowledge_graph do
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be_with_reload(:enrollment) { create(:orbit_namespace_enrollment, namespace: group) }

  let(:status) { instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_ended?: true) }

  subject(:result) { described_class.new(group).end_trial_if_over }

  before_all do
    create(:knowledge_graph_enabled_namespace, namespace: group)
  end

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
    stub_feature_flags(orbit_trial: group)
    allow(::Analytics::Orbit::Trial).to receive(:status_for).with(group).and_return(status)
  end

  shared_examples 'keeps Orbit on' do
    it 'changes nothing' do
      expect(result).to be_error
      expect(group.reload.knowledge_graph_enabled_namespace).to be_present
      expect(enrollment.reload.trial_ended_at).to be_nil
    end

    it 'does not track the orbit_trial_ended event' do
      expect { result }.not_to trigger_internal_events('orbit_trial_ended')
    end
  end

  it 'deletes the enabled namespace and records the end', :freeze_time do
    expect(result).to be_success
    expect(group.reload.knowledge_graph_enabled_namespace).to be_nil
    expect(enrollment.reload.trial_ended_at).to eq(Time.current)
  end

  it 'tracks the orbit_trial_ended event' do
    expect { result }.to trigger_internal_events('orbit_trial_ended').with(namespace: group)
  end

  context 'when the trial has not ended' do
    let(:status) { instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_ended?: false) }

    it_behaves_like 'keeps Orbit on'
  end

  context 'when the group has an active orbit_promo add-on' do
    before do
      create(:gitlab_subscription_add_on_purchase, :orbit_promo, namespace: group)
    end

    it_behaves_like 'keeps Orbit on'

    context 'when the orbit_promo_access_gate flag is disabled' do
      before do
        stub_feature_flags(orbit_promo_access_gate: false)
      end

      it 'deletes the enabled namespace' do
        expect(result).to be_success
        expect(group.reload.knowledge_graph_enabled_namespace).to be_nil
      end
    end
  end

  context 'when the enrollment row is gone' do
    before do
      allow(group).to receive(:orbit_namespace_enrollment).and_return(nil)
    end

    it 'still turns Orbit off' do
      expect(result).to be_success
      expect(group.reload.knowledge_graph_enabled_namespace).to be_nil
    end
  end

  context 'when recording the end fails' do
    before do
      allow(group).to receive(:orbit_namespace_enrollment).and_return(enrollment)
      allow(enrollment).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
    end

    it 'keeps Orbit on' do
      expect { result }.to raise_error(ActiveRecord::RecordInvalid)
      expect(group.reload.knowledge_graph_enabled_namespace).to be_present
    end
  end

  context 'when Orbit is already off' do
    before do
      group.knowledge_graph_enabled_namespace.destroy!
    end

    it 'does not record the end' do
      expect(result).to be_error
      expect(enrollment.reload.trial_ended_at).to be_nil
    end

    it 'does not track the orbit_trial_ended event' do
      expect { result }.not_to trigger_internal_events('orbit_trial_ended')
    end
  end

  context 'when CDot does not answer' do
    before do
      allow(::Analytics::Orbit::Trial).to receive(:status_for)
        .and_raise(::Gitlab::SubscriptionPortal::ProductTrialResponse::UnavailableError)
    end

    it 'raises so the caller can stop' do
      expect { result }.to raise_error(::Gitlab::SubscriptionPortal::ProductTrialResponse::UnavailableError)
    end
  end

  context 'when CDot is shedding load' do
    before do
      allow(::Analytics::Orbit::Trial).to receive(:status_for)
        .and_raise(::Gitlab::SubscriptionPortal::ProductTrialResponse::Error.new(cdot_status: 429))
    end

    it 'raises so the caller can stop, without tracking the exception' do
      expect(::Gitlab::ErrorTracking).not_to receive(:track_exception)

      expect { result }.to raise_error(::Gitlab::SubscriptionPortal::ProductTrialResponse::Error)
    end
  end

  context 'when CDot returns an unexpected response' do
    before do
      allow(::Analytics::Orbit::Trial).to receive(:status_for)
        .and_raise(::Gitlab::SubscriptionPortal::ProductTrialResponse::Error)
    end

    it_behaves_like 'keeps Orbit on'

    it 'tracks the exception' do
      expect(::Gitlab::ErrorTracking).to receive(:track_exception)
        .with(an_instance_of(::Gitlab::SubscriptionPortal::ProductTrialResponse::Error), gl_namespace_id: group.id)

      result
    end
  end

  context 'when the orbit_trial flag is off for the group' do
    before do
      stub_feature_flags(orbit_trial: false)
    end

    it 'still ends the trial, because under the promo gate the trial row gives access' do
      expect(result).to be_success
      expect(group.reload.knowledge_graph_enabled_namespace).to be_nil
    end

    context 'when the orbit_promo_access_gate flag is disabled' do
      before do
        stub_feature_flags(orbit_promo_access_gate: false)
      end

      it_behaves_like 'keeps Orbit on'

      it 'does not call CDot' do
        expect(::Analytics::Orbit::Trial).not_to receive(:status_for)

        result
      end
    end
  end
end
