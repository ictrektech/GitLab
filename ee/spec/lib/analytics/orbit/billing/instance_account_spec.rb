# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::Billing::InstanceAccount, feature_category: :knowledge_graph do
  let_it_be(:group) { create(:group) }

  let(:account) { described_class.new }
  let(:current_license) { ::License.current || build(:license) }

  before do
    stub_saas_features(gitlab_com_subscriptions: false)
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_promo_access_gate: false, orbit_trial: false)
    allow(::License).to receive(:current).and_return(current_license)
    allow(current_license).to receive(:online_cloud_license?).and_return(true)
  end

  it 'keeps the facts private' do
    expect(account).not_to respond_to(:licensed?, :promo_gate?, :promo_add_on?, :trial_flow?, :trial_status)
  end

  it 'never ends a trial, because instance indexing never stops for billing' do
    expect(account).not_to respond_to(:end_trial_if_over)
  end

  describe '#eligible? and #entitled?' do
    it 'follows the instance license without the promo gate' do
      expect(account).to have_attributes(eligible?: true, entitled?: true)

      stub_licensed_features(orbit: false)

      expect(described_class.new).to have_attributes(eligible?: false, entitled?: false)
    end

    context 'with the promo gate' do
      before do
        stub_feature_flags(orbit_promo_access_gate: true)
      end

      it 'does not give access through the license alone' do
        expect(account.entitled?).to be(false)
      end

      it 'gives access through the orbit_promo add-on of the instance' do
        create(:gitlab_subscription_add_on_purchase, :orbit_promo, :self_managed)

        expect(account.entitled?).to be(true)
      end

      it 'gives access during an active instance trial' do
        stub_feature_flags(orbit_trial: true)
        allow(Analytics::Orbit::Trial).to receive(:request_instance_status).and_return(
          instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: true)
        )

        expect(account.entitled?).to be(true)
      end

      it 'gives no access while CustomersDot does not answer' do
        stub_feature_flags(orbit_trial: true)
        allow(Analytics::Orbit::Trial).to receive(:request_instance_status).and_return(:unavailable)

        expect(account.entitled?).to be(false)
      end
    end
  end

  describe '#trial_offered?' do
    before do
      stub_feature_flags(orbit_trial: true)
    end

    it 'offers the trial to a licensed instance with an online cloud license' do
      expect(account.trial_offered?).to be(true)
    end

    it 'does not offer the trial with an offline or legacy license' do
      allow(current_license).to receive(:online_cloud_license?).and_return(false)

      expect(account.trial_offered?).to be(false)
    end

    it 'offers the instance trial to every group, but no group starts it' do
      expect(account.trial_offered_to?(group)).to be(true)
      expect(account.trial_startable_by?(group)).to be(false)
    end
  end

  describe '#turn_on' do
    before do
      stub_feature_flags(orbit_promo_access_gate: true)
    end

    it 'turns on without a trial or a purchase, and does not call CustomersDot' do
      expect(Analytics::Orbit::Trial).not_to receive(:status_for_instance)

      expect(account.turn_on(group)).to be_allowed
    end

    it 'turns on before the instance trial starts' do
      stub_feature_flags(orbit_trial: true)
      allow(Analytics::Orbit::Trial).to receive(:status_for_instance).and_return(
        instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: false, trial_ended?: false)
      )

      expect(account.turn_on(group)).to be_allowed
    end

    it 'still turns on after the instance trial ended, because indexing never stops for billing' do
      stub_feature_flags(orbit_trial: true)
      expect(Analytics::Orbit::Trial).not_to receive(:status_for_instance)

      expect(account.turn_on(group)).to be_allowed
    end

    it 'turns on a beta group during the beta after the instance trial ended' do
      stub_feature_flags(orbit_promo_access_gate: false, orbit_trial: true)
      create(:orbit_namespace_enrollment, :beta, namespace: group)
      allow(Analytics::Orbit::Trial).to receive(:status_for_instance).and_return(
        instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: false, trial_ended?: true)
      )

      expect(account.turn_on(group.reload)).to be_allowed
    end
  end

  describe '#trial' do
    it 'is nil when the instance has no license, because CustomersDot cannot recognize it' do
      stub_feature_flags(orbit_trial: true)
      allow(::License).to receive(:current).and_return(nil)

      expect(account.trial).to be_nil
    end

    it 'is nil outside the trial flow' do
      expect(Analytics::Orbit::Trial).not_to receive(:request_instance_status)

      expect(account.trial).to be_nil
    end

    it 'reads the instance trial once in the trial flow' do
      stub_feature_flags(orbit_trial: true)
      trial = instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse)
      expect(Analytics::Orbit::Trial).to receive(:request_instance_status).once.and_return(trial)

      2.times { expect(account.trial).to be(trial) }
    end
  end
end
