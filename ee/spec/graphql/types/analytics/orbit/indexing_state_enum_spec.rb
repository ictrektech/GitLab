# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['OrbitIndexingState'], feature_category: :knowledge_graph do
  it 'maps every GraphQL value to the indexing phase that Orbit returns' do
    expect(described_class.values.transform_values(&:value)).to eq(
      'NOT_STARTED' => 'not_started',
      'INDEXING' => 'syncing',
      'READY' => 'ready',
      'FAILED' => 'error',
      'UNKNOWN' => 'unknown'
    )
  end

  it 'covers every value of the old indexing phase enum' do
    expect(described_class.values.values.map(&:value))
      .to match_array(GitlabSchema.types['OrbitIndexingPhase'].values.values.map(&:value))
  end
end
