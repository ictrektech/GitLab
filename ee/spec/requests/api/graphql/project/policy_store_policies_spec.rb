# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Project policyStore policies', feature_category: :security_policy_management do
  include GraphqlHelpers
  include_context 'with policy store service authorization'
  include_context 'with policy store group containers'

  let_it_be(:subgroup) { create(:group, parent: group, organization: organization) }
  let_it_be(:sibling_subgroup) { create(:group, parent: group, organization: organization) }
  let_it_be(:project) { create(:project, group: subgroup, organization: organization) }
  let_it_be(:project_developer) { create(:user, developer_of: project) }
  let_it_be(:project_reporter) { create(:user, reporter_of: project) }
  let_it_be(:project_guest) { create(:user, guest_of: project) }

  let_it_be(:organization_policy) { create(:govern_policy, :without_namespace, organization: organization) }
  let_it_be(:group_policy) { create(:govern_policy, namespace: group) }
  let_it_be(:subgroup_policy) { create(:govern_policy, namespace: subgroup) }
  let_it_be(:sibling_subgroup_policy) { create(:govern_policy, namespace: sibling_subgroup) }
  let_it_be(:other_group_policy) { create(:govern_policy, namespace: other_group) }

  let(:current_user) { project_developer }

  let(:query) do
    <<~QUERY
      query projectPolicyStorePolicies($fullPath: ID!) {
        project(fullPath: $fullPath) {
          policyStore {
            policies { nodes { id inherited } }
          }
        }
      }
    QUERY
  end

  subject(:request) { post_graphql(query, current_user: current_user, variables: { fullPath: project.full_path }) }

  def policy_store
    graphql_data.dig('project', 'policyStore')
  end

  def policies
    policy_store&.dig('policies', 'nodes')
  end

  it "lists the organization's and its groups' policies as inherited, but not a sibling group's" do
    request

    expect(policies).to contain_exactly(
      { 'id' => organization_policy.id, 'inherited' => true },
      { 'id' => group_policy.id, 'inherited' => true },
      { 'id' => subgroup_policy.id, 'inherited' => true }
    )
  end

  it 'can be resolved for only one project per request' do
    other_project = create(:project, group: sibling_subgroup, organization: organization,
      developers: [project_developer])

    post_graphql(<<~QUERY, current_user: current_user)
      {
        first: project(fullPath: "#{project.full_path}") { policyStore { policies { nodes { id } } } }
        second: project(fullPath: "#{other_project.full_path}") { policyStore { policies { nodes { id } } } }
      }
    QUERY

    expect_graphql_errors_to_include('"policyStore" field can be requested only for 1 Project(s) at a time.')
  end

  context 'when the user is a project reporter' do
    let(:current_user) { project_reporter }

    it 'returns null policies' do
      request

      expect(policy_store).to be_present
      expect(policy_store['policies']).to be_nil
    end
  end

  context 'when the user is a project guest' do
    let(:current_user) { project_guest }

    it 'returns null policies' do
      request

      expect(policy_store).to be_present
      expect(policy_store['policies']).to be_nil
    end
  end

  context "when the project's top-level group has not opted into the experiment" do
    let_it_be(:opted_out_group) { create(:group, organization: organization) }
    let_it_be(:opted_out_project) do
      create(:project, group: opted_out_group, organization: organization, developers: [project_developer])
    end

    it 'returns a null policyStore' do
      post_graphql(query, current_user: current_user, variables: { fullPath: opted_out_project.full_path })

      expect(policy_store).to be_nil
    end
  end

  describe 'granular token permissions' do
    let(:user) { create(:user, organization: organization, developer_of: project) }
    let(:request) do
      post_graphql(query, variables: { fullPath: project.full_path }, token: { personal_access_token: pat })
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_project, :read_govern_policy] do
      let(:boundary_object) { project }
    end

    context 'with a token scoped to the project' do
      let(:pat) do
        assignables = [:read_project, :read_govern_policy].map do |permission|
          ::Authz::PermissionGroups::Assignable.for_permission(permission).min_by(&:name).name
        end

        create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(project), permissions: assignables.uniq)
      end

      it 'returns the policies that apply to the project' do
        request

        expect(policies).to contain_exactly(
          a_hash_including('id' => organization_policy.id),
          a_hash_including('id' => group_policy.id),
          a_hash_including('id' => subgroup_policy.id)
        )
      end

      it 'returns an empty evaluations list, even with an evaluation recorded against the project' do
        create(:govern_policy_evaluation, policy: group_policy, project: project)

        post_graphql(
          query.sub('policies { nodes { id inherited } }', 'policyEvaluations { nodes { id } }'),
          variables: { fullPath: project.full_path }, token: { personal_access_token: pat }
        )

        expect(policy_store.dig('policyEvaluations', 'nodes')).to eq([])
      end
    end
  end
end
