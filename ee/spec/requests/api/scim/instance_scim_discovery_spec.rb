# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Instance SCIM discovery endpoints', feature_category: :system_access do
  include LoginHelpers

  let_it_be(:organization) { create(:organization) }
  let_it_be(:user) { create(:user, organizations: [organization]) }
  let_it_be(:scim_token) { create(:scim_oauth_access_token, group: nil, organization: organization) }

  let(:token) { scim_token }
  let(:base_url) { 'http://localhost/api/scim/v2/application' }
  let(:user_resource_type) do
    {
      'schemas' => ['urn:ietf:params:scim:schemas:core:2.0:ResourceType'],
      'id' => 'User',
      'name' => 'User',
      'endpoint' => '/Users',
      'description' => 'User Account',
      'schema' => 'urn:ietf:params:scim:schemas:core:2.0:User',
      'meta' => { 'resourceType' => 'ResourceType', 'location' => "#{base_url}/ResourceTypes/User" }
    }
  end

  let(:group_resource_type) do
    {
      'schemas' => ['urn:ietf:params:scim:schemas:core:2.0:ResourceType'],
      'id' => 'Group',
      'name' => 'Group',
      'endpoint' => '/Groups',
      'description' => 'Group',
      'schema' => 'urn:ietf:params:scim:schemas:core:2.0:Group',
      'meta' => { 'resourceType' => 'ResourceType', 'location' => "#{base_url}/ResourceTypes/Group" }
    }
  end

  before do
    stub_licensed_features(instance_level_scim: true)
    stub_basic_saml_config
    allow(Gitlab::Auth::OAuth::Provider).to receive(:providers).and_return([:saml])
  end

  def scim_api(path)
    api("scim/v2/application/#{path}", user, version: '', access_token: token)
  end

  shared_examples 'a SCIM discovery endpoint' do
    context 'without a SCIM token' do
      let(:token) { nil }

      it 'responds with 401' do
        api_request

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'on GitLab.com', :saas do
      it 'responds with 404' do
        api_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the instance_level_scim license feature is not available' do
      before do
        stub_licensed_features(instance_level_scim: false)
      end

      it 'responds with 404' do
        api_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the scim_discovery_endpoints feature flag is disabled' do
      before do
        stub_feature_flags(scim_discovery_endpoints: false)
      end

      it 'responds with 404' do
        api_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when instance SAML SSO is not enabled' do
      before do
        allow(Gitlab::Auth::Saml::Config).to receive(:enabled?).and_return(false)
      end

      it 'responds with 403' do
        api_request

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end
  end

  describe 'GET api/scim/v2/application/ServiceProviderConfig' do
    subject(:api_request) { get scim_api('ServiceProviderConfig') }

    it_behaves_like 'a SCIM discovery endpoint'

    it 'returns the service provider configuration' do
      api_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['schemas']).to eq(['urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig'])
      expect(json_response['documentationUri']).to end_with('/help/administration/settings/scim_setup.md')
      expect(json_response['authenticationSchemes'].pluck('type')).to eq(%w[oauthbearertoken])
      expect(json_response['meta']['location']).to eq("#{base_url}/ServiceProviderConfig")
    end
  end

  describe 'GET api/scim/v2/application/ResourceTypes' do
    subject(:api_request) { get scim_api('ResourceTypes') }

    it_behaves_like 'a SCIM discovery endpoint'

    it 'returns the User and Group resource types' do
      api_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['totalResults']).to eq(2)
      expect(json_response['Resources']).to eq([user_resource_type, group_resource_type])
    end

    context 'when a filter parameter is present' do
      subject(:api_request) { get scim_api('ResourceTypes'), params: { filter: 'name eq "User"' } }

      it 'responds with 403' do
        api_request

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['detail']).to eq('Filtering is not supported on this endpoint')
      end
    end
  end

  describe 'GET api/scim/v2/application/ResourceTypes/:id' do
    subject(:api_request) { get scim_api('ResourceTypes/Group') }

    it_behaves_like 'a SCIM discovery endpoint'

    it 'returns the resource type' do
      api_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response).to eq(group_resource_type)
    end
  end

  describe 'GET api/scim/v2/application/Schemas' do
    subject(:api_request) { get scim_api('Schemas') }

    it_behaves_like 'a SCIM discovery endpoint'

    it 'returns the User and Group schemas' do
      api_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['totalResults']).to eq(2)
      expect(json_response['Resources'].pluck('id')).to eq(
        %w[urn:ietf:params:scim:schemas:core:2.0:User urn:ietf:params:scim:schemas:core:2.0:Group]
      )
    end

    context 'when a filter parameter is present' do
      subject(:api_request) { get scim_api('Schemas'), params: { filter: 'name eq "User"' } }

      it 'responds with 403' do
        api_request

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['detail']).to eq('Filtering is not supported on this endpoint')
      end
    end
  end

  describe 'GET api/scim/v2/application/Schemas/:id' do
    subject(:api_request) { get scim_api("Schemas/#{schema_id}") }

    let(:schema_id) { 'urn:ietf:params:scim:schemas:core:2.0:Group' }

    it_behaves_like 'a SCIM discovery endpoint'

    it 'returns the schema identified by a URN containing dots' do
      api_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['schemas']).to eq(['urn:ietf:params:scim:schemas:core:2.0:Schema'])
      expect(json_response['id']).to eq(schema_id)
      expect(json_response['attributes'].pluck('name')).to eq(%w[id displayName members])
      expect(json_response['meta']['location']).to eq("#{base_url}/Schemas/#{schema_id}")
    end

    context 'when requesting the User schema' do
      let(:schema_id) { 'urn:ietf:params:scim:schemas:core:2.0:User' }

      it 'includes the read-only groups attribute' do
        api_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['attributes'].pluck('name')).to include('groups')
      end
    end

    context 'when the schema does not exist' do
      let(:schema_id) { 'urn:ietf:params:scim:schemas:extension:enterprise:2.0:User' }

      it 'responds with 404' do
        api_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end
end
