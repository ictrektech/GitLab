# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Govern::PolicyStoreRoleType, feature_category: :security_policy_management do
  specify { expect(described_class.graphql_name).to eq('PolicyStoreRole') }

  it 'has the expected fields' do
    expected_fields = %w[id name]

    expect(described_class).to have_graphql_fields(*expected_fields).only
  end

  describe '#id' do
    let(:type_instance) { described_class.send(:new, { id: 'release_manager', name: 'Release Manager' }, context) }
    let(:context) { instance_double(GraphQL::Query::Context) }

    # Without the override BaseObject#id raises on these plain hash catalog entries, which
    # the field assertions above cannot catch because they never resolve the field.
    it 'returns the catalog id rather than a global id' do
      expect(type_instance.id).to eq('release_manager')
    end
  end
end
