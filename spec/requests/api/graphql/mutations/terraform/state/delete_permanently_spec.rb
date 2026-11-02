# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Permanently deleting a Terraform state',
  :aggregate_failures,
  feature_category: :infrastructure_as_code do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:state) { create(:terraform_state, project: project, deleted_at: Time.current) }
  let_it_be(:current_user) { create(:user, maintainer_of: project) }

  let(:input) { { id: state.to_global_id } }
  let(:mutation) { graphql_mutation(:terraform_state_delete_permanently, input, 'errors') }
  let(:mutation_response) { graphql_mutation_response(:terraform_state_delete_permanently) }

  subject(:perform_request) do
    post_graphql_mutation(mutation, current_user: current_user)
  end

  it_behaves_like 'a working GraphQL mutation'

  it 'enqueues a permanent destroy of the Terraform state' do
    expect(Terraform::States::DestroyWorker).to receive(:perform_async)
      .with(state.id, { 'permanent' => true, 'user_id' => current_user.id }).once

    perform_request

    expect(mutation_response['errors']).to be_blank
  end

  context 'when the delayed deletion feature is disabled' do
    before do
      stub_feature_flags(terraform_state_delayed_deletion: false)
    end

    it 'does not enqueue a permanent destroy of the Terraform state' do
      expect(Terraform::States::DestroyWorker).not_to receive(:perform_async)

      perform_request

      expect_graphql_errors_to_include(/The resource that you are attempting to access/)
    end
  end

  context 'when a protection rule applies to the state' do
    before do
      create(:terraform_state_protection_rule,
        project: project,
        state_name: state.name,
        minimum_access_level_for_write: :owner)
    end

    it 'returns the service error without enqueuing the worker' do
      expect(Terraform::States::DestroyWorker).not_to receive(:perform_async)

      perform_request

      expect(mutation_response['errors'])
        .to eq(['Write access to this Terraform state is restricted by a protection rule'])
    end
  end

  context 'when the state is not marked for deletion' do
    let_it_be(:state) { create(:terraform_state, project: project) }

    it 'returns the service error' do
      expect(Terraform::States::DestroyWorker).not_to receive(:perform_async)

      perform_request

      expect(mutation_response['errors'])
        .to eq(['State must be marked for deletion before it can be permanently deleted'])
    end
  end

  context 'when the current user does not have permission' do
    let_it_be(:developer) { create(:user, developer_of: project) }
    let_it_be(:guest) { create(:user, guest_of: project) }
    let_it_be(:non_member) { create(:user) }
    let(:anonymous) { nil }

    where(:current_user) do
      [
        ref(:developer),
        ref(:guest),
        ref(:non_member),
        ref(:anonymous)
      ]
    end

    with_them do
      it 'returns a permission error' do
        expect(Terraform::States::DestroyWorker).not_to receive(:perform_async)

        perform_request

        expect_graphql_errors_to_include(/you don't have permission to perform this action/)
      end
    end
  end

  describe 'granular PAT authorization' do
    it_behaves_like 'authorizing granular token permissions for GraphQL', :delete_terraform_state do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
