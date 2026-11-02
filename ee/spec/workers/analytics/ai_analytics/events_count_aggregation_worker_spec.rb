# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::AiAnalytics::EventsCountAggregationWorker, feature_category: :value_stream_management do
  it 'has the `until_executed` deduplicate strategy' do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
  end

  describe '#perform' do
    it 'is a no-op' do
      expect { described_class.new.perform }.not_to raise_error
    end
  end
end
