# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ModelSelection::CreditGate, feature_category: :duo_agent_platform do
  let_it_be(:namespace) { create(:group) }

  subject(:credit_gate) { described_class.new(namespace) }

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
    allow(namespace).to receive_messages(
      trial_active?: true,
      actual_plan_name: ::Plan::ULTIMATE_TRIAL,
      has_active_gitlab_credits_add_on?: false
    )
  end

  describe '#applies?' do
    context 'when self-managed' do
      let(:license) { build(:license) }

      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        allow(License).to receive_messages(
          current: license, has_active_gitlab_credits_add_on?: false, billable_license: nil
        )
        allow(license).to receive(:trial?).and_return(true)
      end

      context 'when the instance is on a trial licence without purchased credits' do
        it { expect(credit_gate.applies?).to be(true) }
      end

      context 'when the instance purchased credits' do
        before do
          allow(License).to receive_messages(
            has_active_gitlab_credits_add_on?: true, billable_license: license
          )
        end

        it { expect(credit_gate.applies?).to be(false) }
      end

      context 'when a paid licence sits underneath the trial' do
        before do
          allow(License).to receive(:billable_license).and_return(build(:license))
        end

        it { expect(credit_gate.applies?).to be(false) }
      end

      context 'when the licence is not a trial' do
        before do
          allow(license).to receive(:trial?).and_return(false)
        end

        it { expect(credit_gate.applies?).to be(false) }
      end

      context 'when there is no licence' do
        before do
          allow(License).to receive(:current).and_return(nil)
        end

        it { expect(credit_gate.applies?).to be(false) }
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(restrict_credit_gated_models_on_trials: false)
        end

        it { expect(credit_gate.applies?).to be(false) }
      end
    end

    context 'when the namespace is on an active trial without purchased credits' do
      it { expect(credit_gate.applies?).to be(true) }
    end

    context 'when the namespace is on a premium trial' do
      before do
        allow(namespace).to receive(:actual_plan_name).and_return(::Plan::PREMIUM_TRIAL)
      end

      it { expect(credit_gate.applies?).to be(true) }
    end

    context 'when a paying customer is trialling a higher tier' do
      before do
        allow(namespace).to receive(:actual_plan_name)
          .and_return(::Plan::ULTIMATE_TRIAL_PAID_CUSTOMER)
      end

      it 'does not gate them, because they already pay for a subscription' do
        expect(credit_gate.applies?).to be(false)
      end
    end

    context 'when the namespace has purchased credits' do
      before do
        allow(namespace).to receive(:has_active_gitlab_credits_add_on?).and_return(true)
      end

      it { expect(credit_gate.applies?).to be(false) }
    end

    context 'when the namespace is not on a trial' do
      before do
        allow(namespace).to receive(:trial_active?).and_return(false)
      end

      it { expect(credit_gate.applies?).to be(false) }
    end

    context 'when not on GitLab.com and the instance licence is not a trial' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        allow(License).to receive(:current).and_return(nil)
      end

      it { expect(credit_gate.applies?).to be(false) }
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(restrict_credit_gated_models_on_trials: false)
      end

      it { expect(credit_gate.applies?).to be(false) }
    end

    context 'when there is no namespace' do
      subject(:credit_gate) { described_class.new(nil) }

      it { expect(credit_gate.applies?).to be(false) }
    end
  end
end
