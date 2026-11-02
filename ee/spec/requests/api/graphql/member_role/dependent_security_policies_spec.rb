# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.memberRole.dependentSecurityPolicies', feature_category: :security_policy_management do
  include GraphqlHelpers

  def member_role_query
    <<~QUERY
    query {
      memberRole(id: "#{member_role.to_global_id}") {
        id
        dependentSecurityPolicies {
          name
          description
          enabled
          editPath
          yaml
        }
      }
    }
    QUERY
  end

  let_it_be(:member_role) { create(:member_role) }
  let_it_be(:user) { create(:user) }
  let_it_be(:namespace) { member_role.namespace }
  let_it_be(:policy_config) do
    create(:security_orchestration_policy_configuration, project: nil, namespace: namespace)
  end

  let_it_be(:security_policy) do
    create(:security_policy,
      security_orchestration_policy_configuration: policy_config,
      description: 'A security policy',
      content: { actions: [{ type: 'require_approval', approvals_required: 1, role_approvers: [member_role.id] }] }
    )
  end

  subject(:dependent_policies) do
    graphql_data['memberRole']['dependentSecurityPolicies']
  end

  before do
    member_role.namespace.add_owner(user)

    stub_licensed_features(custom_roles: true, security_orchestration_policies: true)
    stub_saas_features(gitlab_com_subscriptions: true)
  end

  context 'when member_role has dependent security policies' do
    before do
      policy_config.security_policy_management_project.add_owner(user)

      # 4 = 1 (before block) + up to 3 (warmup, control, assertion in N+1 test)
      allow_next_found_instances_of(Security::OrchestrationPolicyConfiguration, 4) do |configuration|
        allow(configuration).to receive_messages(policy_configuration_valid?: true, policy_last_updated_at: Time.now)
      end

      post_graphql(member_role_query, current_user: user)
    end

    it_behaves_like 'a working graphql query'

    it 'returns the dependent security policies with yaml field' do
      expect(dependent_policies.first).to include(
        'name' => security_policy.name,
        'description' => security_policy.description,
        'editPath' => Gitlab::Routing.url_helpers.edit_group_security_policy_url(
          namespace, id: CGI.escape(security_policy.name), type: 'approval_policy'
        ),
        'enabled' => true,
        'yaml' => be_present
      )
    end

    it 'avoids N+1 queries when fetching dependent security policies' do
      post_graphql(member_role_query, current_user: user)

      control = ActiveRecord::QueryRecorder.new { post_graphql(member_role_query, current_user: user) }

      create(:security_policy,
        security_orchestration_policy_configuration: policy_config,
        policy_index: 1,
        content: { actions: [{ type: 'require_approval', approvals_required: 1, role_approvers: [member_role.id] }] })

      expect { post_graphql(member_role_query, current_user: user) }.not_to exceed_query_limit(control)
    end
  end

  context 'when member_role has no dependent security policies' do
    let_it_be(:member_role_without_policies) { create(:member_role) }

    def member_role_query
      <<~QUERY
      query {
        memberRole(id: "#{member_role_without_policies.to_global_id}") {
          id
          dependentSecurityPolicies {
            name
            description
            enabled
            editPath
            yaml
          }
        }
      }
      QUERY
    end

    before do
      member_role_without_policies.namespace.add_owner(user)
      post_graphql(member_role_query, current_user: user)
    end

    it 'returns an empty array' do
      expect(dependent_policies).to be_empty
    end
  end

  context 'when an instance-level member_role is a role approver on self-managed', :enable_admin_mode do
    let_it_be(:admin) { create(:admin) }
    let_it_be(:instance_member_role) { create(:member_role, :instance) }
    let_it_be(:instance_policy) do
      create(:security_policy,
        security_orchestration_policy_configuration: policy_config,
        policy_index: 1,
        content: { actions: [{ type: 'require_approval', approvals_required: 1,
                               role_approvers: [instance_member_role.id] }] }
      )
    end

    def member_role_query
      <<~QUERY
      query {
        memberRole(id: "#{instance_member_role.to_global_id}") {
          id
          dependentSecurityPolicies {
            name
          }
        }
      }
      QUERY
    end

    before do
      stub_saas_features(gitlab_com_subscriptions: false)

      allow_next_found_instance_of(Security::OrchestrationPolicyConfiguration) do |configuration|
        allow(configuration).to receive_messages(policy_configuration_valid?: true, policy_last_updated_at: Time.now)
      end

      post_graphql(member_role_query, current_user: admin)
    end

    it_behaves_like 'a working graphql query'

    it 'returns the dependent security policies' do
      expect(dependent_policies).to contain_exactly(a_hash_including('name' => instance_policy.name))
    end
  end

  context 'when user lacks read_security_orchestration_policies permission' do
    let_it_be(:guest_user) { create(:user) }

    before_all do
      namespace.add_guest(guest_user)
    end

    before do
      post_graphql(member_role_query, current_user: guest_user)
    end

    it_behaves_like 'a working graphql query'

    it 'does not expose policy details even though policy exists', :aggregate_failures do
      expect(security_policy).to be_present
      expect(dependent_policies).to be_empty
    end
  end
end
