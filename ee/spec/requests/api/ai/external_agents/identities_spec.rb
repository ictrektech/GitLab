# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Ai::ExternalAgents::Identities, :clean_gitlab_redis_rate_limiting, feature_category: :software_composition_analysis do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:non_member) { create(:user) }

  let(:agent_type) { 'claude-code' }
  let(:machine_fingerprint) { 'a' * 64 }
  let(:path) { "/projects/#{project.id}/ai_agent/identities" }

  before do
    project.reload.project_setting.update!(ai_governance_enabled: true)
  end

  shared_examples 'governed by ai_governance_enabled' do |request, success_status|
    context 'when ai_governance_enabled is false for the project' do
      before do
        project.reload.project_setting.update!(ai_governance_enabled: false)
      end

      it 'returns 403' do
        public_send(request)

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when the instance locks ai_governance_enabled on' do
      before do
        project.reload.project_setting.update!(ai_governance_enabled: false)
        stub_application_setting(ai_governance_enabled: true, lock_ai_governance_enabled: true)
      end

      it 'is not blocked' do
        public_send(request)

        expect(response).to have_gitlab_http_status(success_status)
      end
    end

    context 'when duo_external_agents_enabled is false' do
      before do
        NamespaceSetting.where(namespace_id: group.id).update_all(duo_external_agents_enabled: false)
      end

      it 'is not blocked' do
        public_send(request)

        expect(response).to have_gitlab_http_status(success_status)
      end
    end

    context 'when the ai_governance_session_gate feature flag is disabled' do
      before do
        stub_feature_flags(ai_governance_session_gate: false)
      end

      context 'when ai_governance_enabled is false for the project' do
        before do
          project.reload.project_setting.update!(ai_governance_enabled: false)
        end

        it 'is not blocked' do
          public_send(request)

          expect(response).to have_gitlab_http_status(success_status)
        end
      end

      context 'when duo_external_agents_enabled is false' do
        before do
          NamespaceSetting.where(namespace_id: group.id).update_all(duo_external_agents_enabled: false)
        end

        it 'returns 403' do
          public_send(request)

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end
    end
  end

  describe 'POST /api/v4/projects/:id/ai_agent/identities' do
    let(:params) { { agent_type: agent_type, machine_fingerprint: machine_fingerprint } }

    subject(:post_request) { post api(path, user), params: params }

    before do
      stub_licensed_features(ai_catalog: true)
      allow(group).to receive(:duo_external_agents_enabled).and_return(true)
    end

    it_behaves_like 'governed by ai_governance_enabled', :post_request, :created

    context 'when the project is in a personal namespace' do
      let_it_be(:owner) { create(:user, :with_namespace) }
      let_it_be(:personal_project) do
        create(:project, namespace: owner.namespace, organization: owner.namespace.organization)
      end

      subject(:post_request) do
        post api("/projects/#{personal_project.id}/ai_agent/identities", owner), params: params
      end

      before do
        personal_project.reload.project_setting.update!(ai_governance_enabled: true)
      end

      it 'follows the project setting on self-managed and returns 201' do
        post_request

        expect(response).to have_gitlab_http_status(:created)
      end

      context 'on GitLab.com' do
        before do
          stub_saas_features(gitlab_com_subscriptions: true)
        end

        it 'returns 403, because only groups can turn AI Governance on' do
          post_request

          expect(response).to have_gitlab_http_status(:forbidden)
        end
      end
    end

    context 'when the user is a guest on the project' do
      let_it_be(:guest) { create(:user, guest_of: project) }

      subject(:post_request) { post api(path, guest), params: params }

      it 'returns 403' do
        post_request
        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when the user is a reporter on the project' do
      let_it_be(:reporter) { create(:user, reporter_of: project) }

      subject(:post_request) { post api(path, reporter), params: params }

      it 'returns 403' do
        post_request
        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when the user is a maintainer on the project' do
      let_it_be(:maintainer) { create(:user, maintainer_of: project) }

      subject(:post_request) { post api(path, maintainer), params: params }

      it 'returns 201' do
        post_request
        expect(response).to have_gitlab_http_status(:created)
      end
    end

    context 'when the user is a developer on the project' do
      it 'creates an identity and returns 201' do
        expect { post_request }.to change { Ai::ExternalAgents::AgentIdentity.count }.by(1)

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response['agent_type']).to eq(agent_type)
        expect(json_response['revoked_at']).to be_nil
        expect(json_response).to have_key('id')
        expect(json_response).to have_key('created_at')
        expect(json_response).not_to have_key('machine_fingerprint')
      end

      it 'registers an identity for each supported agent type' do
        Ai::ExternalAgents::AgentIdentity::AGENT_TYPES.each do |type|
          post api(path, user), params: { agent_type: type, machine_fingerprint: machine_fingerprint }

          expect(response).to have_gitlab_http_status(:created)
          expect(json_response['agent_type']).to eq(type)
        end
      end

      it 'is idempotent -- returns the same record on repeat calls' do
        post_request
        first_id = json_response['id']

        post_request

        expect(response).to have_gitlab_http_status(:created)
        expect(json_response['id']).to eq(first_id)
        expect(Ai::ExternalAgents::AgentIdentity.count).to eq(1)
      end

      context 'when the identity has been revoked' do
        before do
          create(:ai_agent_identity, user: user, project: project,
            agent_type: agent_type, machine_fingerprint: machine_fingerprint,
            revoked_at: Time.current)
        end

        it 'returns 403' do
          post_request

          expect(response).to have_gitlab_http_status(:forbidden)
          expect(json_response['message']).to include('revoked')
        end
      end

      context 'when agent_type is not in the allowlist' do
        let(:params) { { agent_type: 'unknown-agent', machine_fingerprint: machine_fingerprint } }

        it 'returns 400' do
          post_request

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when machine_fingerprint is missing' do
        let(:params) { { agent_type: agent_type } }

        it 'returns 400' do
          post_request

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end

      context 'when machine_fingerprint exceeds 64 characters' do
        let(:params) { { agent_type: agent_type, machine_fingerprint: 'a' * 65 } }

        it 'returns 400' do
          post_request

          expect(response).to have_gitlab_http_status(:bad_request)
        end
      end
    end

    context 'when the user is not a member of the project' do
      subject(:post_request) { post api(path, non_member), params: params }

      it 'returns 404' do
        post_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when unauthenticated' do
      subject(:post_request) { post api(path), params: params }

      it 'returns 401' do
        post_request

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end

    context 'when the ai_catalog feature is not licensed' do
      before do
        stub_licensed_features(ai_catalog: false)
      end

      it 'returns 403' do
        post_request

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    it_behaves_like 'authorizing granular token permissions', :create_ai_agent_identity do
      let(:boundary_object) { project }
      let(:request) do
        post api("/projects/#{project.id}/ai_agent/identities", personal_access_token: pat),
          params: { agent_type: 'claude-code', machine_fingerprint: 'a' * 64 }
      end
    end

    context 'when the ai_agent_session_tracking feature flag is disabled' do
      before do
        stub_feature_flags(ai_agent_session_tracking: false)
      end

      it 'returns 404' do
        post_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the rate limit is exceeded' do
      before do
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?).and_return(true)
        allow(Gitlab::ApplicationRateLimiter).to receive(:interval)
          .with(:ai_agent_identity_registration)
          .and_return(60)
      end

      it 'returns 429' do
        post_request

        expect(response).to have_gitlab_http_status(:too_many_requests)
      end
    end
  end
end
