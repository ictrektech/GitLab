# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Security policies Integration (GraphQL fixtures)', type: :request,
  feature_category: :security_policy_management do
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  let_it_be(:owner) { create(:user) }
  let_it_be(:group) { create(:group, owners: owner) }

  let_it_be(:personal_project) { create(:project, :repository, owners: owner) }

  let_it_be(:ci_file_path) { '.gitlab-ci.yml' }

  # The single project getGroupProjectsCount asserts on, and the one the pipeline execution
  # editor picks its CI file from. Needs a repository: the query selects `repository { rootRef }`.
  let_it_be(:group_project) do
    create(:project, :repository, group: group).tap do |project|
      project.repository.create_file(
        owner,
        ci_file_path,
        'stages: [test]',
        message: 'Add a CI configuration',
        branch_name: project.default_branch_or_main
      )
    end
  end

  # Instance-level because RolesFinder ignores namespace scoping on self-managed, and
  # DEVELOPER because it is the lowest base access level `isRoleApprover` accepts.
  let_it_be(:custom_role) { create(:member_role, :instance, :developer, name: 'Custom approver') }

  # Three-way coupling: `test_setup.js` mounts the editor on this policy and the
  # update_policy fixture below stands in for saving it, so both need the same name.
  let_it_be(:edited_policy_name) { 'Run DAST in every pipeline' }

  # The disabled one is new coverage for the status column.
  let_it_be(:policy_yaml) do
    build(:orchestration_policy_yaml,
      scan_execution_policy: [
        build(:scan_execution_policy, name: edited_policy_name),
        build(:scan_execution_policy, name: 'Disabled DAST policy', enabled: false)
      ],
      approval_policy: [
        build(:approval_policy, name: 'critical vulnerability CS approvals')
      ])
  end

  # One commit gives every policy the same `updatedAt`, so GlTable's stable sort preserves
  # the app's own grouping order. `freeze: false` is for the create_merge_request example,
  # which writes to this project from inside the example rather than here.
  let_it_be(:policy_management_project, freeze: false) do
    create(:project, :repository, owners: owner).tap do |spp|
      spp.repository.create_file(
        owner,
        Security::OrchestrationPolicyConfiguration::POLICY_PATH,
        policy_yaml,
        message: 'Add security policies',
        branch_name: spp.default_branch_or_main
      )
    end
  end

  let_it_be(:project_policy_configuration) do
    create(:security_orchestration_policy_configuration,
      security_policy_management_project: policy_management_project,
      project: personal_project)
  end

  let_it_be(:group_policy_configuration) do
    create(:security_orchestration_policy_configuration, :namespace,
      security_policy_management_project: policy_management_project,
      namespace: group)
  end

  # Named for what the policy factory writes into its DAST action: the editor resolves the
  # action's profiles out of these lists, so a mismatch leaves its selectors empty.
  let_it_be(:dast_site_profile) do
    create(:dast_site_profile, name: 'Site Profile', project: personal_project)
  end

  let_it_be(:dast_scanner_profile) do
    create(:dast_scanner_profile, name: 'Scanner Profile', project: personal_project)
  end

  before do
    stub_licensed_features(security_orchestration_policies: true, security_on_demand_scans: true,
      custom_roles: true)
  end

  base_output_path = 'graphql/security_policies/integration/'
  queries_path = 'security_orchestration/graphql/queries/'
  mutations_path = 'security_orchestration/graphql/mutations/'
  dast_queries_path = 'security_configuration/dast_profiles/graphql/'

  # Pinned here so a fixture change fails in this job rather than in the jest one.
  def expected_policies
    [
      { 'name' => 'Run DAST in every pipeline', 'type' => 'scan_execution_policy', 'enabled' => true },
      { 'name' => 'Disabled DAST policy', 'type' => 'scan_execution_policy', 'enabled' => false },
      { 'name' => 'critical vulnerability CS approvals', 'type' => 'approval_policy', 'enabled' => true }
    ]
  end

  def rendered_policies
    graphql_data_at(:namespace, :securityPolicies, :nodes).map { |node| node.slice('name', 'type', 'enabled') }
  end

  # Pinned so a change to PolicyScopeAttributes fails here rather than in the jest job.
  def expected_attribute_scope_fields
    %w[includingBusinessImpactAttributes excludingBusinessImpactAttributes
      includingApplicationAttributes excludingApplicationAttributes
      includingBusinessUnitAttributes excludingBusinessUnitAttributes
      includingExposureAttributes excludingExposureAttributes]
  end

  def expect_attribute_scopes_to_be_present_and_empty
    scopes = graphql_data_at(:namespace, :securityPolicies, :nodes).map do |node|
      node['policyScope'].to_h.select { |field, _| field.end_with?('Attributes') }
    end

    expect(scopes.size).to eq(expected_policies.size)
    expect(scopes.map(&:keys)).to all(match_array(expected_attribute_scope_fields))
    # None of these policies scopes on an attribute, so every connection resolves empty.
    expect(scopes.flat_map(&:values)).to all(include('count' => 0))
  end

  describe GraphQL::Query do
    it "#{base_output_path}project_security_policies.query.graphql.json" do
      query = get_graphql_query_as_string("#{queries_path}project_security_policies.query.graphql", ee: true)

      post_graphql(query, current_user: owner, variables: {
        fullPath: personal_project.full_path,
        relationship: 'INHERITED',
        includeAttributeScopes: true
      })

      expect_graphql_errors_to_be_empty
      expect(rendered_policies).to eq(expected_policies)
      expect_attribute_scopes_to_be_present_and_empty
    end

    it "#{base_output_path}group_security_policies.query.graphql.json" do
      query = get_graphql_query_as_string("#{queries_path}group_security_policies.query.graphql", ee: true)

      post_graphql(query, current_user: owner, variables: {
        fullPath: group.full_path,
        relationship: 'INHERITED',
        includeAttributeScopes: true
      })

      expect_graphql_errors_to_be_empty
      expect(rendered_policies).to eq(expected_policies)
      expect_attribute_scopes_to_be_present_and_empty
    end

    # Named for the operation, not the query filename: loadFixturesMap keys on the former.
    it "#{base_output_path}get_group_projects_count.query.graphql.json" do
      query = get_graphql_query_as_string("#{queries_path}get_group_project_count.query.graphql", ee: true)

      post_graphql(query, current_user: owner, variables: { fullPath: group.full_path })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:group, :projects, :count)).to eq(1)
    end

    it "#{base_output_path}get_spp_linked_projects_groups.query.graphql.json" do
      query = get_graphql_query_as_string("#{queries_path}get_spp_linked_projects_groups.graphql", ee: true)

      post_graphql(query, current_user: owner, variables: { fullPath: personal_project.full_path })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :id)).to eq(personal_project.to_global_id.to_s)
      # The namespace being viewed is not itself a policy project, so both are empty.
      expect(graphql_data_at(:project, :securityPolicyProjectLinkedProjects, :nodes)).to be_empty
      expect(graphql_data_at(:project, :securityPolicyProjectLinkedGroups, :nodes)).to be_empty
    end

    # The edited policy's DAST action mounts the profile selectors, which query both lists.
    it "#{base_output_path}dast_site_profiles.query.graphql.json" do
      query = get_graphql_query_as_string("#{dast_queries_path}dast_site_profiles.query.graphql", ee: true)

      post_graphql(query, current_user: owner, variables: { fullPath: personal_project.full_path, first: 20 })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :siteProfiles, :nodes).pluck('profileName')).to eq([dast_site_profile.name])
    end

    it "#{base_output_path}dast_scanner_profiles.query.graphql.json" do
      query = get_graphql_query_as_string("#{dast_queries_path}dast_scanner_profiles.query.graphql", ee: true)

      post_graphql(query, current_user: owner, variables: { fullPath: personal_project.full_path, first: 20 })

      expect_graphql_errors_to_be_empty
      profile_names = graphql_data_at(:project, :scannerProfiles, :nodes).pluck('profileName')
      expect(profile_names).to eq([dast_scanner_profile.name])
    end

    # Both editors search members shortly after mount, so a spec that outlives the 250ms
    # debounce trips the missing-handler guard without this.
    it "#{base_output_path}search_project_members.query.graphql.json" do
      query = get_graphql_query_as_string('graphql_shared/queries/project_user_members_search.query.graphql')

      post_graphql(query, current_user: owner, variables: {
        fullPath: personal_project.full_path,
        search: ''
      })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :projectMembers, :nodes)).to be_present
    end

    # The same pickers search group members at group level, so those mounts need this.
    it "#{base_output_path}group_users_search.query.graphql.json" do
      query = get_graphql_query_as_string('graphql_shared/queries/group_users_search.query.graphql')

      post_graphql(query, current_user: owner, variables: {
        fullPath: group.full_path,
        search: ''
      })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:namespace, :users, :nodes)).to be_present
    end

    # The approver selector asks for custom roles on mount, same story as the member search.
    it "#{base_output_path}project_custom_roles.query.graphql.json" do
      query = get_graphql_query_as_string("#{queries_path}project_custom_roles.query.graphql", ee: true)

      post_graphql(query, current_user: owner, variables: { fullPath: personal_project.full_path })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :id)).to eq(personal_project.to_global_id.to_s)
      # Null, not an empty list: the field authorizes on read_member_role, which a
      # personal-namespace project cannot grant. This is what the editor really receives.
      expect(graphql_data_at(:project, :memberRoles)).to be_nil
    end

    # The group-level approver selector asks the group for its custom roles instead.
    it "#{base_output_path}group_custom_roles.query.graphql.json" do
      query = get_graphql_query_as_string("#{queries_path}group_custom_roles.query.graphql", ee: true)

      post_graphql(query, current_user: owner, variables: { fullPath: group.full_path })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:group, :id)).to eq(group.to_global_id.to_s)
      expect(graphql_data_at(:group, :memberRoles, :nodes)).to contain_exactly(
        a_hash_including('name' => custom_role.name)
      )
    end

    # The block-group-branch-modification setting queries the SPP, not the edited namespace.
    it "#{base_output_path}get_spp_linked_groups.query.graphql.json" do
      query = get_graphql_query_as_string("#{queries_path}get_spp_linked_groups.graphql", ee: true)

      post_graphql(query, current_user: owner, variables: {
        fullPath: policy_management_project.full_path,
        topLevelOnly: true
      })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :id)).to eq(policy_management_project.to_global_id.to_s)
      # The SPP enforces policies on `group`, the one exception the setting can offer.
      expect(graphql_data_at(:project, :securityPolicyProjectLinkedGroups, :nodes)).to contain_exactly(
        a_hash_including('fullPath' => group.full_path)
      )
    end

    # Backs the dropdown the pipeline execution editor picks the CI file's project from.
    it "#{base_output_path}get_group_projects.query.graphql.json" do
      query = get_graphql_query_as_string("#{queries_path}get_group_projects.query.graphql", ee: true)

      post_graphql(query, current_user: owner, variables: { fullPath: group.full_path })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:group, :projects, :nodes).pluck('fullPath')).to eq([group_project.full_path])
    end

    # A non-empty `nodes` is what `doesFileExist` reads as "the file exists".
    it "#{base_output_path}get_file.query.graphql.json" do
      query = get_graphql_query_as_string("#{queries_path}get_file.query.graphql", ee: true)

      post_graphql(query, current_user: owner, variables: {
        fullPath: group_project.full_path,
        filePath: ci_file_path,
        ref: nil
      })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:project, :repository, :blobs, :nodes).size).to eq(1)
    end
  end

  describe 'Mutations' do
    # Named for the operation, not the mutation filename: loadFixturesMap keys on the former.
    it "#{base_output_path}update_policy.mutation.graphql.json" do
      mutation = get_graphql_query_as_string("#{mutations_path}create_policy.mutation.graphql", ee: true)
      # A differing description, or the commit service rejects it as "No changes detected".
      policy = build(:scan_execution_policy,
        name: edited_policy_name,
        description: 'Edited through the policy editor')

      post_graphql(mutation, current_user: owner, variables: {
        fullPath: personal_project.full_path,
        mode: 'REPLACE',
        name: edited_policy_name,
        policyYaml: policy.merge(type: 'scan_execution_policy').deep_stringify_keys.to_yaml
      })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:scanExecutionPolicyCommit, :errors)).to be_empty
      expect(graphql_data_at(:scanExecutionPolicyCommit, :branch)).to be_present
    end

    # The second half of a save: the editor opens a merge request from the committed branch.
    it "#{base_output_path}create_merge_request.mutation.graphql.json" do
      mutation = get_graphql_query_as_string('graphql_shared/mutations/create_merge_request.mutation.graphql')
      target_branch = policy_management_project.default_branch_or_main
      source_branch = 'update-policy-fixture'

      policy_management_project.repository.create_file(
        owner,
        'policy-change.txt',
        'Policy change',
        message: 'Change the policy',
        branch_name: source_branch,
        start_branch_name: target_branch
      )

      post_graphql(mutation, current_user: owner, variables: {
        input: {
          projectPath: policy_management_project.full_path,
          sourceBranch: source_branch,
          targetBranch: target_branch,
          title: 'Update policy',
          description: '',
          removeSourceBranch: true
        }
      })

      expect_graphql_errors_to_be_empty
      expect(graphql_data_at(:mergeRequestCreate, :errors)).to be_empty
      expect(graphql_data_at(:mergeRequestCreate, :mergeRequest, :iid)).to be_present
    end
  end
end
