# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Metrics::DuoWorkflowSessionCreditsSyncSlis, feature_category: :value_stream_management do
  describe '.initialize_slis!' do
    it 'initializes the ErrorRate SLI with its single unlabelled series' do
      expect(Gitlab::Metrics::Sli::ErrorRate).to receive(:initialize_sli).with(:duo_workflow_session_credits_sync, [{}])

      described_class.initialize_slis!
    end

    it 'creates the freshness histogram series at 0, so the first observation is counted', :aggregate_failures do
      freshness = Ai::DuoWorkflows::SessionCredits::SyncFreshness
      sync_age = instance_double(Prometheus::Client::Histogram)
      awaiting = instance_double(Prometheus::Client::Histogram)
      allow(freshness).to receive_messages(sync_age_histogram: sync_age, awaiting_sync_histogram: awaiting)

      expect(sync_age).to receive(:get).with({})
      expect(awaiting).to receive(:get).with({})

      described_class.initialize_slis!
    end
  end

  describe '.record' do
    where(:error) { [true, false] }

    with_them do
      it 'increments the ErrorRate SLI' do
        expect(Gitlab::Metrics::Sli::ErrorRate[:duo_workflow_session_credits_sync])
          .to receive(:increment).with(labels: {}, error: error)

        described_class.record(error: error)
      end
    end
  end
end
