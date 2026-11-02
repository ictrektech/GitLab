# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'AnthropicComplianceIntegrationCreate', :clean_gitlab_redis_rate_limiting,
  feature_category: :ai_governance do
  include GraphqlHelpers

  let_it_be(:group) { create(:group, :private) }
  let_it_be(:subgroup) { create(:group, :private, parent: group) }
  let_it_be(:owner) { create(:user, owner_of: group) }
  let_it_be(:maintainer) { create(:user, maintainer_of: group) }

  let(:api_key) { 'sk-ant-api01-mutation-test-key' }
  let(:sessions_url) { 'https://api.anthropic.com/v1/compliance/apps/sessions/local' }
  let(:target_group) { group }
  let(:current_user) { owner }

  let(:mutation) do
    graphql_mutation(
      :anthropic_compliance_integration_create,
      { group_path: target_group.full_path, api_key: api_key },
      <<~GQL
        anthropicComplianceIntegration { enabled disabledReason lastSuccessfulSyncAt updatedAt }
        errors
        errorReason
      GQL
    )
  end

  subject(:request) { post_graphql_mutation(mutation, current_user: current_user) }

  def mutation_response
    graphql_mutation_response(:anthropic_compliance_integration_create)
  end

  def stub_sessions(status:, body: { data: [], next_page: nil }.to_json)
    stub_request(:get, sessions_url).with(query: hash_including({}))
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  def error_body(type)
    { error: { type: type, message: 'error' } }.to_json
  end

  context 'when the owner supplies a working key' do
    before do
      stub_sessions(status: 200)
    end

    it 'stores the key and returns the enabled integration', :aggregate_failures do
      expect { request }.to change { Ai::Compliance::Anthropic::Integration.count }.by(1)

      expect(graphql_errors).to be_blank
      expect(mutation_response).to include(
        'errors' => [],
        'errorReason' => nil,
        'anthropicComplianceIntegration' => include('enabled' => true, 'disabledReason' => nil)
      )
      expect(Ai::Compliance::Anthropic::Integration.find_by(namespace: group).api_key).to eq(api_key)
    end

    it 'does not return the key in the response' do
      request

      expect(response.body).not_to include(api_key)
    end

    it 'records an audit event' do
      expect(Gitlab::Audit::Auditor).to receive(:audit).with(
        hash_including(name: 'anthropic_compliance_integration_created', author: owner, scope: group, target: group)
      ).and_call_original

      request
    end
  end

  context 'when an admin in admin mode supplies a working key', :enable_admin_mode do
    let(:current_user) { create(:admin) }

    before do
      stub_sessions(status: 200)
    end

    it 'stores the key' do
      expect { request }.to change { Ai::Compliance::Anthropic::Integration.count }.by(1)
    end
  end

  shared_examples 'a typed error' do |reason|
    it "returns #{reason} without storing or echoing the key", :aggregate_failures do
      expect { request }.not_to change { Ai::Compliance::Anthropic::Integration.count }

      expect(graphql_errors).to be_blank
      expect(mutation_response['anthropicComplianceIntegration']).to be_nil
      expect(mutation_response['errorReason']).to eq(reason)
      expect(mutation_response['errors']).to be_present
      expect(response.body).not_to include(api_key) if api_key.present?
    end

    it 'does not record an audit event' do
      expect(Gitlab::Audit::Auditor).not_to receive(:audit)

      request
    end
  end

  context 'when Anthropic rejects the key' do
    before do
      stub_sessions(status: 401, body: error_body('authentication_error'))
    end

    it_behaves_like 'a typed error', 'INVALID_KEY'
  end

  context 'when Anthropic rate limits the request' do
    before do
      stub_sessions(status: 429, body: error_body('rate_limit_error'))
    end

    it_behaves_like 'a typed error', 'RATE_LIMITED'
  end

  context 'when Anthropic cannot be reached' do
    before do
      stub_sessions(status: 500, body: error_body('api_error'))
    end

    it_behaves_like 'a typed error', 'VERIFICATION_FAILED'
  end

  context 'when the key is blank' do
    let(:api_key) { '  ' }

    it_behaves_like 'a typed error', 'BLANK_KEY'
  end

  context 'when the group already has an integration' do
    before_all do
      create(:ai_compliance_anthropic_integration, namespace: group)
    end

    before do
      stub_sessions(status: 200)
    end

    it_behaves_like 'a typed error', 'INVALID_INTEGRATION'
  end

  context 'when GitLab rate limits the request' do
    where(:limit_key) do
      %i[anthropic_compliance_key_verification_by_group anthropic_compliance_key_verification_by_user]
    end

    with_them do
      before do
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).with(limit_key, anything).and_return(true)
      end

      it_behaves_like 'a typed error', 'RATE_LIMITED'

      it 'does not contact Anthropic' do
        request

        expect(a_request(:get, sessions_url).with(query: hash_including({}))).not_to have_been_made
      end
    end
  end

  shared_examples 'a refused request' do
    it 'returns a resource-not-available error and stores nothing', :aggregate_failures do
      expect { request }.not_to change { Ai::Compliance::Anthropic::Integration.count }

      expect_graphql_errors_to_include(Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR)
      expect(a_request(:get, sessions_url).with(query: hash_including({}))).not_to have_been_made
    end
  end

  context 'when the user is a maintainer' do
    let(:current_user) { maintainer }

    it_behaves_like 'a refused request'
  end

  context 'when the user is anonymous' do
    let(:current_user) { nil }

    it_behaves_like 'a refused request'
  end

  context 'when the group is a subgroup' do
    let(:target_group) { subgroup }

    it_behaves_like 'a refused request'
  end

  context 'when the claude_code_compliance_api_ingestion feature flag is disabled' do
    before do
      stub_feature_flags(claude_code_compliance_api_ingestion: false)
    end

    it_behaves_like 'a refused request'
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :create_anthropic_compliance_integration do
    let(:user) { owner }
    let(:boundary_object) { group }
    let(:authz_mutation) do
      graphql_mutation(:anthropic_compliance_integration_create,
        { group_path: group.full_path, api_key: api_key }, 'errors')
    end

    let(:request) { post_graphql_mutation(authz_mutation, token: { personal_access_token: pat }) }

    before do
      stub_sessions(status: 200)
      Ai::Compliance::Anthropic::Integration.where(namespace: group).delete_all
    end
  end
end
