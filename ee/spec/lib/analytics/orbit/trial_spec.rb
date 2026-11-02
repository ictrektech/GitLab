# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::Trial, feature_category: :knowledge_graph do
  using RSpec::Parameterized::TableSyntax

  describe '.status_for' do
    let_it_be(:group) { create(:group) }
    let(:response) { Gitlab::SubscriptionPortal::ProductTrialResponse.new(state: :trial_eligible) }

    it 'reads the orbit trial of the group from CDot with a timeout' do
      expect(Gitlab::SubscriptionPortal::Client).to receive(:product_trial)
        .with(trial_type: :orbit, namespace_id: group.id, timeout: 2.0)
        .and_return(response)

      expect(described_class.status_for(group)).to eq(response)
    end

    it 'uses the client default timeouts when the caller gives timeout: nil' do
      expect(Gitlab::SubscriptionPortal::Client).to receive(:product_trial)
        .with(trial_type: :orbit, namespace_id: group.id, timeout: nil)
        .and_return(response)

      expect(described_class.status_for(group, timeout: nil)).to eq(response)
    end
  end

  describe '.request_status_for', :request_store do
    let_it_be(:group) { create(:group) }
    let(:response) { Gitlab::SubscriptionPortal::ProductTrialResponse.new(state: :trial_eligible) }

    it 'returns the CDot status' do
      allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial).and_return(response)

      expect(described_class.request_status_for(group)).to eq(response)
    end

    context 'when CDot does not answer' do
      let(:error) { Gitlab::SubscriptionPortal::ProductTrialResponse::UnavailableError.new('HTTP 503') }

      before do
        allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial).and_raise(error)
      end

      it 'calls CDot and tracks the error once for the request' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error, gl_namespace_id: group.id).once

        2.times { expect(described_class.request_status_for(group)).to eq(:unavailable) }

        expect(Gitlab::SubscriptionPortal::Client).to have_received(:product_trial).once
      end
    end

    context 'when CDot refuses every lookup' do
      let(:error) { Gitlab::SubscriptionPortal::ProductTrialResponse::Error.new('HTTP 429', cdot_status: 429) }

      before do
        allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial).and_raise(error)
      end

      it 'calls CDot and tracks the error once for the request' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error, gl_namespace_id: group.id).once

        2.times { expect(described_class.request_status_for(group)).to eq(:unavailable) }

        expect(Gitlab::SubscriptionPortal::Client).to have_received(:product_trial).once
      end
    end

    context 'when CDot rejects the group' do
      before do
        allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial)
          .and_raise(Gitlab::SubscriptionPortal::ProductTrialResponse::Error)
        allow(Gitlab::ErrorTracking).to receive(:track_exception)
      end

      it 'returns unavailable and calls CDot again for the next lookup' do
        2.times { expect(described_class.request_status_for(group)).to eq(:unavailable) }

        expect(Gitlab::SubscriptionPortal::Client).to have_received(:product_trial).twice
        expect(Gitlab::ErrorTracking).to have_received(:track_exception)
          .with(an_instance_of(Gitlab::SubscriptionPortal::ProductTrialResponse::Error), gl_namespace_id: group.id)
          .twice
      end
    end
  end
end
