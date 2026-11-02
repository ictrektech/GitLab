# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['OrbitServiceState'], feature_category: :knowledge_graph do
  it 'maps every GraphQL value to the health state that the Orbit client returns' do
    expect(described_class.values.transform_values(&:value)).to eq(
      'HEALTHY' => 'healthy',
      'DEGRADED' => 'degraded',
      'UNHEALTHY' => 'unhealthy',
      'MIGRATING' => 'migrating',
      'UNKNOWN' => 'unknown'
    )
  end
end
