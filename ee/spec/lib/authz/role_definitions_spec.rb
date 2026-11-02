# frozen_string_literal: true

require 'spec_helper'

# Every role YAML in config/authz/roles is tested automatically. The fixture opens every licensed
# feature and as many settings-based gates as practical, so a role should enable exactly the
# permissions its YAML lists. Policy specs then only need to cover the prevent rules.
# It runs only in GitLab.com (:saas) mode, where more gates open than on self-managed.
RSpec.describe Authz::Role, :saas, feature_category: :permissions do
  # Scopes a role's YAML declares but the spec can't test it in, e.g. bots can never be group members.
  inapplicable_scopes = {
    dependency_management_service_account: [:group],
    descendant_project_member: [:project],
    security_policy_bot: [:group]
  }

  let_it_be_with_refind(:organization) { create(:organization, :private) }
  # Developers need the project creation level lowered to be granted create_projects.
  let_it_be(:private_group) do
    create(:group, :private, organization: organization,
      project_creation_level: Gitlab::Access::DEVELOPER_PROJECT_ACCESS)
  end

  let_it_be(:private_project) { create(:project, :private, group: private_group, lfs_enabled: true) }
  let_it_be(:public_group) { create(:group, :public) }
  let_it_be(:public_project) { create(:project, :public, group: public_group, lfs_enabled: true) }

  # Policy conditions the fixture can't open, mapped to the permissions they withhold from every
  # role. Each one is still checked to be withheld, so remove it here once its gate is opened.
  let(:withheld_permissions) do
    {
      project: {
        duo_workflow_available: %i[create_duo_workflow_for_ci duo_workflow manage_ai_flow_triggers
          read_ai_flow_triggers trigger_ai_flow],
        security_policy_project: %i[_contribute_security_policy_project modify_security_policy],
        orbit_licensed: [:read_code_navigation],
        push_repository_for_job_token_allowed: [:build_push_code],
        policy_store_experiment_active: [:read_govern_policy]
      },
      group: {
        duo_workflow_available: %i[admin_duo_workflow create_duo_workflow_for_ci duo_workflow
          manage_ai_flow_triggers read_ai_flow_triggers],
        group_saml_enabled: %i[admin_saml_group_links read_group_saml_identity read_group_scim_identity],
        group_model_selection_enabled: %i[admin_group_model_selection read_model_selection_allowlist
          update_model_selection_allowlist],
        policy_store_experiment_active: %i[create_govern_policy read_govern_policy update_govern_policy
          delete_govern_policy],
        can_commit_to_security_policy_project: [:modify_security_policy],
        ldap_synced: [:override_group_member]
      }
    }
  end

  # Like withheld_permissions, for a single role and context key.
  let(:withheld_role_permissions) do
    {
      # can_create_fork_in_namespace: a direct project owner can't create projects in the parent group.
      owner: { project: [:link_forked_project] },
      # The policy enables this role's direct_permissions, which leaves out these
      # conditionally_enables expansions.
      security_policy_bot: { project: %i[_read_external_build _read_public_build] }
    }
  end

  # Required permissions mapped to the permissions a policy rule derives from them, e.g.
  # `rule { can?(:read_issue) }.enable :read_design`. Unlike granted_by_policy_rules these are only
  # allowed, never required. `[]` lists rules gated only by a condition, so any role may hold them.
  let(:derived_permissions) do
    {
      project: {
        [] => %i[build_service_proxy_enabled read_cross_project read_issue_analytics
          read_project_level_analytics_dashboard read_target_branch_rule set_pipeline_variables],
        [:read_project] => %i[access_duo_features read_attestation read_iteration read_package read_pages_content
          read_project_metadata read_requirement read_timeline_event_tag],
        [:read_issue] => %i[read_design read_design_activity read_issue_iid read_issue_link],
        [:read_work_item] => %i[read_work_item_lifecycle read_work_item_status],
        [:read_code] => [:read_path_locks],
        [:download_code] => [:read_repository_graphs],
        [:push_code] => [:create_path_lock],
        [:create_issue] => %i[create_key_result create_objective],
        [:read_merge_request] => [:read_vulnerability_merge_request_link],
        %i[read_merge_request read_pipeline] => [:read_merge_train],
        %i[read_build read_pipeline] => [:read_build_report_results],
        [:_read_public_build] => [:read_build],
        [:_read_public_ci_cd_analytics] => [:read_ci_cd_analytics],
        [:_read_public_pipeline] => [:read_pipeline],
        [:_read_public_pipeline_schedule] => [:read_pipeline_schedule],
        [:create_pipeline_schedule] => [:read_ci_pipeline_schedules_plan_limit],
        [:read_cycle_analytics] => [:read_project_level_value_stream_dashboard_overview_counts],
        [:read_vulnerability] => %i[read_vulnerability_feedback read_vulnerability_representation_information
          read_vulnerability_scanner read_vulnerability_statistics],
        [:admin_vulnerability] => %i[create_security_project_tracked_ref create_vulnerability_feedback
          create_vulnerability_state_transition delete_security_project_tracked_ref destroy_vulnerability_feedback
          update_vulnerability_feedback update_vulnerability_flag],
        [:admin_project] => %i[admin_mirror admin_remote_mirror],
        [:admin_package] => [:view_package_registry_project_settings],
        [:admin_security_testing] => [:configure_security_scanner],
        [:admin_terraform_state] => %i[create_terraform_state_protection_rule delete_terraform_state
          delete_terraform_state_protection_rule restore_terraform_state],
        [:update_sec_ai_workflow_settings] => [:view_edit_page]
      },
      group: {
        [] => [:read_cross_project],
        [:read_group] => %i[access_duo_features read_achievement read_contribution_analytics read_counts
          read_custom_emoji read_custom_field read_dependency_proxy read_design_activity read_epic read_epic_board
          read_epic_board_list read_group_activity read_group_activity_analytics read_group_boards
          read_group_build_report_results read_group_contribution_analytics read_group_issues read_group_labels
          read_group_member read_group_merge_requests read_group_metadata read_group_milestones read_issue
          read_issue_board read_issue_board_list read_iteration read_iteration_cadence read_label read_milestone
          read_namespace read_package read_upload read_work_item read_work_item_type],
        [:read_work_item] => %i[read_work_item_lifecycle read_work_item_status],
        [:create_epic] => %i[create_issue create_work_item],
        [:create_work_item] => %i[create_key_result create_objective create_task],
        [:read_wiki] => [:download_wiki_code],
        [:read_cluster] => [:read_cluster_environments],
        [:read_resource_access_tokens] => %i[create_resource_access_tokens manage_resource_access_tokens],
        [:admin_runners] => [:admin_group_or_admin_runners],
        [:admin_namespace] => [:admin_namespace_cluster_agent_mapping],
        [:archive_group] => [:view_edit_page]
      },
      organization: {
        [] => [:read_cross_project]
      }
    }
  end

  # Permissions a policy rule grants to the role outside its YAML, by context key.
  let(:granted_by_policy_rules) do
    cd_permissions = %i[
      create_cd_application create_cd_application_flow_definition create_cd_application_link
      create_cd_artifact_source create_cd_environment create_cd_rollout create_cd_service create_cd_version_set
      delete_cd_application_link read_cd_application read_cd_application_flow_definition read_cd_application_link
      read_cd_artifact_source read_cd_environment read_cd_rollout read_cd_service read_cd_version_set
      resolve_cd_rollout_gate update_cd_application update_cd_application_link update_cd_environment update_cd_service
    ]
    organization_user = %i[
      read_custom_dashboard read_dependency read_licenses read_organization_analytics
      read_organization_cluster_agent_mapping read_system_dashboard
    ]
    organization_owner = organization_user + cd_permissions + %i[
      admin_organization_cluster_agent_mapping create_custom_dashboard create_work_item_type delete_custom_dashboard
      read_security_resource read_work_item_setting update_custom_dashboard update_work_item_setting
      update_work_item_type
    ]

    # BasePolicy grants these on every resource.
    admin_instance_wide = %i[admin_all_resources change_repository_storage read_all_resources]

    {
      admin: {
        project: admin_instance_wide + %i[admin_compliance_framework read_all_organization_resources],
        group: admin_instance_wide + %i[update_organization update_subscription_limit],
        organization: admin_instance_wide + organization_owner
      },
      auditor: { project: [:read_all_resources], group: [:read_all_resources], organization: [:read_all_resources] },
      organization_owner: {
        organization: organization_owner + %i[create_govern_policy read_govern_policy update_govern_policy
          delete_govern_policy]
      },
      organization_user: { organization: organization_user },
      # can_admin_compliance_framework_in_group: granted by the group role, not the project one.
      owner: { project_via_group: [:admin_compliance_framework] },
      public_anonymous: {
        project: [:read_work_item],
        group: %i[read_ai_catalog_flow read_ai_catalog_item_consumer read_ai_foundational_flow
          update_work_item_user_preference upload_file]
      },
      security_manager: { project_via_group: [:admin_compliance_framework] }
    }
  end

  # Roles an actor also holds through membership, e.g. the service account is added to its project as a guest.
  let(:roles_held_alongside) do
    {
      dependency_management_service_account: [:guest]
    }
  end

  before do
    open_policy_gates
  end

  membership_roles = Gitlab::Access.sym_options_with_owner.keys

  # Each scope a role's YAML declares or inherits. A declared scope with no permissions is still
  # tested, which proves the role is granted nothing there.
  role_scopes = Dir[Rails.root.join(described_class::BASE_PATH, '*.yml')].to_h do |path|
    role = File.basename(path, '.yml').to_sym
    declared = YAML.safe_load_file(path).keys.map(&:to_sym)
    scopes = described_class::RESOURCE_SCOPES.select do |scope|
      declared.include?(scope) || described_class.get(role).permissions(scope).any?
    end

    [role, scopes]
  end

  # Each role's test contexts as [key, scope, member_of, description]. The tables above use the key:
  # :project (a direct member, or any role not held through membership), :project_via_group, :group
  # or :organization.
  role_contexts = role_scopes.to_h do |role, scopes|
    contexts = (scopes - inapplicable_scopes.fetch(role, [])).flat_map do |scope|
      if membership_roles.exclude?(role)
        [[scope, scope, nil, "in #{scope}"]]
      elsif scope == :group
        [[:group, :group, :group, 'in group']]
      elsif scope == :project
        [
          [:project, :project, :project, 'in project as a direct member'],
          [:project_via_group, :project, :group, 'in project through group membership']
        ]
      else
        raise "Membership role #{role} has no test context for #{scope}. Add one to role_contexts in #{__FILE__}."
      end
    end

    [role, contexts]
  end

  role_contexts.each do |role, contexts|
    describe role.to_s, enable_admin_mode: role == :admin do
      contexts.each do |key, scope, member_of, description|
        context description do
          let_it_be(:actor) { create_actor(role, member_of) }

          let(:policy) { DeclarativePolicy.policy_for(actor, resource_for(role, scope)) }
          let(:role_permissions) { described_class.get(role).permissions(scope) }
          # Permissions expected to be withheld, mapped to the table entry that lists them.
          let(:withheld_sources) do
            by_gate = withheld_permissions.fetch(scope, {}).flat_map do |gate, permissions|
              permissions.map { |permission| [permission, "withheld_permissions[:#{scope}][:#{gate}]"] }
            end
            by_role = withheld_role_permissions.dig(role, key).to_a.map do |permission|
              [permission, "withheld_role_permissions[:#{role}][:#{key}]"]
            end

            (by_gate + by_role).to_h.slice(*role_permissions)
          end

          it 'enables every permission in its role definition', :aggregate_failures do
            missing = role_permissions.reject { |permission| policy.allowed?(permission) }
            unexplained = missing - withheld_sources.keys
            now_granted = withheld_sources.keys - missing

            expect(unexplained).to be_empty,
              "#{role} is not granted #{unexplained.sort} #{description}. Open the gate that withholds them " \
                "in open_policy_gates, or add them to withheld_permissions (every role) or " \
                "withheld_role_permissions (this role only)."
            expect(now_granted).to be_empty,
              "#{role} is now granted #{now_granted.sort} #{description}. Remove them from " \
                "#{withheld_sources.slice(*now_granted).values.uniq.join(', ')}."
          end

          it 'does not enable permissions outside its role definition', :aggregate_failures do
            granted_by_rules = granted_by_policy_rules.dig(role, key) || []
            held_alongside = roles_held_alongside.fetch(role, []).map do |name|
              described_class.get(name).permissions(scope)
            end
            expected = with_derived_permissions(held_alongside.reduce(role_permissions | granted_by_rules, :|), scope)
            all_policy_permissions = policy.class.ability_map.map.keys
            unexpected = (all_policy_permissions - expected.to_a).select { |permission| policy.allowed?(permission) }
            stale = granted_by_rules.reject { |permission| policy.allowed?(permission) }
            redundant = granted_by_rules & role_permissions.to_a

            expect(unexpected).to be_empty,
              "#{role} is granted #{unexpected.sort} #{description} outside its role definition. Add them to " \
                "config/authz/roles/#{role}.yml or restrict the policy rule that grants them. If the grant is " \
                "intended, add them to granted_by_policy_rules, or to derived_permissions when a rule derives " \
                "them from other permissions."
            expect(stale).to be_empty,
              "#{role} is no longer granted #{stale.sort} #{description}. Remove them from granted_by_policy_rules."
            expect(redundant).to be_empty,
              "#{redundant.sort} are already in config/authz/roles/#{role}.yml. Remove them from " \
                "granted_by_policy_rules for #{role} #{description}."
          end
        end
      end
    end
  end

  it 'only lists roles, contexts, scopes and permissions that exist in its exception tables', :aggregate_failures do
    role_tables = { inapplicable_scopes:, withheld_role_permissions:, granted_by_policy_rules:, roles_held_alongside: }
    unknown_roles = role_tables.transform_values { |table| table.keys - role_contexts.keys }.reject { |_, v| v.empty? }
    unknown_held_roles = roles_held_alongside.values.flatten - role_contexts.keys
    unknown_contexts = { withheld_role_permissions:, granted_by_policy_rules: }.flat_map do |name, table|
      table.flat_map do |role, by_key|
        (by_key.keys - role_contexts.fetch(role, []).map(&:first)).map { |key| "#{name}[#{role}][#{key}]" }
      end
    end
    unused_inapplicable_scopes = inapplicable_scopes
      .to_h { |role, scopes| [role, scopes - role_scopes.fetch(role, [])] }
      .reject { |_, scopes| scopes.empty? }
    unheld = withheld_permissions.flat_map do |scope, by_gate|
      held = role_contexts.keys.map { |role| described_class.get(role).permissions(scope) }.reduce(:|)
      by_gate.flat_map { |gate, permissions| (permissions - held.to_a).map { |permission| "#{gate}: #{permission}" } }
    end
    unheld_by_role = withheld_role_permissions.flat_map do |role, by_key|
      by_key.flat_map do |key, permissions|
        _, scope = role_contexts.fetch(role, []).find { |context_key, _| context_key == key }
        next [] unless scope

        unheld_permissions = permissions - described_class.get(role).permissions(scope).to_a
        unheld_permissions.map { |permission| "#{role} #{key}: #{permission}" }
      end
    end
    policies = { project: ProjectPolicy, group: GroupPolicy, organization: Organizations::OrganizationPolicy }
    undefined_derived = derived_permissions.flat_map do |scope, table|
      (table.flatten.flatten.uniq - policies[scope].ability_map.map.keys).map { |permission| "#{scope}: #{permission}" }
    end

    expect(unknown_roles).to be_empty, "Exception tables refer to roles with no YAML: #{unknown_roles}"
    expect(unknown_held_roles).to be_empty, "roles_held_alongside refers to roles with no YAML: #{unknown_held_roles}"
    expect(unknown_contexts).to be_empty, "Exception tables refer to contexts that aren't tested: #{unknown_contexts}"
    expect(unused_inapplicable_scopes).to be_empty,
      "inapplicable_scopes lists scopes the role doesn't declare or inherit: #{unused_inapplicable_scopes}"
    expect(unheld).to be_empty, "withheld_permissions lists permissions no role's YAML holds: #{unheld}"
    expect(unheld_by_role).to be_empty,
      "withheld_role_permissions lists permissions the role's YAML doesn't hold: #{unheld_by_role}"
    expect(undefined_derived).to be_empty,
      "derived_permissions lists permissions the policy doesn't define: #{undefined_derived}"
  end

  # Ci::JobAbilities lists the job update abilities in code, so a new one must also be added to developer.yml.
  it 'grants developers every job update ability' do
    missing = ProjectPolicy.all_job_update_abilities - described_class.get(:developer).permissions(:project).to_a

    expect(missing).to be_empty,
      "config/authz/roles/developer.yml is missing job update abilities: #{missing.sort}. Add them to the YAML."
  end

  def open_policy_gates
    # Design management (read_design) needs LFS on the instance as well as the project.
    stub_lfs_setting(enabled: true)
    stub_licensed_features(GitlabSubscriptions::Features::ALL_FEATURES.index_with(true))
    # GitLab.com-only features, e.g. Google Cloud runners, credentials inventory and the security scans API.
    stub_saas_features(Gitlab::Saas::FEATURES.index_with(true))
    # Group service account management.
    stub_application_setting(allow_top_level_group_owners_to_create_service_accounts: true)
    # read_runner_usage
    allow(Gitlab::ClickHouse).to receive(:configured?).and_return(true)
    # create_ticket
    allow(ServiceDesk).to receive(:enabled?).and_return(true)
    # Secrets manager permissions.
    allow(SecretsManagement::Availability).to receive_messages(for_project?: true, for_group?: true)
    allow(SecretsManagement::Entitlement).to receive(:for).and_return(SecretsManagement::Entitlement.new(state: :paid))
    allow(SecretsManagement::NamespaceEnrollment).to receive(:enrollment_allowed?).and_return(true)
    # read_advanced_dependency_management
    allow(Search::Elastic::SbomOccurrenceRefIndexHelper).to receive(:advanced_dependency_management_allowed?)
      .and_return(true)
    # External agent session permissions, which need AI Governance turned on.
    private_project.project_setting.update!(ai_governance_enabled: true)
    # read_subscription_usage on an organization billed through a nominated group.
    allow(organization).to receive(:billing_namespace).and_return(build_stubbed(:group))
  end

  def with_derived_permissions(permissions, scope)
    allowed = permissions.dup

    # Repeats so chains resolve, e.g. _read_public_pipeline -> read_pipeline -> read_merge_train.
    loop do
      size = allowed.size
      derived_permissions[scope].each do |requirements, derived|
        allowed.merge(derived) if requirements.all? { |requirement| allowed.include?(requirement) }
      end
      break if allowed.size == size
    end

    allowed
  end

  def create_actor(role, member_of)
    case role
    when *Gitlab::Access.sym_options_with_owner.keys
      source = member_of == :project ? private_project : private_group
      create(:user).tap { |user| source.add_member(user, role) }
    when :minimal_access
      # The trait skips validation, which would reject the member before the license is stubbed.
      create(:group_member, :minimal_access, source: private_group).user
    when :public_anonymous then nil
    when :public_authenticated then create(:user)
    when :admin then create(:admin)
    when :auditor then create(:user, :auditor)
    when :descendant_project_member
      create(:user).tap { |user| private_project.add_guest(user) }
    when :security_policy_bot
      create(:user, user_type: :security_policy_bot).tap { |user| private_project.add_guest(user) }
    when :dependency_management_service_account
      create(:service_account, provisioned_by_project: private_project,
        name: DependencyManagement::ProvisionServiceAccountService::SERVICE_ACCOUNT_NAME)
        .tap { |user| private_project.add_guest(user) }
    when :organization_user
      create(:user).tap { |user| create(:organization_user, organization: organization, user: user) }
    when :organization_owner
      create(:user).tap { |user| create(:organization_owner, organization: organization, user: user) }
    else
      raise "No actor is defined for the #{role} role. Add one to create_actor in #{__FILE__}."
    end
  end

  def resource_for(role, scope)
    public_role = %i[public_anonymous public_authenticated].include?(role)

    case scope
    when :project then public_role ? public_project : private_project
    when :group then public_role ? public_group : private_group
    when :organization then organization
    end
  end
end
