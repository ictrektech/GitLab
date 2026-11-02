# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Group policyStore policyEvaluations', feature_category: :security_policy_management do
  include GraphqlHelpers
  include_context 'with policy store service authorization'
  include_context 'with policy store group containers'

  let_it_be(:group_developer) { create(:user, developer_of: group) }

  let_it_be(:policy) { create(:govern_policy, namespace: group) }
  let_it_be(:other_policy) { create(:govern_policy, namespace: group) }
  let_it_be(:organization_policy) { create(:govern_policy, :without_namespace, organization: organization) }

  let_it_be(:audit_allow_evaluation) do
    create(:govern_policy_evaluation, policy: policy, mode: :audit, verdict: :allow, evaluated_at: 3.days.ago)
  end

  let_it_be(:enforce_deny_evaluation) do
    create(:govern_policy_evaluation, policy: other_policy, mode: :enforce, verdict: :deny, evaluated_at: 1.day.ago)
  end

  let_it_be(:violation) do
    create(:govern_policy_violation, evaluation: enforce_deny_evaluation, details: { 'reason' => 'window closed' })
  end

  # Same organization, but not the group's: an organization-wide evaluation with no
  # project belongs to no group, and a sibling group's evaluation isn't this group's.
  let_it_be(:organization_evaluation) { create(:govern_policy_evaluation, policy: organization_policy) }

  let_it_be(:other_group_evaluation) do
    create(:govern_policy_evaluation, policy: create(:govern_policy, namespace: other_group))
  end

  let(:current_user) { group_owner }
  let(:filters) { {} }
  let(:pagination) { {} }

  let(:query) do
    <<~QUERY
      query groupPolicyStorePolicyEvaluations(
        $fullPath: ID!, $policyId: Int, $mode: GovernPolicyEvaluationMode,
        $verdict: GovernPolicyEvaluationVerdict, $evaluatedAfter: Time, $evaluatedBefore: Time,
        $first: Int, $after: String
      ) {
        group(fullPath: $fullPath) {
          policyStore {
            policyEvaluations(
              policyId: $policyId, mode: $mode, verdict: $verdict,
              evaluatedAfter: $evaluatedAfter, evaluatedBefore: $evaluatedBefore,
              first: $first, after: $after
            ) {
              pageInfo { hasNextPage endCursor }
              nodes {
                id
                policyId
                triggerType
                mode
                verdict
                policyVersion
                evaluatedAt
                projectId
                project { id name webPath }
                environmentId
                userId
                violations { id details createdAt }
              }
            }
          }
        }
      }
    QUERY
  end

  subject(:request) do
    post_graphql(
      query,
      current_user: current_user,
      variables: { fullPath: group.full_path }.merge(filters).merge(pagination)
    )
  end

  def policy_store
    graphql_data.dig('group', 'policyStore')
  end

  def run_query
    post_graphql(query, current_user: current_user, variables: { fullPath: group.full_path })
  end

  def evaluations
    policy_store&.dig('policyEvaluations', 'nodes')
  end

  describe 'the project an evaluation ran for' do
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:project_evaluation) do
      create(:govern_policy_evaluation, policy: policy, project: project, evaluated_at: 1.hour.ago)
    end

    let(:filters) { { policyId: policy.id } }

    it 'resolves the id into the project' do
      request

      expect(evaluations.first['project']).to eq(
        'id' => project.to_global_id.to_s,
        'name' => project.name,
        'webPath' => "/#{project.full_path}"
      )
    end

    # A group's policies can be evaluated against a project the viewer cannot read,
    # and project_id has no foreign key holding it to anything visible. ProjectType
    # refuses the node and the id is all that is left.
    context 'when the viewer cannot read the project' do
      let_it_be(:private_project) { create(:project, :private) }
      let_it_be(:private_evaluation) do
        create(:govern_policy_evaluation, policy: other_policy, project: private_project, evaluated_at: 1.minute.ago)
      end

      let(:filters) { { policyId: other_policy.id } }

      it 'returns the id without the project' do
        request

        expect(evaluations.first).to include('projectId' => private_project.id, 'project' => nil)
      end
    end
  end

  it "returns the evaluations of the group's own policies, newest first, with their violations" do
    request

    expect(evaluations).to match(
      [
        {
          'id' => enforce_deny_evaluation.to_global_id.to_s,
          'policyId' => other_policy.id,
          'triggerType' => 'DEPLOYMENT_REQUESTED',
          'mode' => 'ENFORCE',
          'verdict' => 'DENY',
          'policyVersion' => 1,
          'evaluatedAt' => enforce_deny_evaluation.evaluated_at.iso8601,
          'projectId' => nil,
          'project' => nil,
          'environmentId' => nil,
          'userId' => nil,
          'violations' => [
            {
              'id' => violation.to_global_id.to_s,
              'details' => { 'reason' => 'window closed' },
              'createdAt' => violation.created_at.iso8601
            }
          ]
        },
        a_hash_including(
          'id' => audit_allow_evaluation.to_global_id.to_s,
          'mode' => 'AUDIT',
          'verdict' => 'ALLOW',
          'violations' => []
        )
      ]
    )
  end

  it 'serves a group Owner who cannot read the policies of the organization' do
    expect(Ability.allowed?(group_owner, :read_govern_policy, organization)).to be(false)

    request

    expect(evaluations).to be_present
  end

  it 'avoids N+1 queries for violations' do
    run_query

    control = ActiveRecord::QueryRecorder.new { run_query }

    evaluation = create(:govern_policy_evaluation, policy: policy, evaluated_at: 2.days.ago)
    create(:govern_policy_violation, evaluation: evaluation)

    expect { run_query }.not_to exceed_query_limit(control)
  end

  describe 'filters' do
    context 'with a policyId filter' do
      let(:filters) { { policyId: policy.id } }

      it 'returns only the evaluations of the policy' do
        request

        expect(evaluations).to contain_exactly(
          a_hash_including('id' => audit_allow_evaluation.to_global_id.to_s)
        )
      end
    end

    context 'with a mode filter' do
      let(:filters) { { mode: 'ENFORCE' } }

      it 'returns only the evaluations that ran in the mode' do
        request

        expect(evaluations).to contain_exactly(
          a_hash_including('id' => enforce_deny_evaluation.to_global_id.to_s)
        )
      end
    end

    context 'with a verdict filter' do
      let(:filters) { { verdict: 'ALLOW' } }

      it 'returns only the evaluations that produced the verdict' do
        request

        expect(evaluations).to contain_exactly(
          a_hash_including('id' => audit_allow_evaluation.to_global_id.to_s)
        )
      end
    end

    context 'with a time range filter' do
      let(:filters) { { evaluatedAfter: 2.days.ago.iso8601, evaluatedBefore: Time.current.iso8601 } }

      it 'returns only the evaluations inside the range' do
        request

        expect(evaluations).to contain_exactly(
          a_hash_including('id' => enforce_deny_evaluation.to_global_id.to_s)
        )
      end
    end
  end

  describe 'pagination' do
    let(:pagination) { { first: 1 } }

    it 'paginates newest first with a usable cursor' do
      request

      expect(evaluations).to contain_exactly(
        a_hash_including('id' => enforce_deny_evaluation.to_global_id.to_s)
      )

      page_info = policy_store.dig('policyEvaluations', 'pageInfo')
      expect(page_info['hasNextPage']).to be(true)

      post_graphql(
        query,
        current_user: current_user,
        variables: { fullPath: group.full_path, first: 1, after: page_info['endCursor'] }
      )

      expect(evaluations).to contain_exactly(
        a_hash_including('id' => audit_allow_evaluation.to_global_id.to_s)
      )
    end
  end

  describe 'count' do
    let(:query) do
      <<~QUERY
        query groupPolicyStorePolicyEvaluations(
          $fullPath: ID!, $policyId: Int, $verdict: GovernPolicyEvaluationVerdict,
          $evaluatedAfter: Time, $limit: Int
        ) {
          group(fullPath: $fullPath) {
            policyStore {
              policyEvaluations(
                policyId: $policyId, verdict: $verdict, evaluatedAfter: $evaluatedAfter, first: 0
              ) {
                count(limit: $limit)
              }
            }
          }
        }
      QUERY
    end

    def count
      policy_store&.dig('policyEvaluations', 'count')
    end

    it "counts every evaluation of the group's own policies without fetching them" do
      request

      expect(count).to eq(2)
    end

    it 'counts only the evaluations the filters select' do
      post_graphql(
        query,
        current_user: current_user,
        variables: { fullPath: group.full_path, policyId: policy.id, verdict: 'ALLOW' }
      )

      expect(count).to eq(1)
    end

    it 'counts only the evaluations inside the given window' do
      post_graphql(
        query,
        current_user: current_user,
        variables: { fullPath: group.full_path, evaluatedAfter: 2.days.ago.iso8601 }
      )

      expect(count).to eq(1)
    end

    it 'counts the whole filtered relation, not the requested page' do
      post_graphql(
        query.sub('first: 0', 'first: 1'),
        current_user: current_user,
        variables: { fullPath: group.full_path }
      )

      expect(count).to eq(2)
    end

    context 'when the user cannot read the policies' do
      let(:current_user) { group_developer }

      it 'returns no connection to count rather than the number' do
        request

        expect(policy_store).to be_present
        expect(policy_store['policyEvaluations']).to be_nil
        expect_graphql_errors_to_be_empty
      end
    end

    # A bounded count returns limit + 1, which is what lets the UI render a
    # lower bound instead of paying for an exact count on a busy group.
    context 'with more evaluations than the limit' do
      let_it_be(:third_evaluation) { create(:govern_policy_evaluation, policy: policy) }

      it 'counts them all when no limit is given' do
        request

        expect(count).to eq(3)
      end

      it 'stops counting at the given limit' do
        post_graphql(
          query,
          current_user: current_user,
          variables: { fullPath: group.full_path, limit: 1 }
        )

        expect(count).to eq(2)
      end
    end
  end

  describe 'granular token permissions' do
    # The token owner has to live in the group's organization: the granular token
    # factory takes its organization from the user and rejects a mismatch.
    let(:user) { create(:user, organization: organization, owner_of: group) }
    let(:query) do
      <<~QUERY
        query groupPolicyStorePolicyEvaluations($fullPath: ID!) {
          group(fullPath: $fullPath) {
            policyStore {
              policyEvaluations { nodes { verdict } }
            }
          }
        }
      QUERY
    end

    let(:request) do
      post_graphql(query, variables: { fullPath: group.full_path }, token: { personal_access_token: pat })
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_group, :read_govern_policy] do
      let(:boundary_object) { group }
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_group, :read_govern_policy] do
      let(:boundary_object) { :instance }
    end

    # The shared example passes on an empty connection, so assert the nodes too.
    it "returns the group's evaluations to a token scoped to the group" do
      group_scoped_token = create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(group),
        permissions: [:read_group, :read_govern_policy].map do |permission|
          ::Authz::PermissionGroups::Assignable.for_permission(permission).min_by(&:name).name
        end.uniq)

      post_graphql(
        "query { group(fullPath: \"#{group.full_path}\") { policyStore { policyEvaluations { nodes { id } } } } }",
        token: { personal_access_token: group_scoped_token }
      )

      expect(graphql_data.dig('group', 'policyStore', 'policyEvaluations', 'nodes')).to contain_exactly(
        { 'id' => audit_allow_evaluation.to_global_id.to_s },
        { 'id' => enforce_deny_evaluation.to_global_id.to_s }
      )
    end

    it "returns an inherited policy's evaluation in the group's project to a token scoped to the group" do
      inherited_evaluation = create(:govern_policy_evaluation, policy: organization_policy,
        project: create(:project, group: group))
      group_scoped_token = create(:granular_pat, user: user, boundary: ::Authz::Boundary.for(group),
        permissions: [:read_group, :read_govern_policy].map do |permission|
          ::Authz::PermissionGroups::Assignable.for_permission(permission).min_by(&:name).name
        end.uniq)

      post_graphql(
        "query { group(fullPath: \"#{group.full_path}\") { policyStore { policyEvaluations { nodes { id } } } } }",
        token: { personal_access_token: group_scoped_token }
      )

      expect(graphql_data.dig('group', 'policyStore', 'policyEvaluations', 'nodes'))
        .to include({ 'id' => inherited_evaluation.to_global_id.to_s })
    end
  end

  context 'when the user is a group member without the owner role' do
    let(:current_user) { group_developer }

    it 'returns null evaluations while the catalogs stay reachable' do
      request

      expect(policy_store).to be_present
      expect(policy_store['policyEvaluations']).to be_nil
      expect_graphql_errors_to_be_empty
    end
  end

  context 'when the user owns a sibling group in the same organization' do
    let(:current_user) { create(:user, owner_of: other_group) }

    it 'returns null evaluations' do
      request

      expect(evaluations).to be_nil
      expect_graphql_errors_to_be_empty
    end
  end

  context 'when the group has not opted into the experiment' do
    let_it_be(:opted_out_group) do
      create(:group, organization: organization).tap do |g|
        g.namespace_settings.update!(policy_store_experiment_enabled: false)
        g.add_owner(group_owner)
      end
    end

    it 'returns a null policyStore' do
      post_graphql(query, current_user: current_user, variables: { fullPath: opted_out_group.full_path })

      expect(policy_store).to be_nil
    end
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(security_policies_v2: false)
    end

    it 'returns a null policyStore, so the flag works as a kill switch on its own' do
      request

      expect(policy_store).to be_nil
    end
  end
end
