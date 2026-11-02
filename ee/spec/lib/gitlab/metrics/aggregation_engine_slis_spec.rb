# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Metrics::AggregationEngineSlis, feature_category: :value_stream_management do
  describe '.measure' do
    it 'labels the query with the engine name at runtime' do
      engine = Analytics::AggregationEngines::Deployments.new(context: {})

      expect(Gitlab::Metrics::Sli::ErrorRate[:aggregation_engine_query]).to receive(:increment).with(
        labels: { engine: 'deployments', query_type: 'count', feature_category: 'value_stream_management' },
        error: false
      )

      described_class.measure(engine: engine, query_type: :count) { 1 }
    end
  end
end
