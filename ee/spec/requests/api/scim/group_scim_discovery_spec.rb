# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Group SCIM discovery endpoints', feature_category: :system_access do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:saml_provider) { create(:saml_provider, group: group) }
  let_it_be(:scim_token) { create(:group_scim_auth_access_token, group: group) }

  let(:token) { scim_token }
  let(:base_url) { "http://localhost/api/scim/v2/groups/#{group.full_path}" }
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

  before do
    stub_licensed_features(group_saml: true)
  end

  def scim_api(path)
    api("scim/v2/groups/#{group.full_path}/#{path}", user, version: '', access_token: token)
  end

  shared_examples 'a SCIM discovery endpoint' do
    context 'without a SCIM token' do
      let(:token) { nil }

      it 'responds with 401' do
        api_request

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'with a SCIM token for another group' do
      let(:token) { create(:group_scim_auth_access_token, group: create(:group)) }

      it 'responds with 401' do
        api_request

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when the group does not have SAML SSO configured' do
      let_it_be(:group) { create(:group) }
      let_it_be(:scim_token) { create(:group_scim_auth_access_token, group: group) }

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

    context 'when the scim_discovery_endpoints feature flag is enabled for the group' do
      before do
        stub_feature_flags(scim_discovery_endpoints: group)
      end

      it 'responds with 200' do
        api_request

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when group SAML is not enabled for the instance' do
      before do
        allow(Gitlab::Auth::GroupSaml::Config).to receive(:enabled?).and_return(false)
      end

      it 'responds with 403' do
        api_request

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end
  end

  describe 'GET api/scim/v2/groups/:group/ServiceProviderConfig' do
    subject(:api_request) { get scim_api('ServiceProviderConfig') }

    it_behaves_like 'a SCIM discovery endpoint'

    it 'returns the service provider configuration' do
      api_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['schemas']).to eq(['urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig'])
      expect(json_response['documentationUri']).to end_with('/help/user/group/saml_sso/scim_setup.md')
      expect(json_response['patch']).to eq('supported' => true)
      expect(json_response['bulk']).to include('supported' => false)
      expect(json_response['meta']).to eq(
        'resourceType' => 'ServiceProviderConfig', 'location' => "#{base_url}/ServiceProviderConfig"
      )
    end
  end

  describe 'GET api/scim/v2/groups/:group/ResourceTypes' do
    subject(:api_request) { get scim_api('ResourceTypes') }

    it_behaves_like 'a SCIM discovery endpoint'

    it 'returns only the User resource type' do
      api_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['schemas']).to eq(['urn:ietf:params:scim:api:messages:2.0:ListResponse'])
      expect(json_response['totalResults']).to eq(1)
      expect(json_response['Resources']).to eq([user_resource_type])
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

  describe 'GET api/scim/v2/groups/:group/ResourceTypes/:id' do
    subject(:api_request) { get scim_api("ResourceTypes/#{resource_type_id}") }

    let(:resource_type_id) { 'User' }

    it_behaves_like 'a SCIM discovery endpoint'

    it 'returns the resource type' do
      api_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response).to eq(user_resource_type)
    end

    context 'when the resource type is not available for group SCIM' do
      let(:resource_type_id) { 'Group' }

      it 'responds with 404' do
        api_request

        expect(response).to have_gitlab_http_status(:not_found)
        expect(json_response['detail']).to eq('Resource type Group not found')
      end
    end
  end

  describe 'GET api/scim/v2/groups/:group/Schemas' do
    subject(:api_request) { get scim_api('Schemas') }

    it_behaves_like 'a SCIM discovery endpoint'

    it 'returns only the User schema' do
      api_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['schemas']).to eq(['urn:ietf:params:scim:api:messages:2.0:ListResponse'])
      expect(json_response['totalResults']).to eq(1)
      expect(json_response['Resources'].pluck('id')).to eq(['urn:ietf:params:scim:schemas:core:2.0:User'])
    end

    context 'when a filter parameter is present' do
      subject(:api_request) { get scim_api('Schemas'), params: { filter: 'name eq "User"' } }

      it 'responds with 403' do
        api_request

        expect(response).to have_gitlab_http_status(:forbidden)
        expect(json_response['detail']).to eq('Filtering is not supported on this endpoint')
      end

      context 'without a SCIM token' do
        let(:token) { nil }

        it 'responds with 401' do
          api_request

          expect(response).to have_gitlab_http_status(:unauthorized)
        end
      end
    end
  end

  describe 'GET api/scim/v2/groups/:group/Schemas/:id' do
    subject(:api_request) { get scim_api("Schemas/#{schema_id}") }

    let(:schema_id) { 'urn:ietf:params:scim:schemas:core:2.0:User' }

    it_behaves_like 'a SCIM discovery endpoint'

    it 'returns the schema identified by a URN containing dots' do
      api_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['schemas']).to eq(['urn:ietf:params:scim:schemas:core:2.0:Schema'])
      expect(json_response['id']).to eq(schema_id)
      expect(json_response['name']).to eq('User')
      expect(json_response['attributes'].pluck('name')).to include('userName', 'emails', 'active')
      expect(json_response['attributes'].pluck('name')).not_to include('groups')
      expect(json_response['meta']).to eq('resourceType' => 'Schema', 'location' => "#{base_url}/Schemas/#{schema_id}")
    end

    context 'when the schema is not available for group SCIM' do
      let(:schema_id) { 'urn:ietf:params:scim:schemas:core:2.0:Group' }

      it 'responds with 404' do
        api_request

        expect(response).to have_gitlab_http_status(:not_found)
        expect(json_response['detail']).to eq("Schema #{schema_id} not found")
      end

      context 'without a SCIM token' do
        let(:token) { nil }

        it 'responds with 401' do
          api_request

          expect(response).to have_gitlab_http_status(:unauthorized)
        end
      end
    end
  end
end
