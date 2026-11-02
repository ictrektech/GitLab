# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Analytics::AiMetrics::AgentPlatformMetricsType, feature_category: :value_stream_management do
  it 'has a count field for each user action event' do
    expect(described_class.fields).to include('createdSessionEventCount')
  end

  it 'omits the count field for events that are not user actions' do
    expect(described_class.fields).not_to include('reportAgentPlatformTokenUsageSessionEventCount')
  end

  it 'omits the count field for events the session rollup does not store yet' do
    expect(described_class.fields).not_to include('inputRequiredSessionEventCount')
  end
end
