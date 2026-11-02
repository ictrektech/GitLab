# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Admin::KnowledgeGraph, feature_category: :knowledge_graph do
  let_it_be(:admin) { create(:admin) }
  let_it_be(:namespace) { create(:group) }

  before do
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_promo_access_gate: false)
  end

  shared_examples 'an API that returns 401 for unauthenticated requests' do |verb|
    it 'returns unauthorized status' do
      send(verb, api(path, nil))

      expect(response).to have_gitlab_http_status(:unauthorized)
    end
  end

  shared_examples 'an API that returns 403 for non-admin users' do |verb|
    let_it_be(:user) { create(:user) }

    it 'returns forbidden status' do
      send(verb, api(path, user))

      expect(response).to have_gitlab_http_status(:forbidden)
    end
  end

  shared_examples 'an API that requires :orbit licensed feature' do |verb|
    context 'when the :orbit licensed feature is not available' do
      before do
        stub_licensed_features(orbit: false)
      end

      it 'returns forbidden status' do
        send(verb, api(path, admin, admin_mode: true))

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end
  end

  describe 'GET /admin/knowledge_graph/namespaces' do
    let(:path) { '/admin/knowledge_graph/namespaces' }

    it_behaves_like 'an API that returns 401 for unauthenticated requests', :get
    it_behaves_like 'an API that returns 403 for non-admin users', :get
    it_behaves_like 'an API that requires :orbit licensed feature', :get

    it_behaves_like 'authorizing granular token permissions', :read_knowledge_graph_enabled_namespace do
      let(:boundary_object) { :instance }
      let(:user) { admin }
      let(:request) { get api(path, personal_access_token: pat) }
    end

    it 'returns enabled namespaces' do
      enabled_namespace = create(:knowledge_graph_enabled_namespace, namespace: namespace)

      get api(path, admin, admin_mode: true)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response).to contain_exactly(
        hash_including(
          'id' => enabled_namespace.id,
          'root_namespace_id' => namespace.id
        )
      )
    end

    it 'returns at most MAX_RESULTS most recent rows' do
      stub_const("#{described_class.name}::MAX_RESULTS", 1)

      create(:knowledge_graph_enabled_namespace)
      enabled_namespace_2 = create(:knowledge_graph_enabled_namespace)

      get api(path, admin, admin_mode: true)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response).to contain_exactly(
        hash_including('id' => enabled_namespace_2.id)
      )
    end
  end

  describe 'PUT /admin/knowledge_graph/namespaces/:id' do
    let(:namespace_id) { namespace.id }
    let(:path) { "/admin/knowledge_graph/namespaces/#{namespace_id}" }

    it_behaves_like 'an API that returns 401 for unauthenticated requests', :put
    it_behaves_like 'an API that returns 403 for non-admin users', :put
    it_behaves_like 'an API that requires :orbit licensed feature', :put

    it_behaves_like 'authorizing granular token permissions', :create_knowledge_graph_enabled_namespace do
      let(:boundary_object) { :instance }
      let(:user) { admin }
      let(:request) { put api(path, personal_access_token: pat) }
    end

    it 'creates a KnowledgeGraph::EnabledNamespace for the namespace' do
      expect do
        put api(path, admin, admin_mode: true)
      end.to change { ::Analytics::KnowledgeGraph::EnabledNamespace.count }.from(0).to(1)

      expect(response).to have_gitlab_http_status(:ok)
      enabled_namespace = ::Analytics::KnowledgeGraph::EnabledNamespace.find_by(root_namespace_id: namespace.id)
      expect(json_response['id']).to eq(enabled_namespace.id)
      expect(json_response['root_namespace_id']).to eq(namespace.id)
    end

    it 'records a direct enrollment' do
      put api(path, admin, admin_mode: true)

      expect(namespace.reload.orbit_namespace_enrollment).to be_direct
    end

    context 'with the Orbit promo access gate' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
        stub_feature_flags(orbit_promo_access_gate: namespace)
        create(:gitlab_subscription_add_on_purchase, :orbit_promo, namespace: namespace)
      end

      it 'records a direct enrollment' do
        put api(path, admin, admin_mode: true)

        expect(namespace.reload.orbit_namespace_enrollment).to be_direct
      end

      it 'turns an existing beta enrollment into a direct enrollment' do
        create(:orbit_namespace_enrollment, :beta, namespace: namespace)

        put api(path, admin, admin_mode: true)

        expect(namespace.reload.orbit_namespace_enrollment).to be_direct
      end
    end

    context 'when using namespace path' do
      let(:namespace_id) { namespace.full_path }

      it 'creates a KnowledgeGraph::EnabledNamespace for the namespace' do
        expect do
          put api(path, admin, admin_mode: true)
        end.to change { ::Analytics::KnowledgeGraph::EnabledNamespace.count }.from(0).to(1)

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when using a subgroup' do
      let_it_be(:subgroup) { create(:group, parent: namespace) }
      let(:namespace_id) { subgroup.id }

      it 'returns bad_request status' do
        put api(path, admin, admin_mode: true)

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['error']).to eq('Namespace must be a root namespace')
      end
    end

    context 'when it already exists' do
      it 'returns the existing one' do
        enabled_namespace = create(:knowledge_graph_enabled_namespace, namespace: namespace)

        put api(path, admin, admin_mode: true)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['id']).to eq(enabled_namespace.id)
      end
    end

    context 'when namespace does not exist' do
      let(:namespace_id) { non_existing_record_id }

      it 'returns not_found status' do
        put api(path, admin, admin_mode: true)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the group is excluded from indexing' do
      let_it_be(:excluded_group) { create(:group) }
      let(:namespace_id) { excluded_group.id }

      before_all do
        create(:knowledge_graph_excluded_namespace, namespace: excluded_group)
      end

      it 'returns bad_request status and records no enrollment' do
        put api(path, admin, admin_mode: true)

        expect(response).to have_gitlab_http_status(:bad_request)
        expect(json_response['message']).to include('This top-level group is excluded.')
        expect(excluded_group.reload.orbit_namespace_enrollment).to be_nil
      end
    end

    context 'when the namespace is a user namespace' do
      let_it_be(:user_namespace) { create(:user_namespace) }
      let(:namespace_id) { user_namespace.id }

      it 'returns forbidden status' do
        put api(path, admin, admin_mode: true)

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'on GitLab.com', :saas do
      context 'when the promo gate is on and the group has no add-on or active trial' do
        before do
          stub_feature_flags(orbit_promo_access_gate: namespace, orbit_trial: false)
        end

        it 'returns forbidden status and does not turn on Orbit' do
          expect do
            put api(path, admin, admin_mode: true)
          end.not_to change { ::Analytics::KnowledgeGraph::EnabledNamespace.count }

          expect(response).to have_gitlab_http_status(:forbidden)
          expect(json_response['message']).to include('Contact sales to get GitLab Orbit')
        end
      end

      context 'when the trial of the group has ended' do
        before do
          stub_feature_flags(orbit_promo_access_gate: false, orbit_trial: namespace)
          allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial)
            .and_return(Gitlab::SubscriptionPortal::ProductTrialResponse.new(state: :expired))
        end

        it 'returns forbidden status' do
          put api(path, admin, admin_mode: true)

          expect(response).to have_gitlab_http_status(:forbidden)
          expect(json_response['message']).to include('trial for this group has ended')
        end
      end

      context 'when CustomersDot does not answer for a group in the trial flow' do
        before do
          stub_feature_flags(orbit_promo_access_gate: false, orbit_trial: namespace)
          allow(Gitlab::SubscriptionPortal::Client).to receive(:product_trial)
            .and_raise(Gitlab::SubscriptionPortal::ProductTrialResponse::UnavailableError.new('HTTP 503'))
        end

        it 'returns service_unavailable status' do
          put api(path, admin, admin_mode: true)

          expect(response).to have_gitlab_http_status(:service_unavailable)
        end
      end
    end
  end

  describe 'DELETE /admin/knowledge_graph/namespaces/:id' do
    let(:namespace_id) { namespace.id }
    let(:path) { "/admin/knowledge_graph/namespaces/#{namespace_id}" }

    it_behaves_like 'an API that returns 401 for unauthenticated requests', :delete
    it_behaves_like 'an API that returns 403 for non-admin users', :delete
    it_behaves_like 'an API that requires :orbit licensed feature', :delete

    context 'when enabled namespace exists' do
      let!(:enabled_namespace) { create(:knowledge_graph_enabled_namespace, namespace: namespace) }

      it_behaves_like 'authorizing granular token permissions', :delete_knowledge_graph_enabled_namespace do
        let(:boundary_object) { :instance }
        let(:user) { admin }
        let(:request) { delete api(path, personal_access_token: pat) }
      end

      it 'removes the KnowledgeGraph::EnabledNamespace' do
        expect do
          delete api(path, admin, admin_mode: true)
        end.to change { ::Analytics::KnowledgeGraph::EnabledNamespace.count }.by(-1)

        expect(response).to have_gitlab_http_status(:no_content)
      end

      context 'when using namespace path' do
        let(:namespace_id) { namespace.full_path }

        it 'removes the KnowledgeGraph::EnabledNamespace' do
          expect do
            delete api(path, admin, admin_mode: true)
          end.to change { ::Analytics::KnowledgeGraph::EnabledNamespace.count }.by(-1)

          expect(response).to have_gitlab_http_status(:no_content)
        end
      end

      context 'when using a subgroup' do
        let_it_be(:subgroup) { create(:group, parent: namespace) }
        let(:namespace_id) { subgroup.id }

        it 'returns bad_request status' do
          delete api(path, admin, admin_mode: true)

          expect(response).to have_gitlab_http_status(:bad_request)
          expect(json_response['error']).to eq('Namespace must be a root namespace')
        end
      end
    end

    context 'when enabled namespace does not exist' do
      it 'returns not_found status' do
        delete api(path, admin, admin_mode: true)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when namespace does not exist' do
      let(:namespace_id) { non_existing_record_id }

      it 'returns not_found status' do
        delete api(path, admin, admin_mode: true)

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end
end
