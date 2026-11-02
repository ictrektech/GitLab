# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe AddIndexOnZoektIndicesNodeIdLastIndexedAt, feature_category: :global_search do
  let(:index_name) { described_class::INDEX_NAME }

  it 'creates the index' do
    migrate!

    connection = described_class.new.connection
    expect(connection.index_exists?(:zoekt_indices, nil, name: index_name)).to be(true)
  end

  it 'removes the index on rollback' do
    migrate!
    schema_migrate_down!

    connection = described_class.new.connection
    expect(connection.index_exists?(:zoekt_indices, nil, name: index_name)).to be(false)
  end
end
