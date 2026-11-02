# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Add an issue to an Epic', feature_category: :portfolio_management do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, namespace: group) }

  let(:epic) { create(:epic, group: group) }
  let(:issue) { create(:issue, project: project) }

  let(:mutation) do
    params = { group_path: group.full_path, iid: epic.iid.to_s, issue_iid: issue.iid.to_s, project_path: project.full_path }

    graphql_mutation(:epic_add_issue, params)
  end

  shared_examples 'mutation without access' do
    it_behaves_like 'a mutation that returns a top-level access error'

    it 'does not add issue to the epic' do
      post_graphql_mutation(mutation, current_user: current_user)

      expect(issue.epic).to be_nil
    end
  end

  context 'when epics feature is disabled' do
    it_behaves_like 'mutation without access'
  end

  context 'when epics feature is enabled' do
    before do
      stub_licensed_features(epics: true)
    end

    context 'when the user is a group member' do
      before_all do
        group.add_developer(current_user)
      end

      it 'adds the issue to the epic' do
        post_graphql_mutation(mutation, current_user: current_user)
        response = graphql_mutation_response(:epic_add_issue)

        expect(response['errors']).to be_empty
        expect(response['epicIssue']['iid']).to eq(issue.iid.to_s)
        expect(response['epicIssue']['epic']['iid']).to eq(epic.iid.to_s)
        expect(issue.reload.epic).to eq(epic)
      end

      it_behaves_like 'authorizing granular token permissions for GraphQL', :create_epic_issue do
        let(:user) { current_user }
        let(:boundary_object) { group }
        let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
      end

      context 'when the issue belongs to a project in a different group' do
        let_it_be(:other_group) { create(:group) }
        let_it_be(:other_project) { create(:project, namespace: other_group, developers: current_user) }

        let(:project) { other_project }
        let(:issue) { create(:issue, project: other_project) }

        it_behaves_like 'authorizing granular token permissions for GraphQL', :create_epic_issue do
          let(:user) { current_user }
          let(:boundary_object) { group }
          let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
        end

        context 'when a granular token is scoped only to the issue project' do
          let(:pat) do
            create(:granular_pat, user: current_user, boundary: ::Authz::Boundary.for(other_project),
              permissions: 'create_work_item')
          end

          it 'denies access and does not add the issue to the epic' do
            post_graphql_mutation(mutation, token: { personal_access_token: pat })

            expect(graphql_errors).to include(
              a_hash_including('message' => include('fine-grained personal access token'))
            )
            expect(issue.reload.epic).to be_nil
          end
        end
      end
    end

    context 'when the user is not a group member' do
      it_behaves_like 'mutation without access'
    end
  end
end
