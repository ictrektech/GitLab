# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Graphql::Ai::DuoWorkflows::LinkFieldCallCount, feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let(:owner) { fresh_object_type }
  let(:field) do
    ::Types::BaseField.new(name: 'value', type: GraphQL::Types::String, null: true, owner: owner) do
      extension(::Gitlab::Graphql::Ai::DuoWorkflows::LinkFieldCallCount, limit: 1)
    end
  end

  let(:query) { GraphQL::Query.new(GitlabSchema) }

  def resolve_value
    resolve_field(field, { value: 'foo' }, object_type: owner, query: query)
  end

  it 'returns an error when the field is called more often than the limit' do
    resolve_value

    expect(resolve_value).to be_an_instance_of(Gitlab::Graphql::Errors::LimitError)
  end

  context 'when the limit_duo_workflow_link_fields feature flag is disabled' do
    before do
      stub_feature_flags(limit_duo_workflow_link_fields: false)
    end

    it 'does not enforce the call limit' do
      resolve_value

      expect(resolve_value).to eq('foo')
    end
  end
end
