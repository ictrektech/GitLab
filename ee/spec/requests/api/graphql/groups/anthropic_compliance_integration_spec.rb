# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Group.anthropicComplianceIntegration', feature_category: :ai_governance do
  include GraphqlHelpers

  let_it_be(:group) { create(:group, :private) }
  let_it_be(:subgroup) { create(:group, :private, parent: group) }
  let_it_be(:owner) { create(:user, owner_of: group) }
  let_it_be(:maintainer) { create(:user, maintainer_of: group) }
  let_it_be(:last_sync) { Time.zone.parse('2026-10-20T10:00:00Z') }
  let_it_be(:integration) do
    create(:ai_compliance_anthropic_integration, namespace: group, api_key: 'sk-ant-secret-value', enabled: false,
      disabled_reason: :repeated_failures, last_successful_sync_at: last_sync)
  end

  let(:fields) { 'anthropicComplianceIntegration { enabled disabledReason lastSuccessfulSyncAt updatedAt }' }
  let(:target_group) { group }
  let(:query) { graphql_query_for(:group, { full_path: target_group.full_path }, fields) }
  let(:current_user) { owner }

  subject(:request) { post_graphql(query, current_user: current_user) }

  def integration_data
    graphql_data_at(:group, :anthropic_compliance_integration)
  end

  it 'returns the integration state to an owner' do
    request

    expect(graphql_errors).to be_blank
    expect(integration_data).to eq(
      'enabled' => false,
      'disabledReason' => 'REPEATED_FAILURES',
      'lastSuccessfulSyncAt' => last_sync.iso8601,
      'updatedAt' => integration.updated_at.iso8601
    )
  end

  it 'does not return the key anywhere in the response' do
    request

    expect(response.body).not_to include('sk-ant-secret-value')
  end

  context 'when the group has no integration' do
    let_it_be(:other_group) { create(:group, owners: owner) }
    let(:target_group) { other_group }

    it 'returns null' do
      request

      expect(graphql_errors).to be_blank
      expect(integration_data).to be_nil
    end
  end

  context 'when the group is a subgroup' do
    let(:target_group) { subgroup }

    it 'returns null' do
      request

      expect(graphql_errors).to be_blank
      expect(graphql_data_at(:group)).to be_present
      expect(integration_data).to be_nil
    end
  end

  context 'when the user is a maintainer' do
    let(:current_user) { maintainer }

    it 'returns null' do
      request

      expect(graphql_errors).to be_blank
      expect(graphql_data_at(:group)).to be_present
      expect(integration_data).to be_nil
    end
  end

  context 'when the user is anonymous' do
    let(:current_user) { nil }

    it 'returns no group' do
      request

      expect(graphql_data_at(:group)).to be_nil
    end
  end

  context 'when the claude_code_compliance_api_ingestion feature flag is disabled' do
    before do
      stub_feature_flags(claude_code_compliance_api_ingestion: false)
    end

    it 'returns null' do
      request

      expect(graphql_errors).to be_blank
      expect(integration_data).to be_nil
    end
  end

  it 'avoids N+1 queries across groups' do
    query_for = ->(paths) do
      graphql_query_for(:groups, { full_paths: paths },
        "nodes { #{fields} }")
    end

    control = ActiveRecord::QueryRecorder.new { post_graphql(query_for.call([group.full_path]), current_user: owner) }

    other_groups = create_list(:group, 2, owners: owner)
    other_groups.each { |g| create(:ai_compliance_anthropic_integration, namespace: g) }
    paths = [group.full_path, *other_groups.map(&:full_path)]

    expect { post_graphql(query_for.call(paths), current_user: owner) }.not_to exceed_query_limit(control)
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL',
    [:read_group, :read_anthropic_compliance_integration] do
    let(:user) { owner }
    let(:boundary_object) { group }
    let(:request) do
      post_graphql(query, token: { personal_access_token: pat })
    end
  end

  context 'when a granular token can read the group but not the integration' do
    let(:pat) do
      create(:granular_pat, user: owner, boundary: ::Authz::Boundary.for(group), permissions: [:read_group])
    end

    it 'returns null' do
      post_graphql(query, token: { personal_access_token: pat })

      expect(graphql_data_at(:group)).to be_present
      expect(integration_data).to be_nil
    end
  end
end
