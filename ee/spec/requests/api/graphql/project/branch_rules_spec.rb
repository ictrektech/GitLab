# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'getting list of branch rules for a project', feature_category: :source_code_management do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:project, freeze: false) { create(:project, :repository, :public, :in_group) }
  let_it_be(:project_maintainer) { create(:user, maintainer_of: project) }
  let_it_be(:group_maintainer) { create(:user, maintainer_of: [project, project.group]) }

  let(:branch_rules_data) { graphql_data_at('project', 'branchRules', 'nodes') }
  let(:variables) { { full_path: project.full_path, build_missing: build_missing } }
  let(:build_missing) { false }
  let(:fields) { all_graphql_fields_for('BranchRule') }
  let(:query) do
    <<~GQL
    query($fullPath: ID!, $first: Int, $after: String, $buildMissing: Boolean) {
      project(fullPath: $fullPath) {
        branchRules(first: $first, after: $after, buildMissing: $buildMissing) {
          nodes {
            #{fields}
          }
        }
      }
    }
    GQL
  end

  context 'when the user does have read_branch_rule abilities for the project' do
    let(:current_user) { project_maintainer }

    describe 'queries' do
      include_context 'when user tracking is disabled'

      let(:query) do
        <<~GQL
        query($fullPath: ID!) {
          project(fullPath: $fullPath) {
            branchRules {
              nodes {
                matchingBranchesCount
                squashOption{
                  option
                }
                externalStatusChecks{
                  nodes{
                    name
                  }
                }
              }
            }
          }
        }
        GQL
      end

      before do
        create(:protected_branch, project: project)
      end

      it 'avoids N+1 queries', :use_sql_query_cache, :aggregate_failures do
        control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
          post_graphql(query, current_user: current_user, variables: variables)
        end

        # Verify the response includes the field
        expect_n_matching_branches_count_fields(2)

        create(:protected_branch, project: project)
        create(:protected_branch, name: '*', project: project)
        create(:protected_branch, project: nil, group: project.group)

        expect do
          post_graphql(query, current_user: current_user, variables: variables)
        end.not_to exceed_all_query_limit(control)

        expect_n_matching_branches_count_fields(5)
      end

      def expect_n_matching_branches_count_fields(count)
        branch_rule_nodes = graphql_data_at('project', 'branchRules', 'nodes')
        expect(branch_rule_nodes.count).to eq(count)
        branch_rule_nodes.each do |node|
          expect(node['matchingBranchesCount']).to be_present
        end
      end
    end

    describe 'response' do
      before do
        post_graphql(query, current_user: current_user, variables: variables)
      end

      let(:all_branches_rule) { Projects::AllBranchesRule.new(project) }
      let(:all_protected_branches_rule) { Projects::AllProtectedBranchesRule.new(project) }

      # branchRules are returned in alphabetical order
      let(:all_branches_rule_data) { branch_rules_data.first }
      let(:all_protected_branches_rule_data) { branch_rules_data.second }

      context 'when custom rules are persisted' do
        let_it_be(:all_branches_external_status_check) do
          create(:external_status_check, project: project)
        end

        let_it_be(:all_branches_approval_rule) do
          create(:approval_project_rule, project: project)
        end

        let_it_be(:all_protected_branches_approval_rule) do
          create(:approval_project_rule, project: project, applies_to_all_protected_branches: true)
        end

        context 'and there are other branch rules' do
          let_it_be(:branch_name_a) { TestEnv::BRANCH_SHA.each_key.first }
          let_it_be(:branch_name_b) { 'diff-*' }
          let_it_be(:protected_branch_a, freeze: false) do
            create(:protected_branch, project: project, name: branch_name_a)
          end

          let_it_be(:protected_branch_b) do
            create(:protected_branch, project: project, name: branch_name_b)
          end

          let(:branch_rule_a) { Projects::BranchRule.new(project, protected_branch_a) }
          let(:branch_rule_b) { Projects::BranchRule.new(project, protected_branch_b) }
          let(:branch_rule_b_data) { branch_rules_data.third }
          let(:branch_rule_a_data) { branch_rules_data.fourth }

          it_behaves_like 'a working graphql query'

          it 'includes all fields', :use_sql_query_cache, :aggregate_failures do
            expect(all_branches_rule_data).to include(
              'id' => all_branches_rule.to_global_id.to_s,
              'name' => all_branches_rule.name,
              'isDefault' => all_branches_rule.default_branch?,
              'isProtected' => all_branches_rule.protected?,
              'matchingBranchesCount' => all_branches_rule.matching_branches_count,
              'branchProtection' => all_branches_rule.branch_protection,
              'createdAt' => all_branches_rule.created_at.iso8601,
              'updatedAt' => all_branches_rule.updated_at.iso8601,
              'approvalRules' => be_kind_of(Hash),
              'externalStatusChecks' => be_kind_of(Hash)
            )
            approval_rules_data = all_branches_rule_data['approvalRules']['nodes']
            expect(approval_rules_data).to eq([{
              'id' => all_branches_approval_rule.to_global_id.to_s,
              'name' => all_branches_approval_rule.name,
              'type' => 'REGULAR',
              'approvalsRequired' => 0,
              'coverageMinimumThreshold' => nil
            }])
            external_checks_data = all_branches_rule_data['externalStatusChecks']['nodes']
            expect(external_checks_data).to eq([{
              'id' => all_branches_external_status_check.to_global_id.to_s,
              'name' => all_branches_external_status_check.name,
              'externalUrl' => all_branches_external_status_check.external_url,
              'hmac' => false
            }])
            expect(all_protected_branches_rule_data).to include(
              'id' => all_protected_branches_rule.to_global_id.to_s,
              'name' => all_protected_branches_rule.name,
              'isDefault' => all_protected_branches_rule.default_branch?,
              'isProtected' => all_protected_branches_rule.protected?,
              'matchingBranchesCount' => all_protected_branches_rule.matching_branches_count,
              'branchProtection' => all_protected_branches_rule.branch_protection,
              'createdAt' => all_protected_branches_rule.created_at.iso8601,
              'updatedAt' => all_protected_branches_rule.updated_at.iso8601,
              'approvalRules' => be_kind_of(Hash),
              'externalStatusChecks' => be_kind_of(Hash)
            )
            approval_rules_data = all_protected_branches_rule_data['approvalRules']['nodes']
            expect(approval_rules_data).to eq([{
              'id' => all_protected_branches_approval_rule.to_global_id.to_s,
              'name' => all_protected_branches_approval_rule.name,
              'type' => 'REGULAR',
              'approvalsRequired' => 0,
              'coverageMinimumThreshold' => nil
            }])

            expect(branch_rule_a_data).to include(
              'id' => branch_rule_a.to_global_id.to_s,
              'name' => branch_rule_a.name,
              'isDefault' => branch_rule_a.default_branch?,
              'isProtected' => branch_rule_a.protected?,
              'matchingBranchesCount' => branch_rule_a.matching_branches_count,
              'branchProtection' => hash_including(
                "allowForcePush" => false,
                "codeOwnerApprovalRequired" => false,
                "modificationBlockedByPolicy" => false,
                "protectedFromPushBySecurityPolicy" => false,
                "isGroupLevel" => false
              ),
              'createdAt' => branch_rule_a.created_at.iso8601,
              'updatedAt' => branch_rule_a.updated_at.iso8601,
              'approvalRules' => be_kind_of(Hash),
              'externalStatusChecks' => be_kind_of(Hash)
            )

            expect(branch_rule_b_data).to include(
              'id' => branch_rule_b.to_global_id.to_s,
              'name' => branch_rule_b.name,
              'isDefault' => branch_rule_b.default_branch?,
              'isProtected' => branch_rule_b.protected?,
              'matchingBranchesCount' => branch_rule_b.matching_branches_count,
              'branchProtection' => hash_including(
                "allowForcePush" => false,
                "codeOwnerApprovalRequired" => false,
                "modificationBlockedByPolicy" => false,
                "protectedFromPushBySecurityPolicy" => false,
                "isGroupLevel" => false
              ),
              'createdAt' => branch_rule_b.created_at.iso8601,
              'updatedAt' => branch_rule_b.updated_at.iso8601,
              'approvalRules' => be_kind_of(Hash),
              'externalStatusChecks' => be_kind_of(Hash)
            )
          end
        end

        context 'when there is a group branch rule' do
          let_it_be(:group_protected_branch, freeze: false) do
            create(:protected_branch, project: nil, group: project.group)
          end

          let!(:group_branch_rule) { Projects::BranchRule.new(project, group_protected_branch) }

          let(:group_branch_rules_data) do
            branch_rules_data.find { |rule| rule['id'] == group_branch_rule.to_global_id.to_s }
          end

          it 'returns the group branch rule without its protection details', :aggregate_failures do
            expect(group_branch_rules_data).to include(
              'id' => group_branch_rule.to_global_id.to_s,
              'name' => group_branch_rule.name,
              'isGroupLevel' => true,
              'branchProtection' => nil
            )
          end

          context 'when the user does have read_protected_branch abilities for the group' do
            let(:current_user) { group_maintainer }

            it 'includes all fields', :use_sql_query_cache, :aggregate_failures do
              expect(group_branch_rules_data).to include(
                'id' => group_branch_rule.to_global_id.to_s,
                'name' => group_branch_rule.name,
                'isGroupLevel' => true,
                'isDefault' => group_branch_rule.default_branch?,
                'isProtected' => group_branch_rule.protected?,
                'matchingBranchesCount' => group_branch_rule.matching_branches_count,
                'branchProtection' => hash_including(
                  "allowForcePush" => false,
                  "codeOwnerApprovalRequired" => false,
                  "modificationBlockedByPolicy" => false,
                  "protectedFromPushBySecurityPolicy" => false,
                  "isGroupLevel" => true
                ),
                'createdAt' => group_branch_rule.created_at.iso8601,
                'updatedAt' => group_branch_rule.updated_at.iso8601,
                'approvalRules' => be_kind_of(Hash),
                'externalStatusChecks' => be_kind_of(Hash)
              )
            end
          end
        end
      end

      context 'when custom rules are not persisted' do
        context 'and build_missing is true' do
          let(:build_missing) { true }

          it_behaves_like 'a working graphql query'

          it 'includes unpersisted custom rules', :use_sql_query_cache, :aggregate_failures do
            expect(all_branches_rule_data).to include(
              'id' => all_branches_rule.to_global_id.to_s,
              'name' => all_branches_rule.name,
              'isDefault' => all_branches_rule.default_branch?,
              'isProtected' => all_branches_rule.protected?,
              'matchingBranchesCount' => all_branches_rule.matching_branches_count,
              'branchProtection' => nil,
              'createdAt' => nil,
              'updatedAt' => nil,
              'approvalRules' => a_hash_including('nodes' => []),
              'externalStatusChecks' => a_hash_including('nodes' => [])
            )

            expect(all_protected_branches_rule_data).to include(
              'id' => all_protected_branches_rule.to_global_id.to_s,
              'name' => all_protected_branches_rule.name,
              'isDefault' => all_protected_branches_rule.default_branch?,
              'isProtected' => all_protected_branches_rule.protected?,
              'matchingBranchesCount' => all_protected_branches_rule.matching_branches_count,
              'branchProtection' => nil,
              'createdAt' => nil,
              'updatedAt' => nil,
              'approvalRules' => a_hash_including('nodes' => []),
              'externalStatusChecks' => a_hash_including('nodes' => [])
            )
          end
        end

        context 'and build_missing is false' do
          let(:build_missing) { false }

          it_behaves_like 'a working graphql query'

          it 'omits unpersisted custom branch rules', :use_sql_query_cache, :aggregate_failures do
            expect(branch_rules_data).not_to include(a_hash_including(name: 'All branches'))
            expect(branch_rules_data).not_to include(a_hash_including(name: 'All protected branches'))
          end
        end
      end
    end
  end

  context 'when the user has a custom role' do
    let_it_be(:custom_role_group, freeze: false) { create(:group) }
    let_it_be(:custom_role_project, freeze: false) { create(:project, :repository, group: custom_role_group) }
    let_it_be(:custom_role_protected_branch, freeze: false) do
      create(:protected_branch, project: custom_role_project, name: 'custom-role-branch')
    end

    let_it_be(:custom_role_user) { create(:user) }
    let_it_be(:custom_role_project_member, freeze: false) do
      create(:project_member, :guest, user: custom_role_user, project: custom_role_project)
    end

    let_it_be(:external_status_check) do
      create(:external_status_check, project: custom_role_project)
    end

    let_it_be(:approval_rule) do
      create(:approval_project_rule, project: custom_role_project)
    end

    let(:current_user) { custom_role_user }
    let(:project) { custom_role_project }
    let(:build_missing) { true }
    let(:persisted) { false }

    let(:branch_rule) { Projects::BranchRule.new(custom_role_project, custom_role_protected_branch) }
    let(:branch_rule_data) do
      branch_rules_data.find { |rule| rule['id'] == branch_rule.to_global_id.to_s }
    end

    before do
      stub_licensed_features(custom_roles: true)
      create(:member_role, :guest, custom_ability, namespace: custom_role_group,
        members: [custom_role_project_member])

      # Persists the "All protected branches" rule
      create(:approval_project_rule, project: custom_role_project, applies_to_all_protected_branches: true) if persisted

      post_graphql(query, current_user: current_user, variables: variables)
    end

    context 'with admin_protected_branch' do
      let(:custom_ability) { :admin_protected_branch }

      where(:persisted, :build_missing) do
        true  | true
        true  | false
        false | true
        false | false
      end

      with_them do
        it_behaves_like 'a working graphql query'

        it 'returns only the protected branch rule' do
          expect(branch_rules_data.pluck('name')).to contain_exactly('custom-role-branch')
        end

        context 'when limiting the page size' do
          let(:variables) { { full_path: project.full_path, build_missing: build_missing, first: 1 } }

          it 'fills the page with readable branch rules' do
            expect(branch_rules_data.pluck('name')).to contain_exactly('custom-role-branch')
          end
        end
      end

      it 'does not return approval rules or external status checks', :aggregate_failures do
        expect(branch_rule_data['approvalRules']).to be_nil
        expect(branch_rule_data['externalStatusChecks']).to be_nil
      end
    end

    context 'with manage_merge_request_settings' do
      let(:custom_ability) { :manage_merge_request_settings }

      where(:persisted, :build_missing, :expected_names) do
        true  | true  | ['All branches', 'All protected branches', 'custom-role-branch']
        true  | false | ['All branches', 'All protected branches', 'custom-role-branch']
        false | true  | ['All branches', 'All protected branches', 'custom-role-branch']
        false | false | ['All branches', 'custom-role-branch']
      end

      with_them do
        it_behaves_like 'a working graphql query'

        it 'returns the readable branch rules' do
          expect(branch_rules_data.pluck('name')).to match_array(expected_names)
        end
      end

      it 'returns approval rules and external status checks', :aggregate_failures do
        all_branches_rule_data = branch_rules_data.find { |rule| rule['name'] == 'All branches' }

        expect(all_branches_rule_data['approvalRules']['nodes'].pluck('id'))
          .to contain_exactly(approval_rule.to_global_id.to_s)
        expect(all_branches_rule_data['externalStatusChecks']['nodes'].pluck('id'))
          .to contain_exactly(external_status_check.to_global_id.to_s)
      end
    end
  end
end
