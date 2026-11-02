# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Govern::PolicyDelete, feature_category: :security_policy_management do
  it { expect(described_class.graphql_name).to eq('GovernPolicyDelete') }
  it { expect(described_class).to require_graphql_authorizations(:delete_govern_policy) }

  it 'identifies the policy by container and id' do
    expect(described_class.arguments.keys).to match_array(%w[organizationId groupPath id clientMutationId])
  end

  it 'requires only the policy id' do
    required = described_class.arguments.filter_map { |name, arg| name if arg.type.non_null? }

    expect(required).to match_array(%w[id])
  end

  it 'requires exactly one container argument' do
    expect(described_class.validators.map(&:class)).to include(Gitlab::Graphql::Validators::ExactlyOneOfValidator)
  end

  # Pins the deliberate deviation from GlobalID arguments: store policies are value
  # objects with plain integer ids, so a minted gid could not be resolved.
  it 'takes the policy id as a plain integer' do
    expect(described_class.arguments['id'].type.unwrap).to eq(GraphQL::Types::Int)
  end

  it 'returns only errors' do
    expect(described_class.fields.keys).to match_array(%w[clientMutationId errors])
  end
end
