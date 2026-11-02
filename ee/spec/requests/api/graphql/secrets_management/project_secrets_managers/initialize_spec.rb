# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Initialize secrets manager on a project', :gitlab_secrets_manager, feature_category: :secrets_management do
  include GraphqlHelpers

  let_it_be_with_reload(:project) { create(:project, group: create(:group)) }
  let_it_be(:current_user) { create(:user) }
  let_it_be(:mutation_name) { :project_secrets_manager_initialize }

  let(:mutation) { graphql_mutation(mutation_name, project_path: project.full_path) }
  let(:mutation_response) { graphql_mutation_response(mutation_name) }

  subject(:post_mutation) { post_graphql_mutation(mutation, current_user: current_user) }

  before do
    enroll_instance_in_secrets_manager
  end

  context 'when current user is not part of the project' do
    it_behaves_like 'a mutation on an unauthorized resource'
  end

  # Reporters get no default policy at provisioning, so they may not provision.
  context 'when current user is a project reporter' do
    before_all do
      project.add_reporter(current_user)
    end

    it_behaves_like 'a mutation on an unauthorized resource'
  end

  # Developers and Maintainers are in the project's default role policies, so
  # they may provision.
  shared_examples 'a role that initializes the project secrets manager' do
    it 'initializes the secrets manager on the project', :aggregate_failures do
      post_mutation

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(graphql_data_at(mutation_name, :project_secrets_manager, :status)).to eq('PROVISIONING')
    end
  end

  context 'when current user is a project developer' do
    before_all do
      project.add_developer(current_user)
    end

    it_behaves_like 'a role that initializes the project secrets manager'
  end

  context 'when current user is a project maintainer' do
    before_all do
      project.add_maintainer(current_user)
    end

    it_behaves_like 'a role that initializes the project secrets manager'
  end

  context 'when current user is the project owner' do
    before_all do
      project.add_owner(current_user)
    end

    it_behaves_like 'a secrets manager mutation blocked on an inactive namespace' do
      let(:inactive_namespace) { project }
    end

    it_behaves_like 'a secrets manager mutation blocked on entitlement' do
      let(:payload_key) { 'projectSecretsManager' }
      let(:service_class) { SecretsManagement::ProjectSecretsManagers::InitializeService }
    end

    context 'and project has not initialized a secrets manager' do
      it 'initializes the secrets manager on the project', :aggregate_failures do
        post_mutation

        expect(response).to have_gitlab_http_status(:success)
        expect(mutation_response['errors']).to be_empty

        expect(graphql_data_at(mutation_name, :project_secrets_manager))
          .to match(a_graphql_entity_for(
            project: a_graphql_entity_for(project),
            status: 'PROVISIONING'
          ))
      end

      it_behaves_like 'internal event tracking' do
        let(:event) { 'enable_ci_secrets_manager_for_project' }
        let(:namespace) { project.namespace }
        let(:user) { current_user }
        let(:category) { 'SecretsManagement::ProjectSecretsManagers::InitializeService' }
      end
    end

    context 'and service results to a failure' do
      before do
        allow_next_instance_of(SecretsManagement::ProjectSecretsManagers::InitializeService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'some error'))
        end
      end

      it 'returns the service error' do
        expect_next_instance_of(SecretsManagement::ProjectSecretsManagers::InitializeService) do |service|
          result = ServiceResponse.error(message: 'some error')
          expect(service).to receive(:execute).and_return(result)
        end

        post_mutation

        expect(mutation_response['errors']).to include('some error')
      end

      it_behaves_like 'internal event not tracked'
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :provision_secrets_manager do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
