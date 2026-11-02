# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProjectPolicy, feature_category: :system_access do
  include ExternalAuthorizationServiceHelpers
  include AdminModeHelper
  include LoginHelpers
  include_context 'ProjectPolicy context'

  using RSpec::Parameterized::TableSyntax

  let(:project) { public_project }

  let_it_be(:auditor) { create(:user, :auditor) }

  subject { described_class.new(current_user, project) }

  # The license prevent rules are role-independent, so a few roles that hold the permissions are enough.
  # The role definitions spec covers which roles hold them when the license is on.
  shared_examples 'prevents permissions when the licensed feature is disabled' do |licensed_feature:, permissions:,
    roles: %w[owner]|
    roles.each do |role|
      context "with #{role} when #{licensed_feature} is disabled" do
        let(:current_user) { public_send(role) }

        before do
          stub_licensed_features(licensed_feature => false)
        end

        it { expect_disallowed(*permissions) }
      end
    end
  end

  before do
    stub_licensed_features(
      license_scanning: true,
      quality_management: true,
      cycle_analytics_for_projects: true
    )
  end

  context 'basic permissions' do
    let(:additional_guest_permissions) { %i[read_limit_alert] }
    let(:additional_maintainer_permissions) do
      %i[push_code_to_protected_branches]
    end

    let(:auditor_permissions) do
      %i[
        access_security_and_compliance
        award_emoji
        download_code
        download_wiki_code
        export_work_items
        read_ai_tool_rule
        read_alert_management_alert
        read_build
        read_cluster
        read_code_review_analytics
        read_commit_status
        read_compliance_framework
        read_confidential_issues
        read_container_image
        read_cycle_analytics
        read_deployment
        read_environment
        read_feature_flag
        read_issue
        read_issue_board
        read_issue_board_list
        read_issue_iid
        read_issue_link
        read_label
        read_merge_request
        read_merge_request_iid
        read_merge_train
        read_milestone
        read_note
        read_on_demand_dast_scan
        read_pages
        read_pipeline
        read_project
        read_audit_event
        read_project_for_iids
        read_project_member
        read_project_merge_request_analytics
        read_project_metadata
        read_project_security_dashboard
        read_release
        read_resource_access_tokens
        read_runners
        read_security_resource
        read_snippet
        read_software_license_policy
        read_terraform_state
        read_vulnerability
        read_vulnerability_scanner
        read_wiki
      ]
    end

    it_behaves_like 'project policies as admin without admin mode'

    context 'auditor' do
      let(:current_user) { auditor }
      let(:auditor_as_guest_exclusions) do
        %i[
          admin_issue_link
          create_issue
          create_note
          create_project
          upload_file
        ]
      end

      before do
        stub_licensed_features(
          security_dashboard: true,
          license_scanning: true,
          security_on_demand_scans: true
        )
      end

      context 'for read_* permissions' do
        let(:excluded_permissions) do
          %i[
            read_advanced_dependency_management
            read_agent_artifacts
            read_ai_agent_session
            read_ai_catalog_mcp_server
            read_ai_catalog_flow
            read_ai_catalog_item_consumer
            read_ai_catalog_third_party_flow
            read_ai_flow_triggers
            read_all_organization_resources
            read_branch_rule
            read_ci_pipeline_schedules_plan_limit
            read_cluster_agent
            read_code_navigation
            read_commit_committer_check
            read_commit_committer_name_check
            read_compliance_adherence_report
            read_compliance_dashboard
            read_compliance_violations_report
            read_coverage_fuzzing
            read_custom_attribute
            read_customizable_dashboards
            read_deploy_board
            read_deploy_token
            read_design_activity
            read_design
            read_dora4_analytics
            read_enterprise_ai_analytics
            read_error_tracking_client_key
            read_error_tracking_setting
            read_external_emails
            read_external_status_check
            read_ai_catalog_item
            read_ai_foundational_flow
            read_freeze_period
            read_google_cloud_artifact_registry
            read_govern_policy
            read_harbor_registry
            read_http_integration
            read_import_error
            read_internal_note
            read_iteration
            read_job_inputs
            read_limit_alert
            read_manual_variables
            read_member_access_request
            read_member_role
            read_namespace_via_membership
            read_observability
            read_observability_portal
            read_pod_logs
            read_pro_ai_analytics
            read_product_analytics_settings
            read_project_secrets_manager_status
            read_project_secrets_manager
            read_project_secrets
            read_secrets_manager
            read_prometheus
            read_protectable_branch
            read_protected_branch
            read_protected_tag
            read_protected_tags
            read_reject_non_dco_commits
            read_reject_unsigned_commits
            read_resource_group
            read_runner_cloud_provisioning_info
            read_runner_gke_provisioning_info
            read_runner_usage
            read_runners_registration_token
            read_saved_replies
            read_secret_push_protection_info
            read_secure_files
            read_security_configuration
            read_security_orchestration_policy_project
            read_sentry_issue
            read_service_account
            read_squash_option
            read_statistics
            read_storage_disk_path
            read_usage_quotas
            read_work_item_lifecycle
            read_work_item_setting
            read_work_item_status
          ]
        end

        # Excluded but still allowed for auditors. See https://gitlab.com/gitlab-org/gitlab/-/work_items/631877
        let(:excluded_but_allowed_permissions) do
          %i[
            read_design
            read_design_activity
            read_observability
            read_saved_replies
          ]
        end

        let(:read_permissions) { described_class.ability_map.map.keys.select { |key| key.to_s.start_with?('read_') } }
        let(:expected_permissions) { read_permissions - excluded_permissions }

        before do
          create_current_license_without_expiration(plan: License::ULTIMATE_PLAN)
        end

        it 'allows the read permissions except the excluded ones', :aggregate_failures do
          expect_allowed(*expected_permissions)
          expect_disallowed(*(excluded_permissions - excluded_but_allowed_permissions))
        end
      end

      context 'who is a team member' do
        before do
          project.add_guest(current_user)
        end

        it do
          expect_disallowed(*(developer_permissions - auditor_permissions))
          expect_disallowed(*(maintainer_permissions - auditor_permissions))
          expect_disallowed(*owner_permissions)
          expect_disallowed(*(planner_permissions - auditor_permissions - auditor_as_guest_exclusions))
          expect_allowed(*(guest_permissions - auditor_permissions))
          expect_allowed(*auditor_permissions)
        end
      end

      it_behaves_like 'project private features with read_all_resources ability' do
        let(:user) { current_user }
      end

      context 'with project feature related policies' do
        # Required parameters:
        # - project_feature: Hash defining project feature mapping abilities.
        shared_examples 'project feature visibility' do |project_features|
          # For each project feature, check that an auditor is always allowed read
          # permissions unless the feature is disabled.
          project_features.each do |feature, permissions|
            context "with project feature #{feature}" do
              where(:project_visibility, :access_level, :allowed) do
                :public   | ProjectFeature::ENABLED  | true
                :public   | ProjectFeature::PRIVATE  | true
                :public   | ProjectFeature::DISABLED | false
                :internal | ProjectFeature::ENABLED  | true
                :internal | ProjectFeature::PRIVATE  | true
                :internal | ProjectFeature::DISABLED | false
                :private  | ProjectFeature::ENABLED  | true
                :private  | ProjectFeature::PRIVATE  | true
                :private  | ProjectFeature::DISABLED | false
              end

              with_them do
                let(:project) { send(:"#{project_visibility}_project") }

                it 'always allows permissions except when feature disabled' do
                  project.project_feature.update!("#{feature}": access_level)

                  if allowed
                    expect_allowed(*permissions)
                  else
                    expect_disallowed(*permissions)
                  end
                end
              end
            end
          end
        end

        include_examples 'project feature visibility', {
          container_registry_access_level: [:read_container_image],
          merge_requests_access_level: [:read_merge_request],
          monitor_access_level: [:read_alert_management_alert]
        }
      end
    end
  end

  context 'iterations' do
    context 'in a personal project' do
      let(:current_user) { owner }

      context 'when feature is disabled' do
        before do
          stub_licensed_features(iterations: false)
        end

        it { expect_disallowed(:read_iteration, :create_iteration, :admin_iteration) }
      end

      context 'when feature is enabled' do
        before do
          stub_licensed_features(iterations: true)
        end

        it { expect_disallowed(:read_iteration, :create_iteration, :admin_iteration) }
      end
    end

    context 'in a group project' do
      let(:project) { public_project_in_group }
      let(:current_user) { maintainer }

      context 'when feature is disabled' do
        before do
          stub_licensed_features(iterations: false)
        end

        it { expect_disallowed(:read_iteration, :create_iteration, :admin_iteration) }
      end

      context 'when feature is enabled' do
        before do
          stub_licensed_features(iterations: true)
        end

        context 'when issues are disabled but merge requests are enabled' do
          before do
            project.update!(issues_enabled: false)
          end

          it { expect_allowed(:read_iteration, :create_iteration, :admin_iteration) }
        end

        context 'when issues are enabled but merge requests are enabled' do
          before do
            project.update!(merge_requests_enabled: false)
          end

          it { expect_allowed(:read_iteration, :create_iteration, :admin_iteration) }
        end

        context 'when both issues and merge requests are disabled' do
          before do
            project.update!(issues_enabled: false, merge_requests_enabled: false)
          end

          it { expect_disallowed(:read_iteration, :create_iteration, :admin_iteration) }
        end

        context 'when the project is private' do
          let(:project) { private_project }

          context 'when user is not a member' do
            let(:current_user) { non_member }

            it { expect_disallowed(:read_iteration, :create_iteration, :admin_iteration) }
          end

          context 'when user is logged out' do
            let(:current_user) { anonymous }

            it { expect_disallowed(:read_iteration, :create_iteration, :admin_iteration) }
          end
        end
      end
    end
  end

  context 'issues feature' do
    let(:current_user) { owner }

    context 'when the feature is disabled' do
      before do
        project.update!(issues_enabled: false)
      end

      it 'disables boards permissions' do
        expect_disallowed :admin_issue_board, :create_test_case
      end

      it 'disables issues analytics' do
        expect_disallowed :read_issue_analytics
      end
    end
  end

  context 'merge requests feature' do
    let(:current_user) { owner }
    let_it_be(:group) { create(:group, :private) }
    let_it_be_with_reload(:project) { create(:project, group: group) }

    context 'when the feature is disabled' do
      before do
        project.update!(merge_requests_enabled: false)
      end

      it 'disables issues analytics' do
        expect_disallowed :read_project_merge_request_analytics
      end
    end
  end

  context 'admin_mirror' do
    context 'with admin when admin mode disabled' do
      let(:current_user) { admin }

      it { expect_disallowed(:admin_mirror) }
    end

    context 'with owner' do
      let(:current_user) { owner }

      it { expect_allowed(:admin_mirror) }
    end

    context 'with remote mirror setting disabled' do
      before do
        stub_application_setting(mirror_available: false)
      end

      context 'with admin' do
        let(:current_user) { admin }

        context 'when admin mode enabled', :enable_admin_mode do
          it { expect_allowed(:admin_mirror) }
        end

        context 'when admin mode disabled' do
          it { expect_disallowed(:admin_mirror) }
        end
      end

      context 'with owner' do
        let(:current_user) { owner }

        it { expect_disallowed(:admin_mirror) }
      end
    end

    context 'with remote mirrors feature disabled' do
      before do
        stub_licensed_features(repository_mirrors: false)
      end

      context 'with admin' do
        let(:current_user) { admin }

        it { expect_disallowed(:admin_mirror) }
      end

      context 'with owner' do
        let(:current_user) { owner }

        it { expect_disallowed(:admin_mirror) }
      end
    end
  end

  context 'when continuous GitHub sync is on' do
    import_sync_read_only_permissions = %i[
      admin_issue admin_issue_link admin_label admin_merge_request admin_milestone
      admin_note admin_protected_branch admin_remote_mirror admin_tag
      admin_upload approve_merge_request create_branch_rule create_incident create_issue create_issue_link
      create_label create_merge_request create_merge_request_from create_merge_request_in
      create_milestone create_note create_protected_branch create_release create_test_case
      delete_branch_rule delete_label delete_milestone delete_note destroy_issue destroy_issue_link
      destroy_merge_request destroy_protected_branch
      destroy_release destroy_upload promote_milestone push_code push_code_to_protected_branches
      push_to_delete_protected_branch
      reopen_issue reopen_merge_request resolve_note rewrite_repository_history
      update_branch_rule update_issue update_issue_link update_label update_merge_request
      update_milestone update_note update_protected_branch update_release upload_file
    ].freeze

    let_it_be_with_reload(:connected_project) do
      create(:project, :repository, :public, organization: organization, maintainers: maintainer, owners: owner)
    end

    let_it_be(:import_sync_repository) do
      connected_project.update!(import_type: 'github')

      create(:import_sync_repository, project: connected_project,
        authority_state: :provider_canonical)
    end

    let(:project) { connected_project }
    let(:current_user) { owner }

    before do
      connected_project.association(:import_sync_repository).reset
    end

    it 'keeps project content readable and project administration available' do
      expect_allowed(:read_project, :read_code, :read_issue, :read_merge_request, :admin_project)
    end

    it 'blocks provider-derived content mutations using the established read-only permission set' do
      expect_disallowed(*import_sync_read_only_permissions)
    end

    context 'when continuous GitHub sync is off' do
      let(:project) do
        create(:project, :repository, :public, organization: organization, maintainers: maintainer, owners: owner)
      end

      before do
        project.update!(import_type: 'github')
        create(:import_sync_repository, project: project,
          authority_state: :gitlab_canonical)
        project.association(:import_sync_repository).reset
      end

      it 'restores ordinary write permissions' do
        never_enabled_anywhere = %i[
          create_issue_link create_merge_request
          destroy_issue_link update_issue_link
        ]
        restorable_permissions = import_sync_read_only_permissions - never_enabled_anywhere

        expect_allowed(*restorable_permissions)
      end
    end
  end

  context 'reading a project' do
    context 'with an external authorization service' do
      before do
        enable_external_authorization_service_check
      end

      it 'allows auditors' do
        stub_licensed_features(auditor_user: true)

        expect(described_class.new(auditor, project)).to be_allowed(:read_project)
      end
    end

    context 'when SAML SSO is enabled for resource' do
      let_it_be_with_reload(:saml_provider) { create(:saml_provider, group: group, enabled: true, enforced_sso: false) }
      let(:project) { public_project_in_group }
      let(:member_with_identity) { inherited_reporter }
      let(:member_without_identity) { inherited_developer }
      # A direct member of the project only, not of its group.
      let(:project_member_without_identity) { developer }
      let(:not_signed_in_user) { nil }

      before_all do
        create(:group_saml_identity, saml_provider: saml_provider, user: inherited_reporter)
      end

      before do
        stub_licensed_features(group_saml: true)
      end

      subject { described_class.new(current_user, resource) }

      shared_examples 'does not allow read project' do
        it 'does not allow read project' do
          expect_disallowed(:read_project)
        end
      end

      shared_examples 'allows to read project' do
        it 'allows read project' do
          expect_allowed(:read_project)
        end
      end

      shared_examples 'does not allow to read project due to its visibility level' do
        it 'does not allow to read project due to its visibility level', :aggregate_failures do
          expect(resource.root_ancestor.saml_provider.enforced_sso?).to be(false)

          expect_disallowed(:read_project)
        end
      end

      # See https://docs.gitlab.com/ee/user/group/saml_sso/#sso-enforcement
      where(:resource, :resource_visibility_level, :enforced_sso?, :user, :user_is_resource_owner?,
        :user_with_saml_session?, :user_is_admin?, :enable_admin_mode?, :user_is_auditor?, :shared_examples) do
        # Project/Group visibility: Private; Enforce SSO setting: Off

        ref(:project)    | 'private' | false | ref(:member_with_identity)    | false | false | nil  | nil   | nil  | 'does not allow read project'
        ref(:project)    | 'private' | false | ref(:member_with_identity)    | true  | false | nil  | nil   | nil  | 'does not allow read project'
        ref(:project)    | 'private' | false | ref(:member_with_identity)    | false | true  | nil  | nil   | nil  | 'allows to read project'
        ref(:project)    | 'private' | false | ref(:member_with_identity)    | false | false | true | false | nil  | 'does not allow read project'
        ref(:project)    | 'private' | false | ref(:member_with_identity)    | false | false | true | true  | nil  | 'allows to read project'
        ref(:project)    | 'private' | false | ref(:member_with_identity)    | false | false | nil  | nil   | true | 'allows to read project'

        ref(:project)    | 'private' | false | ref(:member_without_identity) | false | nil   | nil  | nil   | nil  | 'allows to read project'

        ref(:project)    | 'private' | false | ref(:non_member)              | nil   | nil   | nil  | nil   | nil  | 'does not allow to read project due to its visibility level'
        ref(:project)    | 'private' | false | ref(:non_member)              | nil   | nil   | true | false | nil  | 'does not allow to read project due to its visibility level'
        ref(:project)    | 'private' | false | ref(:non_member)              | nil   | nil   | true | true  | nil  | 'allows to read project'
        ref(:project)    | 'private' | false | ref(:non_member)              | nil   | nil   | nil  | nil   | true | 'allows to read project'
        ref(:project)    | 'private' | false | ref(:not_signed_in_user)      | nil   | nil   | nil  | nil   | nil  | 'does not allow to read project due to its visibility level'

        # Project/Group visibility: Private; Enforce SSO setting: On

        ref(:project)    | 'private' | true  | ref(:member_with_identity)    | false | false | nil  | nil   | nil  | 'does not allow read project'
        ref(:project)    | 'private' | true  | ref(:member_with_identity)    | true  | false | nil  | nil   | nil  | 'does not allow read project'
        ref(:project)    | 'private' | true  | ref(:member_with_identity)    | false | true  | nil  | nil   | nil  | 'allows to read project'
        ref(:project)    | 'private' | true  | ref(:member_with_identity)    | false | false | true | false | nil  | 'does not allow read project'
        ref(:project)    | 'private' | true  | ref(:member_with_identity)    | false | false | true | true  | nil  | 'allows to read project'
        ref(:project)    | 'private' | true  | ref(:member_with_identity)    | false | false | nil  | nil   | true | 'allows to read project'

        ref(:project)    | 'private' | true  | ref(:member_without_identity) | false | nil   | nil  | nil   | nil  | 'does not allow read project'
        ref(:project)    | 'private' | true  | ref(:member_without_identity) | true  | nil   | nil  | nil   | nil  | 'does not allow read project'
        ref(:project)    | 'private' | true  | ref(:member_without_identity) | false | nil   | true | false | nil  | 'does not allow read project'
        ref(:project)    | 'private' | true  | ref(:member_without_identity) | false | nil   | true | true  | nil  | 'allows to read project'
        ref(:project)    | 'private' | true  | ref(:member_without_identity) | false | nil   | nil  | nil   | true | 'allows to read project'

        ref(:project)    | 'private' | true  | ref(:project_member_without_identity) | false | nil   | nil  | nil   | nil  | 'does not allow read project'
        ref(:project)    | 'private' | true  | ref(:project_member_without_identity) | false | nil   | true | false | nil  | 'does not allow read project'
        ref(:project)    | 'private' | true  | ref(:project_member_without_identity) | false | nil   | true | true  | nil  | 'allows to read project'
        ref(:project)    | 'private' | true  | ref(:project_member_without_identity) | false | nil   | nil  | nil   | true | 'allows to read project'

        ref(:project)    | 'private' | true  | ref(:non_member)              | nil   | nil   | nil  | nil   | nil  | 'does not allow read project'
        ref(:project)    | 'private' | true  | ref(:non_member)              | nil   | nil   | true | false | nil  | 'does not allow read project'
        ref(:project)    | 'private' | true  | ref(:non_member)              | nil   | nil   | true | true  | nil  | 'allows to read project'
        ref(:project)    | 'private' | true  | ref(:non_member)              | nil   | nil   | nil  | nil   | true | 'allows to read project'
        ref(:project)    | 'private' | true  | ref(:not_signed_in_user)      | nil   | nil   | nil  | nil   | nil  | 'does not allow read project'

        # Project/Group visibility: Public; Enforce SSO setting: Off

        ref(:project)    | 'public'  | false | ref(:member_with_identity)    | false | false | nil  | nil   | nil  | 'does not allow read project'
        ref(:project)    | 'public'  | false | ref(:member_with_identity)    | true  | false | nil  | nil   | nil  | 'does not allow read project'
        ref(:project)    | 'public'  | false | ref(:member_with_identity)    | false | true  | nil  | nil   | nil  | 'allows to read project'
        ref(:project)    | 'public'  | false | ref(:member_with_identity)    | false | false | true | false | nil  | 'does not allow read project'
        ref(:project)    | 'public'  | false | ref(:member_with_identity)    | false | false | true | true  | nil  | 'allows to read project'
        ref(:project)    | 'public'  | false | ref(:member_with_identity)    | false | false | nil  | nil   | true | 'allows to read project'

        ref(:project)    | 'public'  | false | ref(:member_without_identity) | false | nil   | nil  | nil   | nil  | 'allows to read project'

        ref(:project)    | 'public'  | false | ref(:non_member)              | nil   | nil   | nil  | nil   | nil  | 'allows to read project'
        ref(:project)    | 'public'  | false | ref(:not_signed_in_user)      | nil   | nil   | nil  | nil   | nil  | 'allows to read project'

        # Project/Group visibility: Public; Enforce SSO setting: On

        ref(:project)    | 'public'  | true  | ref(:member_with_identity)    | false | false | nil  | nil   | nil  | 'does not allow read project'
        ref(:project)    | 'public'  | true  | ref(:member_with_identity)    | true  | false | nil  | nil   | nil  | 'does not allow read project'
        ref(:project)    | 'public'  | true  | ref(:member_with_identity)    | false | true  | nil  | nil   | nil  | 'allows to read project'
        ref(:project)    | 'public'  | true  | ref(:member_with_identity)    | false | false | true | false | nil  | 'does not allow read project'
        ref(:project)    | 'public'  | true  | ref(:member_with_identity)    | false | false | true | true  | nil  | 'allows to read project'
        ref(:project)    | 'public'  | true  | ref(:member_with_identity)    | false | false | nil  | nil   | true | 'allows to read project'

        ref(:project)    | 'public'  | true  | ref(:member_without_identity) | false | nil   | nil  | nil   | nil  | 'does not allow read project'
        ref(:project)    | 'public'  | true  | ref(:member_without_identity) | true  | nil   | nil  | nil   | nil  | 'does not allow read project'
        ref(:project)    | 'public'  | true  | ref(:member_without_identity) | false | nil   | true | false | nil  | 'does not allow read project'
        ref(:project)    | 'public'  | true  | ref(:member_without_identity) | false | nil   | true | true  | nil  | 'allows to read project'
        ref(:project)    | 'public'  | true  | ref(:member_without_identity) | false | nil   | nil  | nil   | true | 'allows to read project'

        ref(:project)    | 'public' | true  | ref(:project_member_without_identity) | false | nil   | nil  | nil   | nil  | 'does not allow read project'
        ref(:project)    | 'public' | true  | ref(:project_member_without_identity) | false | nil   | true | false | nil  | 'does not allow read project'
        ref(:project)    | 'public' | true  | ref(:project_member_without_identity) | false | nil   | true | true  | nil  | 'allows to read project'
        ref(:project)    | 'public' | true  | ref(:project_member_without_identity) | false | nil   | nil  | nil   | true | 'allows to read project'

        ref(:project)    | 'public'  | true  | ref(:non_member)              | nil   | nil   | nil  | nil   | nil  | 'allows to read project'
        ref(:project)    | 'public'  | true  | ref(:not_signed_in_user)      | nil   | nil   | nil  | nil   | nil  | 'allows to read project'
      end

      with_them do
        context "when 'Enforce SSO-only authentication for web activity for this group' option is #{params[:enforced_sso?] ? 'enabled' : 'not enabled'}" do
          around do |example|
            session = {}

            session['warden.user.user.key'] = [[user.id], user.authenticatable_salt] if user.is_a?(User)

            Gitlab::Session.with_session(session) do
              example.run
            end
          end

          before do
            saml_provider.update!(enforced_sso: enforced_sso?)
          end

          context "when resource is #{params[:resource_visibility_level]}" do
            before do
              resource.update!(visibility_level: Gitlab::VisibilityLevel.string_options[resource_visibility_level])
            end

            context 'for user', enable_admin_mode: params[:enable_admin_mode?] do
              before do
                if user_is_resource_owner?
                  resource.root_ancestor.member(user).update_column(:access_level, Gitlab::Access::OWNER)
                end

                Gitlab::Auth::GroupSaml::SsoEnforcer.new(saml_provider).update_session if user_with_saml_session?

                user.update!(admin: true) if user_is_admin?
                user.update!(auditor: true) if user_is_auditor?
              end

              let(:current_user) { user }

              include_examples params[:shared_examples]
            end
          end
        end
      end
    end

    context 'with ip restriction' do
      let(:current_user) { admin }
      let(:group) { create(:group, :public) }
      let(:project) { create(:project, group: group) }

      before do
        allow(Gitlab::IpAddressState).to receive(:current).and_return('192.168.0.2')
        stub_licensed_features(group_ip_restriction: true)
        group.add_maintainer(current_user)
      end

      context 'group without restriction' do
        it do
          expect_allowed(
            :admin_package,
            :create_package,
            :destroy_package,
            :read_container_image,
            :read_issue,
            :read_merge_request,
            :read_milestone,
            :read_package,
            :read_project
          )
        end
      end

      context 'group with restriction' do
        before do
          create(:ip_restriction, group: group, range: range)
        end

        context 'address is within the range' do
          let(:range) { '192.168.0.0/24' }

          it do
            expect_allowed(
              :admin_package,
              :create_container_image,
              :create_package,
              :destroy_package,
              :read_container_image,
              :read_issue,
              :read_merge_request,
              :read_milestone,
              :read_package,
              :read_project
            )
          end
        end

        context 'address is outside the range' do
          let(:range) { '10.0.0.0/8' }

          it do
            expect_disallowed(
              :admin_package,
              :create_container_image,
              :create_package,
              :destroy_package,
              :read_container_image,
              :read_issue,
              :read_merge_request,
              :read_milestone,
              :read_package,
              :read_project
            )
          end

          context 'with admin enabled', :enable_admin_mode do
            it do
              expect_allowed(
                :admin_package,
                :create_container_image,
                :create_package,
                :destroy_package,
                :read_container_image,
                :read_issue,
                :read_merge_request,
                :read_milestone,
                :read_package,
                :read_project
              )
            end
          end

          context 'with admin disabled' do
            it do
              expect_disallowed(
                :admin_package,
                :create_container_image,
                :create_package,
                :destroy_package,
                :read_container_image,
                :read_issue,
                :read_merge_request,
                :read_milestone,
                :read_package,
                :read_project
              )
            end
          end

          context 'with auditor' do
            let(:current_user) { auditor }

            it do
              expect_allowed(
                :admin_package,
                :create_container_image,
                :create_package,
                :destroy_package,
                :read_container_image,
                :read_issue,
                :read_merge_request,
                :read_milestone,
                :read_package,
                :read_project
              )
            end
          end
        end
      end

      context 'without group' do
        let(:project) { create(:project, :small_repo, namespace: current_user.namespace) }

        it { expect_allowed(:read_project) }
      end
    end
  end

  describe 'access_security_and_compliance' do
    shared_examples 'correct access to security and compliance' do
      before do
        project.project_feature.update!(security_and_compliance_access_level: access_level)
      end

      context 'when "Security and compliance" is disabled' do
        let(:access_level) { Featurable::DISABLED }

        it do
          expect_disallowed(
            :access_security_and_compliance,
            :admin_security_attributes,
            :admin_vulnerability,
            :admin_vulnerability_external_issue_link,
            :admin_vulnerability_issue_link,
            :apply_security_scan_profiles,
            :confirm_vulnerability,
            :create_on_demand_dast_scan,
            :create_security_scan_profiles,
            :create_vulnerability_archive_export,
            :create_vulnerability_export,
            :delete_security_scan_profiles,
            :dismiss_vulnerability,
            :edit_on_demand_dast_scan,
            :enable_container_scanning_for_registry,
            :enable_secret_push_protection,
            :manage_project_security_exclusions,
            :modify_security_policy,
            :read_any_audit_event,
            :read_audit_event,
            :read_compliance_adherence_report,
            :read_compliance_dashboard,
            :read_compliance_violations_report,
            :read_on_demand_dast_scan,
            :read_project_security_dashboard,
            :read_project_security_exclusions,
            :read_secret_push_protection_info,
            :read_security_attribute,
            :read_security_configuration,
            :read_security_inventory,
            :read_security_orchestration_policies,
            :read_security_project_tracked_ref,
            :read_security_resource,
            :read_security_scan_profiles,
            :read_security_settings,
            :read_vulnerability,
            :resolve_vulnerability,
            :revert_vulnerability,
            :update_cvs_for_container_scanning,
            :update_cvs_for_dependency_scanning,
            :update_on_demand_dast_scan,
            :update_sec_ai_workflow_settings,
            :update_security_scan_profiles,
            :update_security_setting,
            :update_vulnerability_flag,
            :update_vulnerability_severity
          )
        end
      end

      context 'when "Security and compliance" is enabled' do
        let(:access_level) { Featurable::PRIVATE }

        it { expect_allowed(:access_security_and_compliance) }
      end
    end

    context 'when the user is developer' do
      let(:current_user) { developer }

      it_behaves_like 'correct access to security and compliance'
    end

    context 'when the user has a custom role that enables read_vulnerability' do
      let(:current_user) { guest }
      let_it_be_with_refind(:project) { create(:project, :in_group) }

      before do
        stub_licensed_features(custom_roles: true)
        project_member = create(:project_member, :guest, user: current_user, source: project)
        create(:member_role, :guest, read_vulnerability: true, members: [project_member], namespace: project.group)
      end

      it_behaves_like 'correct access to security and compliance'
    end

    context 'when the user is auditor' do
      let(:current_user) { auditor }

      it_behaves_like 'correct access to security and compliance'
    end

    context 'when the user is a security_manager (inherited from group)' do
      let(:current_user) { inherited_security_manager }
      let(:project) { public_project_in_group }

      before do
        stub_licensed_features(custom_roles: true)
      end

      it_behaves_like 'correct access to security and compliance'
    end

    describe 'read_compliance_framework' do
      before do
        project.project_feature.update!(security_and_compliance_access_level: access_level)
      end

      context 'when "Security and compliance" is disabled' do
        let(:access_level) { Featurable::DISABLED }

        context 'when the user is a reporter' do
          let(:current_user) { reporter }

          it { expect_allowed(:read_compliance_framework) }
        end

        context 'when the user is auditor' do
          let(:current_user) { auditor }

          it { expect_allowed(:read_compliance_framework) }
        end

        context 'when the user is a developer' do
          let(:current_user) { developer }

          it { expect_allowed(:read_compliance_framework) }
        end
      end
    end

    describe 'vulnerability feedback permissions' do
      before do
        stub_licensed_features(security_dashboard: true)
      end

      context 'with developer' do
        let(:current_user) { developer }

        it 'can read feedback but not change it' do
          expect_allowed(:read_vulnerability_feedback, :read_vulnerability_representation_information)
          expect_disallowed(
            :create_vulnerability_feedback,
            :destroy_vulnerability_feedback,
            :update_vulnerability_feedback
          )
        end
      end

      context 'with maintainer' do
        let(:current_user) { maintainer }

        it do
          expect_allowed(
            :create_vulnerability_feedback,
            :create_vulnerability_state_transition,
            :destroy_vulnerability_feedback,
            :update_vulnerability_feedback
          )
        end
      end

      context 'with admin when admin mode disabled' do
        let(:current_user) { admin }

        it do
          expect_disallowed(
            :create_vulnerability_feedback,
            :destroy_vulnerability_feedback,
            :read_vulnerability_feedback,
            :update_vulnerability_feedback
          )
        end
      end
    end

    describe 'read_security_inventory' do
      it_behaves_like 'enables permissions for the correct roles',
        licensed_feature: :security_inventory,
        permissions: [:read_security_inventory],
        allowed: %w[owner maintainer security_manager developer auditor],
        disallowed: %w[guest reporter]
    end

    describe 'security dashboard permissions' do
      it_behaves_like 'prevents permissions when the licensed feature is disabled',
        licensed_feature: :security_dashboard,
        permissions: %i[
          read_project_security_dashboard
          read_security_resource
          admin_security_testing
          admin_vulnerability_merge_request_link
          admin_vulnerability
          confirm_vulnerability
          dismiss_vulnerability
          resolve_vulnerability
          revert_vulnerability
          update_vulnerability_severity
          read_vulnerability
          create_vulnerability_export
          create_vulnerability_archive_export
          read_security_project_tracked_ref
          admin_vulnerability_issue_link
          admin_vulnerability_external_issue_link
          execute_vulnerability_duo_workflow
        ],
        roles: %w[developer owner auditor]
    end

    describe 'permissions for security bot' do
      let_it_be(:current_user) { create(:user, :security_bot) }

      let(:project) { private_project }

      let(:permissions) do
        %i[
          push_code
          create_merge_request_from
          create_merge_request_in
          create_vulnerability_feedback
          read_project
          admin_merge_request
        ]
      end

      context 'when project does not have a security_setting' do
        before do
          project.security_setting.delete
          project.reload
        end

        it { expect_allowed(*permissions) }

        context 'with user other than security bot' do
          let_it_be(:current_user) { create(:user) }

          it { expect_disallowed(*permissions) }
        end
      end
    end

    describe 'permissions for dependency management service account' do
      let_it_be(:project) { create(:project, :private, :in_group) }
      let_it_be(:service_account) do
        create(:service_account,
          provisioned_by_project: project,
          name: DependencyManagement::ProvisionServiceAccountService::SERVICE_ACCOUNT_NAME
        )
      end

      let(:current_user) { service_account }

      let(:expected_permissions) do
        %i[
          create_pipeline
          push_code
          create_merge_request_from
          create_merge_request_in
          read_merge_request
          update_merge_request
          set_merge_request_metadata
          download_code
          build_download_code
        ]
      end

      context 'when the service account is a guest member of the project' do
        before_all do
          project.add_guest(service_account)
        end

        it { expect_allowed(*expected_permissions) }
      end

      context 'when the service account is not a member of the project' do
        it { expect_disallowed(*expected_permissions) }
      end

      context 'when a different service account is a guest member' do
        let_it_be(:other_service_account) do
          create(:service_account,
            provisioned_by_project: project,
            name: 'Some Other Bot'
          )
        end

        let(:current_user) { other_service_account }

        before_all do
          project.add_guest(other_service_account)
        end

        it 'does not grant surgical permissions to unrelated service accounts' do
          expect_disallowed(
            :build_download_code,
            :create_merge_request_from,
            :create_merge_request_in,
            :create_pipeline,
            :download_code,
            :push_code,
            :read_merge_request,
            :set_merge_request_metadata,
            :update_merge_request
          )
        end
      end

      context 'when the service account belongs to a different project' do
        let_it_be(:other_project) { create(:project, :in_group) }
        let_it_be(:other_dep_mgmt_account) do
          create(:service_account,
            provisioned_by_project: other_project,
            name: DependencyManagement::ProvisionServiceAccountService::SERVICE_ACCOUNT_NAME
          )
        end

        let(:current_user) { other_dep_mgmt_account }

        before_all do
          project.add_guest(other_dep_mgmt_account)
        end

        it 'does not grant surgical permissions to another project dependency management account' do
          expect_disallowed(
            :build_download_code,
            :create_merge_request_from,
            :create_merge_request_in,
            :create_pipeline,
            :download_code,
            :push_code,
            :read_merge_request,
            :update_merge_request
          )
        end
      end
    end

    describe 'security orchestration policies' do
      before do
        stub_licensed_features(security_orchestration_policies: true)
      end

      describe 'force_evaluate_merge_request_security_policy' do
        let(:current_user) { developer }

        it { expect_allowed(:force_evaluate_merge_request_security_policy) }

        context 'when security orchestration policies are not licensed' do
          before do
            stub_licensed_features(security_orchestration_policies: false)
          end

          it { expect_disallowed(:force_evaluate_merge_request_security_policy) }
        end
      end

      context 'with owner role' do
        where(role: %w[owner])

        with_them do
          let(:current_user) { public_send(role) }

          it 'disallows modifying since there is no policy project to push to' do
            expect_disallowed(:modify_security_policy)
          end

          context 'when security_orchestration_policy_configuration is present' do
            let_it_be(:security_policy_management_project) { create(:project) }

            before do
              create(:security_orchestration_policy_configuration, project: project,
                security_policy_management_project: security_policy_management_project)
            end

            it 'disallows creating since policy project already exists' do
              expect_disallowed(:create_security_policy)
            end

            it 'disallows modifying since user cannot push to the policy project' do
              expect_disallowed(:modify_security_policy)
            end
          end
        end
      end

      context 'with auditor role' do
        where(role: %w[auditor])

        before do
          project.project_feature.update!(security_orchestration_policies: feature_status)
        end

        context 'with policy feature disabled' do
          let(:feature_status) { ProjectFeature::DISABLED }

          with_them do
            let(:current_user) { public_send(role) }

            it do
              expect_disallowed(:read_security_orchestration_policies, :update_security_orchestration_policy_project)
            end
          end
        end
      end

      context 'when no security_orchestration_policy_configuration exists' do
        let(:current_user) { developer }

        it { expect_disallowed(:modify_security_policy, :create_policy_schedule_test_run) }
      end

      context 'when security_orchestration_policy_configuration is present' do
        let_it_be(:security_policy_management_project) { create(:project) }
        let(:current_user) { developer }

        before do
          create(:security_orchestration_policy_configuration, project: project,
            security_policy_management_project: security_policy_management_project)
        end

        context 'when current_user is guest of security_policy_management_project' do
          let(:project) { security_policy_management_project }

          before do
            security_policy_management_project.add_guest(developer)
          end

          it { expect_disallowed(:read_security_orchestration_policy_project, :modify_security_policy) }
        end

        context 'when current_user is reporter of security_policy_management_project' do
          let(:project) { security_policy_management_project }

          before do
            security_policy_management_project.add_reporter(developer)
          end

          specify :aggregate_failures do
            expect_allowed(:read_security_orchestration_policy_project)
            expect_disallowed(:modify_security_policy)
          end
        end

        context 'when current_user is developer of security_policy_management_project' do
          let(:project) { security_policy_management_project }

          before do
            security_policy_management_project.add_developer(developer)
          end

          it 'allows modifying existing policy project' do
            expect_allowed(:modify_security_policy)
          end

          it 'disallows creating since policy project already exists' do
            expect_disallowed(:create_security_policy)
          end
        end

        context 'when current_user is not member of security_policy_management_project' do
          let(:project) { security_policy_management_project }

          it { expect_disallowed(:read_security_orchestration_policy_project, :modify_security_policy) }
        end
      end

      context 'when security_orchestration_policy_configuration is inherited from group' do
        let_it_be(:group) { create(:group) }
        let_it_be(:project) { create(:project, group: group) }
        let_it_be(:security_policy_management_project) { create(:project) }
        let_it_be(:user) { create(:user) }
        let(:current_user) { user }

        before_all do
          create(:security_orchestration_policy_configuration, :namespace,
            namespace: group,
            security_policy_management_project: security_policy_management_project)
          project.add_developer(user)
        end

        context 'when user can push to inherited security_policy_management_project' do
          before_all do
            security_policy_management_project.add_developer(user)
          end

          specify :aggregate_failures do
            expect_disallowed(:modify_security_policy)
            expect_allowed(:create_policy_schedule_test_run)
          end
        end

        context 'when user cannot push to inherited security_policy_management_project' do
          it { expect_disallowed(:modify_security_policy, :create_policy_schedule_test_run) }
        end

        context 'when user is owner of the project' do
          before_all do
            project.add_owner(user)
          end

          it 'allows creating policies when no direct policy project exists' do
            expect_allowed(:create_security_policy)
          end

          it 'disallows modifying since there is no direct policy project to push to' do
            expect_disallowed(:modify_security_policy)
          end
        end

        context 'when user is maintainer of the project' do
          before_all do
            project.add_maintainer(user)
          end

          it { expect_disallowed(:create_security_policy, :modify_security_policy) }
        end
      end

      context 'when project has both direct and inherited policy configurations' do
        let_it_be(:group) { create(:group) }
        let_it_be(:project) { create(:project, group: group) }
        let_it_be(:group_policy_management_project) { create(:project) }
        let_it_be(:project_policy_management_project) { create(:project) }
        let_it_be(:user) { create(:user) }
        let(:current_user) { user }

        before_all do
          create(:security_orchestration_policy_configuration, :namespace,
            namespace: group,
            security_policy_management_project: group_policy_management_project)
          create(:security_orchestration_policy_configuration,
            project: project,
            security_policy_management_project: project_policy_management_project)
          project.add_developer(user)
        end

        context 'when user can push only to group policy management project' do
          before_all do
            group_policy_management_project.add_developer(user)
          end

          specify :aggregate_failures do
            expect_disallowed(:modify_security_policy)
            expect_allowed(:create_policy_schedule_test_run)
          end
        end

        context 'when user can push only to project policy management project' do
          before_all do
            project_policy_management_project.add_developer(user)
          end

          it { expect_allowed(:modify_security_policy, :create_policy_schedule_test_run) }
        end

        context 'when user cannot push to either policy management project' do
          it { expect_disallowed(:modify_security_policy, :create_policy_schedule_test_run) }
        end
      end
    end

    describe 'security orchestration policies with only the dependency firewall enforced' do
      let(:project) { public_project_in_group }

      before do
        stub_saas_features(dependency_firewall: true)
        stub_licensed_features(security_orchestration_policies: false, dependency_firewall: true)
        group.namespace_settings.update!(dependency_firewall_enabled: true)
      end

      context 'with owner role' do
        let(:current_user) { owner }

        it 'opens the policy management abilities without the security policies licence' do
          expect_allowed(
            :create_security_policy,
            :read_security_orchestration_policies,
            :update_security_orchestration_policy_project
          )
        end

        context 'when the dependency firewall setting is switched off' do
          before do
            group.namespace_settings.update!(dependency_firewall_enabled: false)
          end

          it 'keeps the gate closed' do
            expect_disallowed(
              :create_security_policy,
              :read_security_orchestration_policies,
              :update_security_orchestration_policy_project
            )
          end
        end
      end

      context 'when the project is a security policy management project' do
        before do
          create(:security_orchestration_policy_configuration, :namespace,
            namespace: group,
            security_policy_management_project: project)
        end

        context 'with security manager role' do
          let(:current_user) { security_manager }

          it 'grants write access to the policy project through _contribute_security_policy_project' do
            expect_allowed(
              :_contribute_security_policy_project,
              :create_merge_request_from,
              :create_merge_request_in,
              :push_code
            )
          end

          context 'when the dependency firewall setting is switched off' do
            before do
              group.namespace_settings.update!(dependency_firewall_enabled: false)
            end

            it 'withholds write access to the policy project' do
              expect_disallowed(:_contribute_security_policy_project, :push_code)
            end
          end
        end
      end
    end

    describe 'coverage_fuzzing' do
      context 'with admin when admin mode disabled' do
        let(:current_user) { admin }

        it { expect_disallowed(:read_coverage_fuzzing) }
      end

      it_behaves_like 'prevents permissions when the licensed feature is disabled',
        licensed_feature: :coverage_fuzzing,
        permissions: [:read_coverage_fuzzing],
        roles: %w[developer owner]
    end

    describe 'security attributes' do
      context 'when security attributes are not available' do
        before do
          stub_licensed_features(security_attributes: false)
        end

        context 'when user is maintainer' do
          let(:current_user) { maintainer }

          it { expect_disallowed(:admin_security_attributes) }
        end

        context 'when user is a security manager' do
          let(:current_user) { security_manager }

          it { expect_disallowed(:admin_security_attributes) }
        end
      end

      context 'with a project-level custom role granting only read_security_attribute' do
        let_it_be(:custom_role_group) { create(:group) }
        let_it_be_with_reload(:project) { create(:project, group: custom_role_group) }
        let_it_be(:role) do
          create(:member_role, :reporter, :read_security_attribute, namespace: custom_role_group)
        end

        let_it_be(:current_user) { create(:user) }

        before_all do
          create(:project_member, :reporter, member_role: role, user: current_user, source: project)
        end

        context 'when security attributes are available' do
          before do
            stub_licensed_features(custom_roles: true, security_attributes: true)
          end

          it { expect_allowed(:read_security_attribute) }
        end

        context 'when security attributes are not available' do
          before do
            stub_licensed_features(custom_roles: true, security_attributes: false)
          end

          it { expect_disallowed(:read_security_attribute) }
        end

        context 'when security and compliance is disabled on the project' do
          before do
            stub_licensed_features(custom_roles: true, security_attributes: true)
            project.project_feature.update!(security_and_compliance_access_level: Featurable::DISABLED)
          end

          it { expect_disallowed(:read_security_attribute) }
        end
      end
    end

    describe 'security scan profiles' do
      it_behaves_like 'prevents permissions when the licensed feature is disabled',
        licensed_feature: :security_scan_profiles,
        permissions: %i[read_security_scan_profiles apply_security_scan_profiles],
        roles: %w[developer security_manager owner]

      context 'with a custom role granting apply_security_scan_profiles' do
        include_context 'with custom role in project'

        let(:member_role_abilities) { { apply_security_scan_profiles: true } }
        let(:allowed_abilities) { [:apply_security_scan_profiles] }
        let(:licensed_features) { { security_scan_profiles: true } }

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:security_manager, :maintainer, :owner]
      end
    end

    describe 'remove_project when default_project_deletion_protection is set to true' do
      before do
        stub_application_setting(default_project_deletion_protection: true)
      end

      context 'with admin' do
        let(:current_user) { admin }

        context 'when admin mode enabled', :enable_admin_mode do
          it { expect_allowed(:remove_project) }
        end

        context 'when admin mode disabled' do
          it { expect_disallowed(:remove_project) }

          context 'and admin owns the project' do
            let_it_be(:project) { create(:project, :public, namespace: admin.namespace) }

            it { expect_disallowed(:remove_project) }
          end
        end
      end

      context 'with owner' do
        let(:current_user) { owner }

        it { expect_disallowed(:remove_project) }
      end

      context 'with a custom role granting remove_project' do
        let(:project) { public_project_in_group }
        let(:current_user) { guest }

        before do
          stub_licensed_features(custom_roles: true)
          member = project.members.find_by(user: guest)
          create(:member_role, :guest, :remove_project, namespace: group, members: [member])
        end

        it { expect_disallowed(:remove_project) }
      end
    end

    describe 'admin_feature_flags_issue_links' do
      before do
        stub_licensed_features(feature_flags_related_issues: true)
      end

      context 'with maintainer' do
        let(:current_user) { maintainer }

        context 'when repository is disabled' do
          before do
            project.project_feature.update!(
              merge_requests_access_level: ProjectFeature::DISABLED,
              builds_access_level: ProjectFeature::DISABLED,
              repository_access_level: ProjectFeature::DISABLED
            )
          end

          it { expect_disallowed(:admin_feature_flags_issue_links) }
        end
      end

      context 'with developer' do
        let(:current_user) { developer }

        context 'when feature is unlicensed' do
          before do
            stub_licensed_features(feature_flags_related_issues: false)
          end

          it { expect_disallowed(:admin_feature_flags_issue_links) }
        end
      end
    end

    describe 'admin_software_license_policy' do
      context 'without license scanning feature available' do
        before do
          stub_licensed_features(license_scanning: false)
        end

        let(:current_user) { admin }

        it { expect_disallowed(:admin_software_license_policy) }
      end

      context 'with admin when admin mode disabled' do
        let(:current_user) { admin }

        it { expect_disallowed(:admin_software_license_policy) }
      end
    end

    describe 'value stream permissions' do
      let(:value_stream_permissions) do
        %i[create_value_stream update_value_stream delete_value_stream]
      end

      context 'with reporter when cycle_analytics_for_projects is enabled' do
        let(:current_user) { reporter }

        it { expect_allowed(*value_stream_permissions) }
      end

      it_behaves_like 'prevents permissions when the licensed feature is disabled',
        licensed_feature: :cycle_analytics_for_projects,
        permissions: %i[create_value_stream update_value_stream delete_value_stream],
        roles: %w[reporter owner]
    end

    describe 'publish_status_page' do
      context 'with admin when admin mode disabled' do
        let(:current_user) { admin }

        it { expect_disallowed(:publish_status_page) }
      end

      it_behaves_like 'prevents permissions when the licensed feature is disabled',
        licensed_feature: :status_page,
        permissions: [:publish_status_page],
        roles: %w[developer owner]
    end

    context 'visual review bot' do
      let(:current_user) { Users::Internal.in_organization(project.organization).visual_review_bot }

      it { expect_disallowed(:create_note, :read_note, :resolve_note) }
    end

    context 'when push_rules is not enabled by the current license' do
      before do
        stub_licensed_features(push_rules: false)
      end

      let(:current_user) { maintainer }

      it { expect_disallowed(:change_push_rules) }
    end

    context 'commit_committer_check is not enabled by the current license' do
      before do
        stub_licensed_features(commit_committer_check: false)
      end

      let(:current_user) { maintainer }

      it { expect_disallowed(:change_commit_committer_check, :read_commit_committer_check) }
    end

    context 'when commit_committer_name_check is not enabled by the current license' do
      before do
        stub_licensed_features(commit_committer_name_check: false)
      end

      let(:current_user) { maintainer }

      it { expect_disallowed(:read_commit_committer_name_check, :change_commit_committer_name_check) }
    end

    context 'reject_unsigned_commits is not enabled by the current license' do
      before do
        stub_licensed_features(reject_unsigned_commits: false)
      end

      let(:current_user) { maintainer }

      it { expect_disallowed(:change_reject_unsigned_commits, :read_reject_unsigned_commits) }
    end

    context 'when reject_non_dco_commits is not enabled by the current license' do
      before do
        stub_licensed_features(reject_non_dco_commits: false)
      end

      let(:current_user) { maintainer }

      it { expect_disallowed(:read_reject_non_dco_commits, :change_reject_non_dco_commits) }
    end

    context 'when dora4 analytics is not available' do
      let(:current_user) { developer }

      before do
        stub_licensed_features(dora4_analytics: false)
      end

      it { expect_disallowed(:read_dora4_analytics) }
    end

    describe ':read_contribution_analytics' do
      context 'when contribution_analytics is not available' do
        let(:current_user) { developer }
        let(:project) { private_project }

        before do
          stub_licensed_features(contribution_analytics: false)
        end

        it { expect_disallowed(:read_contribution_analytics) }
      end
    end

    describe 'AI analytics' do
      it_behaves_like 'prevents permissions when the licensed feature is disabled',
        licensed_feature: :ai_analytics,
        permissions: %i[read_enterprise_ai_analytics read_pro_ai_analytics],
        roles: %w[reporter owner]
    end

    describe ':read_code_review_analytics' do
      let(:policy) { :read_code_review_analytics }
      let(:project) { internal_project }

      where(role: %i[guest planner reporter developer maintainer owner admin])

      with_them do
        let(:current_user) { public_send(role) }

        before do
          enable_admin_mode!(current_user) if role == :admin
        end

        it { expect_allowed(policy) }
      end

      it_behaves_like 'prevents permissions when the licensed feature is disabled',
        licensed_feature: :code_review_analytics,
        permissions: [:read_code_review_analytics],
        roles: %w[reporter owner]
    end

    shared_examples 'merge request approval settings' do |admin_override_allowed = false|
      let(:project) { private_project }

      context 'with merge request approvers rules available in license' do
        where(:role, :setting, :admin_mode, :allowed) do
          :maintainer | true  | nil    | false
          :owner      | true  | nil    | false
          :admin      | true  | false  | false
          :admin      | true  | true   | admin_override_allowed
        end

        with_them do
          let(:current_user) { public_send(role) }

          before do
            stub_licensed_features(admin_merge_request_approvers_rules: true)
            stub_application_setting(app_setting => setting)
            enable_admin_mode!(current_user) if admin_mode
          end

          it { is_expected.to(allowed ? be_allowed(policy) : be_disallowed(policy)) }
        end
      end

      context 'with merge request approvers rules not available in license' do
        where(:role, :setting, :admin_mode, :allowed) do
          :maintainer | true  | nil    | true
          :owner      | true  | nil    | true
          :admin      | true  | true   | true
        end

        with_them do
          let(:current_user) { public_send(role) }

          before do
            stub_licensed_features(admin_merge_request_approvers_rules: false)
            stub_application_setting(app_setting => setting)
            enable_admin_mode!(current_user) if admin_mode
          end

          it { is_expected.to(allowed ? be_allowed(policy) : be_disallowed(policy)) }
        end
      end
    end

    describe ':admin_merge_request_approval_settings' do
      let(:project) { private_project }

      it_behaves_like 'prevents permissions when the licensed feature is disabled',
        licensed_feature: :merge_request_approvers,
        permissions: [:admin_merge_request_approval_settings],
        roles: %w[maintainer owner]
    end

    describe ':modify_approvers_rules' do
      it_behaves_like 'merge request approval settings', true do
        let(:app_setting) { :disable_overriding_approvers_per_merge_request }
        let(:policy) { :modify_approvers_rules }
      end
    end

    describe 'approval rule editing' do
      let(:project) { private_project }

      context 'when the instance-level approval rule lock is enabled' do
        before do
          stub_licensed_features(admin_merge_request_approvers_rules: true)
          stub_application_setting(disable_overriding_approvers_per_merge_request: true)
        end

        context 'when user is a maintainer' do
          let(:current_user) { maintainer }

          it do
            expect_disallowed(
              :create_approval_rule,
              :delete_approval_rule,
              :modify_approvers_rules,
              :update_approval_rule
            )
          end
        end

        context 'when user is an admin', :enable_admin_mode do
          let(:current_user) { admin }

          it do
            expect_allowed(:modify_approvers_rules, :create_approval_rule, :update_approval_rule, :delete_approval_rule)
          end
        end
      end

      context 'when only the project-level override setting is enabled' do
        let(:current_user) { maintainer }

        before do
          stub_licensed_features(admin_merge_request_approvers_rules: true)
          project.update!(disable_overriding_approvers_per_merge_request: true)
        end

        it do
          expect_allowed(:modify_approvers_rules, :create_approval_rule, :update_approval_rule, :delete_approval_rule)
        end
      end
    end

    describe ':modify_merge_request_author_setting' do
      it_behaves_like 'merge request approval settings' do
        let(:app_setting) { :prevent_merge_requests_author_approval }
        let(:policy) { :modify_merge_request_author_setting }
      end
    end

    describe ':modify_merge_request_committer_setting' do
      it_behaves_like 'merge request approval settings' do
        let(:app_setting) { :prevent_merge_requests_committers_approval }
        let(:policy) { :modify_merge_request_committer_setting }
      end
    end

    describe 'requirements' do
      let(:requirement_permissions) do
        %i[read_requirement create_requirement admin_requirement update_requirement destroy_requirement
          create_requirement_test_report export_requirements]
      end

      before do
        stub_licensed_features(requirements: true)
      end

      context 'with guest' do
        let(:current_user) { guest }

        it { expect_allowed(:read_requirement) }
        it { expect_disallowed(*(requirement_permissions - [:read_requirement])) }
      end

      context 'with non member' do
        let(:current_user) { non_member }

        it { expect_allowed(:read_requirement) }
      end

      context 'when access level is disabled' do
        let(:current_user) { owner }

        before do
          project.project_feature.update!(requirements_access_level: ProjectFeature::DISABLED)
        end

        it { expect_disallowed(*requirement_permissions) }
      end

      context 'when access level is private' do
        before do
          project.project_feature.update!(requirements_access_level: ProjectFeature::PRIVATE)
        end

        context 'with non member' do
          let(:current_user) { non_member }

          it { expect_disallowed(*requirement_permissions) }
        end

        context 'with admin' do
          let(:current_user) { admin }

          it { expect_disallowed(*requirement_permissions) }

          context 'with admin mode enabled' do
            before do
              enable_admin_mode!(current_user)
            end

            it { expect_allowed(*requirement_permissions) }
          end
        end
      end

      context 'with non member of a private project' do
        let(:project) { private_project }
        let(:current_user) { non_member }

        it { expect_disallowed(*requirement_permissions) }
      end

      it_behaves_like 'prevents permissions when the licensed feature is disabled',
        licensed_feature: :requirements,
        permissions: %i[read_requirement create_requirement admin_requirement update_requirement destroy_requirement
          create_requirement_test_report export_requirements],
        roles: %w[planner owner]
    end

    describe 'Quality Management test case' do
      context 'with admin when admin mode disabled' do
        let(:current_user) { admin }

        it { expect_disallowed(:create_test_case) }
      end

      it_behaves_like 'prevents permissions when the licensed feature is disabled',
        licensed_feature: :quality_management,
        permissions: [:create_test_case],
        roles: %w[planner owner]
    end

    shared_examples_for 'prevents CI cancellation ability' do
      context 'when feature is enabled' do
        where(:restricted_role, :actual_role, :allowed) do
          :maintainer | :developer  | false
          :maintainer | :maintainer | true
          :no_one     | :owner      | false
        end

        with_them do
          let(:current_user) { public_send(actual_role) }

          before do
            stub_licensed_features(ci_pipeline_cancellation_restrictions: true)
            project.update!(restrict_pipeline_cancellation_role: restricted_role)
          end

          it { is_expected.to(allowed ? be_allowed(ability) : be_disallowed(ability)) }
        end
      end
    end

    describe 'prevents cancel_pipeline when CI cancllation restricted' do
      let(:ability) { :cancel_pipeline }

      it_behaves_like 'prevents CI cancellation ability'
    end

    describe 'prevents cancel_build when CI cancllation restricted' do
      let(:ability) { :cancel_build }

      it_behaves_like 'prevents CI cancellation ability'
    end

    describe 'project level compliance features' do
      shared_examples 'project level compliance feature' do |feature, permission|
        let(:current_user) { owner }

        context 'when project is in personal namespace' do
          let(:project) { public_project }

          it { expect_disallowed(permission) }
        end

        context 'when disabled' do
          let(:project) { public_project_in_group }

          before do
            stub_licensed_features({ feature => false })
          end

          it { expect_disallowed(permission) }
        end
      end

      describe 'project level compliance dashboard' do
        it_behaves_like 'project level compliance feature', :project_level_compliance_dashboard,
          :read_compliance_dashboard
      end

      describe 'project level compliance adherence report' do
        it_behaves_like 'project level compliance feature', :project_level_compliance_adherence_report,
          :read_compliance_adherence_report
      end

      describe 'project level compliance violations report' do
        it_behaves_like 'project level compliance feature', :project_level_compliance_violations_report,
          :read_compliance_violations_report
      end
    end

    describe 'project level admin_compliance_framework check delegates to group' do
      let(:project)  { public_project_in_group }
      let(:policy) { :admin_compliance_framework }

      where(:role, :feature_enabled, :admin_mode, :allowed) do
        :owner      | false | nil   | false
        :admin      | false | true  | false
        :admin      | true  | false | false
      end

      with_them do
        let(:current_user) { role == :admin ? admin : owner }

        before do
          project.group.public_send(:"add_#{role}", current_user) unless role == :admin
          stub_licensed_features(compliance_framework: feature_enabled, custom_compliance_frameworks: feature_enabled)
          enable_admin_mode!(current_user) if admin_mode
        end

        it { allowed ? expect_allowed(policy) : expect_disallowed(policy) }
      end
    end

    describe 'Incident Management on-call schedules' do
      let(:current_user) { public_send(role) }
      let(:admin_mode) { false }

      before do
        enable_admin_mode!(current_user) if admin_mode
        stub_licensed_features(oncall_schedules: true)
      end

      context ':read_incident_management_oncall_schedule' do
        let(:policy) { :read_incident_management_oncall_schedule }

        where(:role, :admin_mode, :allowed) do
          :reporter   | nil   | true
          :owner      | nil   | true
          :admin      | false | false
        end

        with_them do
          it { is_expected.to(allowed ? be_allowed(policy) : be_disallowed(policy)) }

          context 'with unavailable license' do
            before do
              stub_licensed_features(oncall_schedules: false)
            end

            it { expect_disallowed(policy) }
          end
        end

        it_behaves_like 'monitor feature visibility', allow_lowest_role: :reporter
      end

      context ':admin_incident_management_oncall_schedule' do
        let(:policy) { :admin_incident_management_oncall_schedule }

        where(:role, :admin_mode, :allowed) do
          :maintainer | nil   | true
          :owner      | nil   | true
          :admin      | false | false
        end

        with_them do
          it { is_expected.to(allowed ? be_allowed(policy) : be_disallowed(policy)) }

          context 'with unavailable license' do
            before do
              stub_licensed_features(oncall_schedules: false)
            end

            it { expect_disallowed(policy) }
          end
        end

        it_behaves_like 'monitor feature visibility', allow_lowest_role: :maintainer
      end
    end

    describe 'Escalation Policies' do
      let(:current_user) { public_send(role) }
      let(:admin_mode) { false }

      before do
        enable_admin_mode!(current_user) if admin_mode
        allow(::Gitlab::IncidentManagement).to receive(:escalation_policies_available?).with(project).and_return(true)
      end

      context ':read_incident_management_escalation_policy' do
        let(:policy) { :read_incident_management_escalation_policy }

        where(:role, :admin_mode, :allowed) do
          :reporter   | nil   | true
          :owner      | nil   | true
          :admin      | false | false
        end

        with_them do
          it { is_expected.to(allowed ? be_allowed(policy) : be_disallowed(policy)) }

          context 'with unavailable escalation policies' do
            before do
              allow(::Gitlab::IncidentManagement).to receive(:escalation_policies_available?).with(project).and_return(false)
            end

            it { expect_disallowed(policy) }
          end
        end

        it_behaves_like 'monitor feature visibility', allow_lowest_role: :reporter
      end

      %i[create_escalation_policy update_escalation_policy delete_escalation_policy].each do |permission|
        context ":#{permission}" do
          let(:policy) { permission }

          where(:role, :admin_mode, :allowed) do
            :maintainer | nil   | true
            :owner      | nil   | true
            :admin      | false | false
          end

          with_them do
            it { is_expected.to(allowed ? be_allowed(policy) : be_disallowed(policy)) }

            context 'with unavailable escalation policies' do
              before do
                allow(::Gitlab::IncidentManagement).to receive(:escalation_policies_available?).with(project).and_return(false)
              end

              it { expect_disallowed(policy) }
            end
          end

          it_behaves_like 'monitor feature visibility', allow_lowest_role: :maintainer
        end
      end
    end

    context 'when project is read only on the namespace' do
      let(:project) { public_project_in_group }
      let(:current_user) { maintainer }
      let(:abilities) do
        described_class.readonly_features.flat_map do |feature|
          [
            :"create_#{feature}",
            :"update_#{feature}"
          ]
        end + described_class.readonly_abilities
      end

      before do
        allow(project.root_namespace).to receive(:read_only?).and_return(read_only)
        allow(project).to receive(:design_management_enabled?).and_return(true)
        stub_licensed_features(security_dashboard: true, license_scanning: true, quality_management: true)
      end

      context 'when the group is read only' do
        let(:read_only) { true }

        it { expect_disallowed(*abilities) }
      end

      context 'when the group is not read only' do
        let(:read_only) { false }

        # These are abilities that are not explicitly allowed by policies because most of them are not
        # real abilities.
        let(:abilities_not_currently_enabled) do
          %i[create_merge_request create_issue_board_list create_issue_board update_issue_board
            update_issue_board_list create_label update_label create_milestone
            update_milestone update_wiki update_design admin_design update_note
            update_pipeline_schedule admin_pipeline_schedule create_trigger update_trigger
            admin_trigger create_pages request_access create_board update_board
            create_issue_link update_issue_link
            create_feature_flags_client
            update_feature_flags_client update_iteration update_vulnerability create_vulnerability]
        end

        it { expect_allowed(*(abilities - abilities_not_currently_enabled)) }
      end
    end

    context 'project access tokens' do
      context 'GitLab.com Core resource access tokens', :saas do
        before do
          stub_ee_application_setting(should_check_namespace_plan: true)
        end

        context 'with admin access' do
          let(:current_user) { owner }

          before do
            project.add_owner(owner)
          end

          context 'when project belongs to a group' do
            let_it_be(:group) { create(:group) }
            let_it_be(:project) { create(:project, group: group) }

            specify :aggregate_failures do
              expect_disallowed(:create_resource_access_tokens)
              expect_allowed(:read_resource_access_tokens, :destroy_resource_access_tokens)
            end
          end

          context 'when project belongs to personal namespace' do
            it do
              expect_allowed(
                :create_resource_access_tokens,
                :destroy_resource_access_tokens,
                :read_resource_access_tokens
              )
            end
          end
        end

        context 'with non admin access' do
          let(:current_user) { developer }

          before do
            project.add_developer(developer)
          end

          context 'when project belongs to a group' do
            let_it_be(:group) { create(:group) }
            let_it_be(:project) { create(:project, group: group) }

            it do
              expect_disallowed(
                :create_resource_access_tokens,
                :destroy_resource_access_tokens,
                :read_resource_access_tokens
              )
            end
          end

          context 'when project belongs to personal namespace' do
            it do
              expect_disallowed(
                :create_resource_access_tokens,
                :destroy_resource_access_tokens,
                :read_resource_access_tokens
              )
            end
          end
        end
      end

      context 'on GitLab.com paid', :saas do
        let_it_be_with_refind(:group) { create(:group_with_plan, plan: :bronze_plan) }
        let_it_be_with_refind(:project) { create(:project, group: group) }

        context 'with maintainer access' do
          let(:current_user) { maintainer }

          before do
            project.add_maintainer(maintainer)
          end

          it_behaves_like 'GitLab.com Paid plan resource access tokens'

          context 'create resource access tokens' do
            it { expect_allowed(:create_resource_access_tokens) }

            context 'with a personal namespace project' do
              let(:namespace) { create(:namespace_with_plan, plan: :bronze_plan) }
              let(:project) { create(:project, namespace: namespace) }

              it { expect_allowed(:create_resource_access_tokens) }
            end

            context 'when resource access token creation is not allowed' do
              before do
                group.namespace_settings.update_column(:resource_access_token_creation_allowed, false)
              end

              it { expect_disallowed(:create_resource_access_tokens) }
            end

            context 'when parent group has resource access token creation disabled' do
              let(:resource_access_token_creation_allowed) { false }
              let(:ns_for_parent) do
                create(:namespace_settings,
                  resource_access_token_creation_allowed: resource_access_token_creation_allowed)
              end

              let(:parent) { create(:group_with_plan, plan: :bronze_plan, namespace_settings: ns_for_parent) }
              let(:group) { create(:group, parent: parent) }
              let(:project) { create(:project, group: group) }

              context 'cannot create resource access tokens' do
                it { expect_disallowed(:create_resource_access_tokens) }
              end
            end
          end

          context 'read resource access tokens' do
            it { expect_allowed(:read_resource_access_tokens) }
          end

          context 'destroy resource access tokens' do
            it { expect_allowed(:destroy_resource_access_tokens) }
          end
        end

        context 'with developer access' do
          let(:current_user) { developer }

          before do
            project.add_developer(developer)
          end

          context 'create resource access tokens' do
            it { expect_disallowed(:create_resource_access_tokens) }
          end

          context 'read resource access tokens' do
            it { expect_disallowed(:read_resource_access_tokens) }
          end

          context 'destroy resource access tokens' do
            it { expect_disallowed(:destroy_resource_access_tokens) }
          end
        end

        context 'with auditor access' do
          let(:current_user) { auditor }

          context 'read resource access tokens' do
            it { expect_allowed(:read_resource_access_tokens) }
          end

          context 'cannot create resource access tokens' do
            it { expect_disallowed(:create_resource_access_tokens) }
          end

          context 'cannot destroy resource access tokens' do
            it { expect_disallowed(:destroy_resource_access_tokens) }
          end
        end
      end
    end

    describe 'read_code_navigation' do
      # Granted to Reporter+ via config/authz/roles/reporter.yml, then gated by
      # prevent rules.
      let(:project) { public_project }

      before do
        stub_licensed_features(orbit: true)
        stub_feature_flags(orbit_promo_access_gate: false)
        allow(::Analytics::KnowledgeGraph).to receive(:service_configured?).and_return(true)
        create(:knowledge_graph_enabled_namespace, namespace: owner_namespace)
      end

      context 'when every requirement is met' do
        where(:role, :allowed) do
          :anonymous  | false
          :non_member | false
          :guest      | false
          :planner    | false
          :reporter   | true
          :developer  | true
          :maintainer | true
          :owner      | true
        end

        with_them do
          let(:current_user) { public_send(role) }

          it { is_expected.to(allowed ? be_allowed(:read_code_navigation) : be_disallowed(:read_code_navigation)) }
        end
      end

      context 'when the rollout flag is disabled' do
        let(:current_user) { reporter }

        before do
          stub_feature_flags(orbit_code_intelligence: false)
        end

        it { expect_disallowed(:read_code_navigation) }
      end

      context 'when Knowledge Graph is not configured on the instance' do
        let(:current_user) { reporter }

        before do
          allow(::Analytics::KnowledgeGraph).to receive(:service_configured?).and_return(false)
        end

        it { expect_disallowed(:read_code_navigation) }
      end

      context 'when Orbit is not licensed' do
        let(:current_user) { reporter }

        before do
          stub_licensed_features(orbit: false)
        end

        it { expect_disallowed(:read_code_navigation) }
      end

      context 'when on SaaS with the Orbit promo access gate' do
        let_it_be(:orbit_group) { create(:group) }
        let_it_be(:group_project) { create(:project, :public, group: orbit_group) }

        let(:project) { group_project }
        let(:current_user) { reporter }

        before_all do
          group_project.add_reporter(reporter)
          create(:knowledge_graph_enabled_namespace, namespace: orbit_group)
        end

        before do
          stub_saas_features(gitlab_com_subscriptions: true)
          stub_feature_flags(orbit_promo_access_gate: true)
        end

        it { expect_disallowed(:read_code_navigation) }

        context 'when the root namespace has an active orbit_promo add-on' do
          before do
            create(:gitlab_subscription_add_on_purchase, :orbit_promo, namespace: orbit_group)
          end

          it { expect_allowed(:read_code_navigation) }
        end
      end

      context 'when the root namespace is not enrolled in Orbit indexing' do
        let(:current_user) { reporter }

        before do
          ::Analytics::KnowledgeGraph::EnabledNamespace.delete_all
        end

        it { expect_disallowed(:read_code_navigation) }
      end

      context 'when the user cannot read the code' do
        let(:current_user) { reporter }

        before do
          # Merge requests and builds cannot be more visible than the repository.
          project.project_feature.update!(
            repository_access_level: ::ProjectFeature::DISABLED,
            merge_requests_access_level: ::ProjectFeature::DISABLED,
            builds_access_level: ::ProjectFeature::DISABLED
          )
        end

        it { expect_disallowed(:read_code_navigation) }
      end
    end

    describe 'read_analytics' do
      context 'with various analytics features' do
        let_it_be(:project_with_analytics_disabled) { create(:project, :analytics_disabled) }
        let_it_be(:project_with_analytics_private) { create(:project, :analytics_private) }
        let_it_be(:project_with_analytics_enabled) { create(:project, :analytics_enabled) }

        let(:all_read_analytics_permissions) do
          %i[
            read_project_merge_request_analytics
            read_code_review_analytics
            read_cycle_analytics
            read_issue_analytics
          ]
        end

        before do
          stub_licensed_features(issues_analytics: true, code_review_analytics: true,
            project_merge_request_analytics: true, cycle_analytics_for_projects: true)

          project_with_analytics_disabled.add_developer(developer)
          project_with_analytics_private.add_developer(developer)
          project_with_analytics_enabled.add_developer(developer)
        end

        context 'when analytics is disabled for the project' do
          let(:project) { project_with_analytics_disabled }

          %w[guest planner developer admin auditor].each do |role|
            context "for #{role} user" do
              let(:current_user) { send(role) }

              it { expect_disallowed(*all_read_analytics_permissions) }
            end
          end
        end

        context 'when analytics is private for the project' do
          let(:project) { project_with_analytics_private }

          %w[guest planner].each do |role|
            context "for #{role} user" do
              let(:current_user) { send(role) }

              it { expect_disallowed(*all_read_analytics_permissions) }
            end
          end

          context 'for developer' do
            let(:current_user) { developer }

            it { expect_allowed(*all_read_analytics_permissions) }
          end

          context 'for admin', :enable_admin_mode do
            let(:current_user) { admin }

            it { expect_allowed(*all_read_analytics_permissions) }
          end

          context 'for auditor' do
            let(:current_user) { auditor }

            it { expect_allowed(*all_read_analytics_permissions) }
          end
        end

        context 'when analytics is enabled for the project' do
          let(:project) { project_with_analytics_enabled }

          %w[guest planner].each do |role|
            context "for #{role} user" do
              let(:current_user) { send(role) }

              specify :aggregate_failures do
                expect_disallowed(
                  :read_code_review_analytics,
                  :read_cycle_analytics,
                  :read_project_merge_request_analytics
                )
                expect_allowed(:read_issue_analytics)
              end
            end
          end
        end
      end
    end

    describe 'pending member permissions' do
      let_it_be(:current_user) { create(:user) }
      let_it_be(:group) { create(:group, :public) }

      context 'with a pending membership in a private project' do
        let_it_be(:project) { create(:project, :private, public_builds: false) }

        # Pending memberships are filtered regardless of the access level.
        where(role: %i[guest maintainer])

        with_them do
          it 'a pending member has permissions to the project as if the user is not a member' do
            create(:project_member, :awaiting, role, source: project, user: current_user)

            expect_no_permissions_beyond_non_member
          end
        end
      end

      context 'with a group invited to a project' do
        let_it_be(:project) { create(:project, :private, public_builds: false) }

        before_all do
          create(:project_group_link, project: project, group: group)
        end

        where(role: %i[guest owner])

        with_them do
          it 'a pending member in the group has permissions to the project as if the user is not a member' do
            create(:group_member, :awaiting, role, source: group, user: current_user)

            expect_no_permissions_beyond_non_member
          end
        end
      end

      context 'with a group invited to another group' do
        let_it_be(:other_group) { create(:group, :public) }
        let_it_be(:project) { create(:project, :private, public_builds: false, namespace: other_group) }

        before_all do
          create(:group_group_link, shared_with_group: group, shared_group: other_group)
        end

        where(role: %i[guest owner])

        with_them do
          it "a pending member in the group has permissions to the other group's project as if the user is not a member" do
            create(:group_member, :awaiting, role, source: group, user: current_user)

            expect_no_permissions_beyond_non_member
          end
        end
      end

      context 'with a subgroup' do
        let_it_be(:subgroup) { create(:group, :private, parent: group) }
        let_it_be(:project) { create(:project, :private, public_builds: false, namespace: subgroup) }

        where(role: %i[guest owner])

        with_them do
          it 'a pending member in the group has permissions to the subgroup project as if the user is not a member' do
            create(:group_member, :awaiting, role, source: group, user: current_user)

            expect_no_permissions_beyond_non_member
          end
        end
      end
    end

    context 'for membership locking' do
      let(:current_user) { owner }

      context 'for a personal project' do
        it { expect_allowed(:import_project_members_from_another_project, :invite_member) }
      end

      context 'for a project in a group' do
        let(:project) { create(:project, group: create(:group)) }

        context 'when the project has locked their membership' do
          context 'via the parent group' do
            before do
              project.group.update!(membership_lock: true)
            end

            it { expect_disallowed(:import_project_members_from_another_project, :invite_member) }
          end

          context 'via LDAP' do
            before do
              stub_application_setting(lock_memberships_to_ldap: true)
            end

            it { expect_disallowed(:import_project_members_from_another_project, :invite_member) }
          end

          context 'via SAML' do
            before do
              stub_application_setting(lock_memberships_to_saml: true)
            end

            it { expect_disallowed(:import_project_members_from_another_project, :invite_member) }
          end
        end
      end
    end

    describe 'inviting a group' do
      let_it_be_with_reload(:current_user) { developer }
      let_it_be_with_reload(:project) { public_project }

      let_it_be(:banned_group) { create(:group) }
      let_it_be(:banned_subgroup) { create(:group, parent: banned_group) }

      before do
        stub_licensed_features(unique_project_download_limit: true)
        create(:namespace_ban, user: current_user, namespace: banned_group)
      end

      it { expect_allowed(:read_project) }

      context 'when the user is banned from the invited group' do
        before do
          create(:project_group_link, project: project, group: banned_group)
        end

        it { expect_disallowed(:read_project) }
      end

      context 'when the user is banned from the invited subgroup' do
        before do
          create(:project_group_link, project: project, group: banned_subgroup)
        end

        it { expect_disallowed(:read_project) }
      end
    end

    describe 'user banned from namespace' do
      let_it_be_with_reload(:current_user) { create(:user) }

      let_it_be(:group) { create(:group, :private) }
      let_it_be(:project) { create(:project, :private, public_builds: false, group: group) }

      before do
        stub_licensed_features(unique_project_download_limit: true)
        project.add_developer(current_user)
      end

      context 'when user is not banned' do
        it { expect_allowed(:read_project) }
      end

      context 'when user is banned' do
        before do
          create(:namespace_ban, user: current_user, namespace: group.root_ancestor)
        end

        it { expect_disallowed(*described_class.own_ability_map.map.keys) }

        context 'as an owner of the project' do
          before do
            project.add_owner(current_user)
          end

          it { expect_disallowed(*described_class.own_ability_map.map.keys) }
        end

        context 'when project is inside subgroup' do
          let_it_be(:subgroup) { create(:group, :private, parent: group) }
          let_it_be(:project) { create(:project, :private, public_builds: false, group: subgroup) }

          it { expect_disallowed(*described_class.own_ability_map.map.keys) }
        end

        context 'as an admin' do
          let_it_be(:current_user) { admin }

          context 'when admin mode is enabled', :enable_admin_mode do
            it { expect_allowed(:read_project) }
          end
        end

        context 'when project is public' do
          let_it_be(:group) { create(:group, :public) }
          let_it_be(:project) { create(:project, :public, public_builds: false, group: group) }

          it { expect_disallowed(:read_project) }
        end

        context 'when licensed feature unique_project_download_limit is not available' do
          before do
            stub_licensed_features(unique_project_download_limit: false)
          end

          it { expect_allowed(:read_project) }
        end
      end
    end

    describe 'create_objective' do
      let(:project) { private_project }

      let(:okr_policies) { [:create_objective, :create_key_result] }

      where(:role, :allowed) do
        :guest      | true
        :auditor    | false
        :owner      | true
      end

      with_them do
        let(:current_user) { public_send(role) }

        before do
          stub_licensed_features(okrs: true)
        end

        context 'when okrs_mvc feature flag is enabled' do
          it { is_expected.to(allowed ? be_allowed(*okr_policies) : be_disallowed(*okr_policies)) }
        end

        context 'when okrs_mvc feature flag is disabled' do
          before do
            stub_feature_flags(okrs_mvc: false)
          end

          it { expect_disallowed(*okr_policies) }
        end

        context 'when okrs license feature is not available' do
          before do
            stub_licensed_features(okrs: false)
          end

          it { expect_disallowed(*okr_policies) }
        end
      end
    end

    describe 'read_member_role' do
      let_it_be_with_reload(:project) { private_project_in_group }
      let_it_be_with_reload(:current_user) { create(:user) }

      let(:permission) { :read_member_role }

      where(role: %i[guest owner])

      with_them do
        before do
          create(:project_member, role, source: project, user: current_user)
        end

        context 'when custom_roles feature is disabled' do
          before do
            stub_licensed_features(custom_roles: false)
          end

          it { expect_disallowed(permission) }
        end
      end
    end

    context 'hidden projects' do
      let_it_be(:current_user) { create(:user) }
      let_it_be(:project) { create(:project, :small_repo, hidden: true, owners: current_user) }

      it { expect_disallowed(:download_code, :build_download_code, :read_protectable_branch) }
    end

    context 'custom role' do
      include_context 'with custom role in project'

      context 'for a member role with the `read_code` ability' do
        let(:member_role_abilities) { { read_code: true } }
        let(:allowed_abilities) { [:read_code] }

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:reporter, :developer, :maintainer, :owner]

        context 'when repository access level is set as disabled' do
          before do
            project.project_feature.update_column(:repository_access_level, ProjectFeature::DISABLED)

            create_member_role(project_member_guest)
          end

          after do
            project.project_feature.update_column(:repository_access_level, ProjectFeature::ENABLED)
          end

          it { expect_disallowed(:read_code) }
        end
      end

      context 'for a member role with the `admin_runners` ability' do
        let(:member_role_abilities) { { read_runners: true, admin_runners: true } }
        let(:allowed_abilities) { [:admin_runners, :create_runners, :read_runners] }

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:maintainer, :owner]
      end

      context 'for a member role with the `read_vulnerability` ability' do
        let(:member_role_abilities) { { read_vulnerability: true } }
        let(:licensed_features) { { security_dashboard: true } }
        let(:allowed_abilities) do
          [
            :access_security_and_compliance,
            :admin_vulnerability_external_issue_link,
            :admin_vulnerability_issue_link,
            :create_vulnerability_archive_export,
            :create_vulnerability_export,
            :read_project_security_dashboard,
            :read_security_project_tracked_ref,
            :read_security_resource,
            :read_vulnerability,
            :read_vulnerability_feedback,
            :read_vulnerability_scanner
          ]
        end

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:developer, :maintainer, :owner]

        it 'does not enable to admin_vulnerability' do
          expect(subject).to be_disallowed(:admin_vulnerability)
        end
      end

      context 'for a member role with the `admin_terraform_state` ability' do
        let(:member_role_abilities) { { admin_terraform_state: true } }
        let(:allowed_abilities) { [:read_terraform_state, :admin_terraform_state] }

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:maintainer, :owner]
      end

      context 'for a member role with the `admin_vulnerability` ability' do
        let(:member_role_abilities) { { read_vulnerability: true, admin_vulnerability: true } }
        let(:licensed_features) { { security_dashboard: true } }
        let(:allowed_abilities) do
          [
            :admin_vulnerability,
            :confirm_vulnerability,
            :create_vulnerability_feedback,
            :create_vulnerability_state_transition,
            :destroy_vulnerability_feedback,
            :dismiss_vulnerability,
            :read_security_resource,
            :read_vulnerability,
            :read_vulnerability_feedback,
            :resolve_vulnerability,
            :revert_vulnerability,
            :update_vulnerability_feedback,
            :update_vulnerability_severity
          ]
        end

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:maintainer, :owner]
      end

      context 'for a member role with the `read_dependency` ability' do
        let(:member_role_abilities) { { read_dependency: true } }
        let(:allowed_abilities) { [:access_security_and_compliance, :read_dependency, :read_licenses] }
        let(:licensed_features) { { dependency_scanning: true, license_scanning: true } }

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:developer, :maintainer, :owner]
      end

      context 'for a member role with the `admin_merge_request` true' do
        let(:member_role_abilities) { { admin_merge_request: true } }
        let(:allowed_abilities) { [:admin_merge_request] }

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:developer, :maintainer, :owner]

        context 'when the merge requests access level is set as private' do
          before do
            project.project_feature.update_column(:merge_requests_access_level, ProjectFeature::PRIVATE)
          end

          it_behaves_like 'custom roles abilities'
        end

        context 'when the merge requests access level is set as disabled' do
          before do
            project.project_feature.update_column(:merge_requests_access_level, ProjectFeature::DISABLED)
          end

          it { expect_disallowed(:read_merge_request, :admin_merge_request, :download_code) }
        end
      end

      context 'for a member role with the `manage_project_access_tokens` ability' do
        let(:member_role_abilities) { { manage_project_access_tokens: true } }
        let(:allowed_abilities) { [:manage_resource_access_tokens] }

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:maintainer, :owner]
      end

      context 'for a member role with the `archive_project` ability' do
        let(:member_role_abilities) { { archive_project: true } }
        let(:allowed_abilities) { [:archive_project, :view_edit_page] }

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:owner]
      end

      context 'for a member role with the `remove_project` ability' do
        let(:member_role_abilities) { { remove_project: true } }
        let(:allowed_abilities) { [:remove_project, :view_edit_page] }

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:owner]
      end

      context 'for a member role with the `manage_security_policy_link` ability' do
        let(:member_role_abilities) { { manage_security_policy_link: true } }
        let(:licensed_features) { { security_orchestration_policies: true } }
        let(:allowed_abilities) do
          [:read_security_orchestration_policies, :update_security_orchestration_policy_project,
            :access_security_and_compliance]
        end

        let(:disallowed_abilities) { [:modify_security_policy] }

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:owner]
      end

      context 'when a user is assigned to member roles in both group and project' do
        before do
          stub_licensed_features(custom_roles: true, dependency_scanning: true)

          create_member_role(group_member_guest, { read_dependency: true })
          create_member_role(project_member_guest, { read_code: true })
        end

        it { expect_allowed(:read_dependency, :read_code) }
      end

      context 'for a member role with the `admin_cicd_variables` ability' do
        let(:member_role_abilities) { { admin_cicd_variables: true } }
        let(:allowed_abilities) { [:admin_cicd_variables] }

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:maintainer, :owner]
      end

      context 'for a member role with the `admin_protected_environments` ability' do
        let(:member_role_abilities) { { admin_protected_environments: true } }
        let(:allowed_abilities) { [:admin_protected_environments] }

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:maintainer, :owner]

        context 'when builds access level is set as disabled' do
          before do
            project.project_feature.update_column(:builds_access_level, ProjectFeature::DISABLED)

            create_member_role(project_member_guest)
          end

          after do
            project.project_feature.update_column(:builds_access_level, ProjectFeature::ENABLED)
          end

          it { expect_disallowed(:admin_protected_environments) }
        end
      end

      context 'for a member role with the `admin_push_rules` ability' do
        let(:member_role_abilities) { { admin_push_rules: true } }

        let(:licensed_features) do
          {
            custom_roles: true,
            push_rules: true,
            commit_committer_check: true,
            commit_committer_name_check: true,
            reject_unsigned_commits: true,
            reject_non_dco_commits: true
          }
        end

        let(:allowed_abilities) do
          [
            :admin_push_rules,
            :change_push_rules,
            :read_commit_committer_check,
            :change_commit_committer_check,
            :change_commit_committer_name_check,
            :read_reject_unsigned_commits,
            :change_reject_unsigned_commits,
            :change_reject_non_dco_commits
          ]
        end

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:maintainer, :owner]
      end

      context 'for a member role with the `admin_compliance_framework` ability' do
        let(:licensed_features) do
          {
            compliance_framework: true,
            custom_compliance_frameworks: true,
            project_level_compliance_dashboard: true,
            project_level_compliance_adherence_report: true,
            project_level_compliance_violations_report: true
          }
        end

        let(:member_role_abilities) { { read_compliance_dashboard: true, admin_compliance_framework: true } }

        let(:allowed_abilities) do
          [
            :admin_compliance_framework,
            :read_compliance_dashboard,
            :read_compliance_adherence_report,
            :read_compliance_violations_report
          ]
        end

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:owner]
      end

      context 'for a member role with the `read_compliance_dashboard` ability' do
        let(:licensed_features) do
          {
            project_level_compliance_dashboard: true,
            project_level_compliance_adherence_report: true,
            project_level_compliance_violations_report: true
          }
        end

        let(:member_role_abilities) { { read_compliance_dashboard: true } }

        let(:allowed_abilities) do
          [
            :read_compliance_dashboard,
            :read_compliance_adherence_report,
            :read_compliance_violations_report
          ]
        end

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:owner, :security_manager]
      end

      context 'for a member role with the `admin_web_hook` ability' do
        let(:member_role_abilities) { { admin_web_hook: true } }
        let(:allowed_abilities) do
          [
            :create_webhook, :read_webhook, :update_webhook, :delete_webhook,
            :test_webhook, :update_webhook_url_variable, :delete_webhook_url_variable, :update_webhook_custom_header,
            :delete_webhook_custom_header, :read_webhook_event, :resend_webhook_event
          ]
        end

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:maintainer, :owner]
      end

      context 'for a member role with the `manage_deploy_tokens` ability' do
        let(:member_role_abilities) { { manage_deploy_tokens: true } }
        let(:allowed_abilities) do
          [:manage_deploy_tokens, :read_deploy_token, :create_deploy_token, :destroy_deploy_token]
        end

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:maintainer, :owner]
      end

      context 'for a member role with the `manage_merge_request_settings` ability' do
        let(:member_role_abilities) { { read_code: true, manage_merge_request_settings: true } }
        let(:allowed_abilities) do
          [
            :manage_merge_request_settings,
            :create_approval_rule,
            :update_approval_rule,
            :delete_approval_rule,
            :modify_approvers_rules,
            :modify_merge_request_author_setting,
            :modify_merge_request_committer_setting,
            :read_branch_rule,
            :create_squash_option,
            :read_squash_option,
            :update_squash_option,
            :delete_squash_option
          ]
        end

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:owner]

        context 'when `target_branch_rules` feature is available' do
          let(:licensed_features) { { target_branch_rules: true } }
          let(:allowed_abilities) { [:admin_target_branch_rule] }

          it_behaves_like 'custom roles abilities'
        end

        context 'when `merge_request_approvers` feature is available' do
          let(:licensed_features) { { merge_request_approvers: true } }
          let(:allowed_abilities) { [:admin_merge_request_approval_settings] }

          it_behaves_like 'custom roles abilities'
        end
      end

      context 'for a member role with the `admin_integrations` ability' do
        let(:member_role_abilities) { { admin_integrations: true } }
        let(:allowed_abilities) { [:admin_integrations] }

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:maintainer, :owner]
      end

      context 'for a member role with the `read_runners` ability' do
        let(:member_role_abilities) { { read_runners: true } }
        let(:allowed_abilities) { [:read_runners] }

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:maintainer, :owner]
      end

      context 'for a member role with `admin_protected_branch` true' do
        let(:member_role_abilities) { { admin_protected_branch: true } }
        let(:allowed_abilities) do
          [
            :admin_protected_branch,
            :create_protected_branch,
            :destroy_protected_branch,
            :read_branch_rule,
            :read_protectable_branch,
            :read_protected_branch,
            :update_protected_branch
          ]
        end

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:maintainer, :owner]
      end

      context 'for a member role with the `admin_ai_catalog_item` ability' do
        let(:member_role_abilities) { { admin_ai_catalog_item: true } }
        let(:allowed_abilities) { [:admin_ai_catalog_item, :create_ai_catalog_agent] }

        before do
          allow(project).to receive(:ai_catalog_available?).and_return(true)
          allow_next_instance_of(described_class) do |policy|
            allow(policy).to receive(:user_allowed_to_use_through_namespace?).and_return(true)
          end
          project.root_ancestor.namespace_settings.update!(duo_custom_agents_enabled: true)
        end

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:maintainer, :owner]

        context 'when flows are enabled' do
          let(:allowed_abilities) { [:admin_ai_catalog_item, :create_ai_catalog_flow, :create_ai_catalog_agent] }

          before do
            allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :ai_catalog_flows).and_return(true)
            project.root_ancestor.namespace_settings.update!(duo_custom_flows_enabled: true)
          end

          it_behaves_like 'custom roles abilities'
        end

        context 'when agents are disabled' do
          let(:allowed_abilities) { [:admin_ai_catalog_item] }

          before do
            project.root_ancestor.namespace_settings.update!(duo_custom_agents_enabled: false)
          end

          it_behaves_like 'custom roles abilities'
        end
      end

      context 'for a member role with the `admin_ai_catalog_item_consumer` ability' do
        let(:member_role_abilities) { { admin_ai_catalog_item_consumer: true } }
        let(:allowed_abilities) do
          [:admin_ai_catalog_item_consumer, :create_ai_catalog_item_consumer, :create_ai_catalog_agent_item_consumer]
        end

        before do
          allow(project).to receive(:ai_catalog_available?).and_return(true)
          allow_next_instance_of(described_class) do |policy|
            allow(policy).to receive(:user_allowed_to_use_through_namespace?).and_return(true)
          end
          project.root_ancestor.namespace_settings.update!(duo_custom_agents_enabled: true)
        end

        it_behaves_like 'custom roles abilities'

        it_behaves_like 'does not call custom role query', [:maintainer, :owner]

        context 'when flows are enabled' do
          let(:allowed_abilities) do
            [:admin_ai_catalog_item_consumer, :create_ai_catalog_item_consumer,
              :create_ai_catalog_flow_item_consumer, :create_ai_catalog_agent_item_consumer]
          end

          before do
            allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :ai_catalog_flows).and_return(true)
            project.root_ancestor.namespace_settings.update!(duo_custom_flows_enabled: true)
          end

          it_behaves_like 'custom roles abilities'
        end

        context 'when agents are disabled' do
          let(:allowed_abilities) { [:admin_ai_catalog_item_consumer, :create_ai_catalog_item_consumer] }

          before do
            project.root_ancestor.namespace_settings.update!(duo_custom_agents_enabled: false)
          end

          it_behaves_like 'custom roles abilities'
        end

        context 'when the duo agent platform is available' do
          let(:allowed_abilities) do
            [:admin_ai_catalog_item_consumer, :create_ai_catalog_item_consumer,
              :create_ai_catalog_agent_item_consumer, :manage_ai_flow_triggers,
              :read_ai_flow_triggers]
          end

          before do
            allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
            stub_ee_application_setting(duo_features_enabled: true)
            allow(guest).to receive(:allowed_to_use?)
              .with(:duo_agent_platform, root_namespace: project.root_ancestor)
              .and_return(true)
          end

          it_behaves_like 'custom roles abilities'
        end
      end
    end

    context 'admin custom role', :enable_admin_mode do
      let_it_be(:project) { create(:project, :private, public_builds: false) }
      let_it_be(:non_admin_user) { create(:user) }

      let(:member_role_abilities) { [] }
      let(:allowed_abilities) { [] }
      let(:current_user) { non_admin_user }

      subject { described_class.new(current_user, project) }

      shared_examples 'admin custom roles abilities' do
        context 'when custom roles feature is unavailable' do
          before do
            create(:admin_member_role, *member_role_abilities, user: current_user)

            stub_licensed_features(custom_roles: false)
          end

          it { expect_disallowed(*allowed_abilities) }
        end

        context 'when custom roles feature is available' do
          before do
            stub_licensed_features(custom_roles: true)
          end

          context 'when a role enables the abilities' do
            before do
              create(:admin_member_role, *member_role_abilities, user: current_user)
            end

            it { expect_allowed(*allowed_abilities) }
          end

          context 'when a role does not enable the abilities' do
            it { expect_disallowed(*allowed_abilities) }
          end
        end
      end

      context 'for an admin member role with read_admin_cicd true' do
        let(:member_role_abilities) { [:read_admin_cicd] }
        let(:allowed_abilities) { %i[read_project_metadata] }

        it_behaves_like 'admin custom roles abilities'
      end

      context 'for an admin member role with read_admin_projects true' do
        let(:member_role_abilities) { [:read_admin_projects] }
        let(:allowed_abilities) { %i[read_project_metadata] }

        it_behaves_like 'admin custom roles abilities'
      end
    end

    describe 'read_runner_usage' do
      where(:licensed, :current_user, :project, :enable_admin_mode, :clickhouse_configured, :expected) do
        false | ref(:maintainer) | ref(:public_project_in_group) | false | true  | false
        true  | ref(:maintainer) | ref(:public_project_in_group) | false | false | false
        true  | ref(:admin)      | ref(:public_project)          | true  | true  | false
        true  | ref(:maintainer) | ref(:public_project)          | false | true  | false
      end

      with_them do
        before do
          stub_licensed_features(runner_performance_insights_for_namespace: licensed)

          enable_admin_mode!(admin) if enable_admin_mode

          allow(::Gitlab::ClickHouse).to receive(:configured?).and_return(clickhouse_configured)
        end

        it 'matches expectation' do
          if expected
            expect_allowed(:read_runner_usage)
          else
            expect_disallowed(:read_runner_usage)
          end
        end
      end
    end

    describe 'create_pipeline policy' do
      context 'as a guest member' do
        let(:current_user) { guest }

        context 'and user is a security_policy_bot' do
          let_it_be(:security_policy_bot) { create(:user, user_type: :security_policy_bot) }
          let(:current_user) { security_policy_bot }

          it { expect_disallowed(:create_pipeline) }

          shared_examples 'allows to create pipeline' do
            let(:security_policy_bot) { create(:user, user_type: :security_policy_bot) }

            before do
              project.add_guest(security_policy_bot)
            end

            it { expect_allowed(:create_pipeline) }
          end

          context 'and user is a member of the project' do
            context 'and the project is private' do
              let(:project) { private_project }

              it_behaves_like 'allows to create pipeline'
            end

            context 'and the project is internal' do
              let(:project) { internal_project }

              it_behaves_like 'allows to create pipeline'
            end

            context 'and the project is public' do
              let(:project) { public_project }

              it_behaves_like 'allows to create pipeline'
            end

            context 'and the project is public in group' do
              let(:project) { public_project_in_group }

              it_behaves_like 'allows to create pipeline'
            end
          end
        end
      end
    end

    describe 'build_download_code policy' do
      let(:project) { private_project }

      context 'as a guest member' do
        let(:current_user) { guest }

        context 'and user is a security_policy_bot' do
          let_it_be(:security_policy_bot) { create(:user, user_type: :security_policy_bot) }
          let(:current_user) { security_policy_bot }

          it { expect_disallowed(:build_download_code) }

          context 'and user is a member of the project' do
            before do
              [private_project, internal_project, public_project, public_project_in_group].each do |project|
                project.add_guest(security_policy_bot)
              end
            end

            it { expect_allowed(:build_download_code) }
          end
        end
      end
    end

    describe 'update_pipeline policy' do
      context 'as a guest member' do
        let(:current_user) { guest }

        context 'and user is a security_policy_bot' do
          let_it_be(:security_policy_bot) { create(:user, user_type: :security_policy_bot) }
          let(:current_user) { security_policy_bot }

          it { expect_disallowed(:update_pipeline) }

          context 'and user is a member of the project' do
            shared_examples 'does not allow update_pipeline' do
              let(:security_policy_bot) { create(:user, user_type: :security_policy_bot) }

              before do
                project.add_guest(security_policy_bot)
              end

              it { expect_disallowed(:update_pipeline) }
            end

            context 'and the project is private' do
              let(:project) { private_project }

              it_behaves_like 'does not allow update_pipeline'
            end

            context 'and the project is internal' do
              let(:project) { internal_project }

              it_behaves_like 'does not allow update_pipeline'
            end

            context 'and the project is public' do
              let(:project) { public_project }

              it_behaves_like 'does not allow update_pipeline'
            end

            context 'and the project is public in group' do
              let(:project) { public_project_in_group }

              it_behaves_like 'does not allow update_pipeline'
            end
          end
        end
      end
    end

    describe 'create_bot_pipeline policy' do
      context 'as a guest member' do
        let(:current_user) { guest }

        context 'and user is a security_policy_bot' do
          let_it_be(:security_policy_bot) { create(:user, user_type: :security_policy_bot) }
          let(:current_user) { security_policy_bot }

          it { expect_disallowed(:create_bot_pipeline) }

          context 'and user is a member of the project' do
            shared_examples 'allows to create_bot_pipeline' do
              let(:security_policy_bot) { create(:user, user_type: :security_policy_bot) }

              before do
                project.add_guest(security_policy_bot)
              end

              it { expect_allowed(:create_bot_pipeline) }
            end

            context 'and the project is private' do
              let(:project) { private_project }

              it_behaves_like 'allows to create_bot_pipeline'
            end

            context 'and the project is internal' do
              let(:project) { internal_project }

              it_behaves_like 'allows to create_bot_pipeline'
            end

            context 'and the project is public' do
              let(:project) { public_project }

              it_behaves_like 'allows to create_bot_pipeline'
            end

            context 'and the project is public in group' do
              let(:project) { public_project_in_group }

              it_behaves_like 'allows to create_bot_pipeline'
            end
          end
        end
      end
    end

    describe 'security_policy_bot policy' do
      let_it_be(:security_policy_bot) { create(:user, user_type: :security_policy_bot) }
      let(:current_user) { security_policy_bot }

      context 'when user is authenticated via CI_JOB_TOKEN', :request_store do
        let(:project) { private_project }
        let(:job) { build_stubbed(:ci_build, project: scope_project, user: current_user) }
        let(:scope_project) { project }
        let(:bot_member_of_project) { true }

        let_it_be_with_reload(:other_private_project) { create(:project, :private) }

        shared_examples 'read_build is always allowed for security_policy_bot' do
          context 'when builds are public' do
            it { expect_allowed(:read_build) }
          end

          context 'when builds are not public' do
            before do
              project.update!(public_builds: false)
            end

            it { expect_allowed(:read_build) }
          end
        end

        before do
          allow(::Gitlab::CurrentSettings).to receive(:enforce_ci_inbound_job_token_scope_enabled?).and_return(instance_level_token_scope_enabled)
          project.add_guest(security_policy_bot) if bot_member_of_project
          current_user.set_ci_job_token_scope!(job)
          project.update!(
            ci_outbound_job_token_scope_enabled: token_scope_enabled,
            ci_inbound_job_token_scope_enabled: token_scope_enabled
          )
          scope_project.update!(
            ci_outbound_job_token_scope_enabled: token_scope_enabled,
            ci_inbound_job_token_scope_enabled: token_scope_enabled
          )
        end

        context 'when instance_level_token_scope_enabled is false' do
          let(:instance_level_token_scope_enabled) { false }
          let(:project) { private_project }

          context 'when token scope is disabled' do
            let(:token_scope_enabled) { false }

            context 'when pipeline is executed in project where bot is invited' do
              specify :aggregate_failures do
                expect_allowed(:create_pipeline)
                expect_disallowed(:update_pipeline)
                expect_allowed(:create_bot_pipeline, :build_download_code, :build_read_container_image, :read_package)
              end

              it_behaves_like 'read_build is always allowed for security_policy_bot'
            end

            context 'when pipeline is executed in project where bot is not invited' do
              let(:scope_project) { other_private_project }

              specify :aggregate_failures do
                expect_allowed(:create_pipeline)
                expect_disallowed(:update_pipeline)
                expect_allowed(:create_bot_pipeline, :build_download_code, :build_read_container_image, :read_package)
              end

              it_behaves_like 'read_build is always allowed for security_policy_bot'
            end
          end

          context 'when token scope is enabled' do
            let(:token_scope_enabled) { true }

            context 'when pipeline is executed in project where bot is invited' do
              specify :aggregate_failures do
                expect_allowed(:create_pipeline)
                expect_disallowed(:update_pipeline)
                expect_allowed(:create_bot_pipeline, :build_download_code, :build_read_container_image, :read_package)
              end

              it_behaves_like 'read_build is always allowed for security_policy_bot'
            end

            context 'when pipeline is executed in project where bot is not invited' do
              let(:scope_project) { other_private_project }

              it do
                expect_disallowed(
                  :build_download_code,
                  :create_bot_pipeline,
                  :create_pipeline,
                  :read_build,
                  :read_package,
                  :update_pipeline
                )
              end
            end
          end
        end

        context 'when instance_level_token_scope_enabled is true' do
          let(:instance_level_token_scope_enabled) { true }
          let(:project) { private_project }

          context 'when token scope is disabled' do
            let(:token_scope_enabled) { false }

            context 'when pipeline is executed in project where bot is invited' do
              specify :aggregate_failures do
                expect_allowed(:create_pipeline)
                expect_disallowed(:update_pipeline)
                expect_allowed(:create_bot_pipeline, :build_download_code, :build_read_container_image, :read_package)
              end

              it_behaves_like 'read_build is always allowed for security_policy_bot'
            end

            context 'when pipeline is executed in project where bot is not invited' do
              let(:scope_project) { other_private_project }

              it do
                expect_disallowed(
                  :build_download_code,
                  :create_bot_pipeline,
                  :create_pipeline,
                  :read_build,
                  :read_package,
                  :update_pipeline
                )
              end
            end
          end
        end

        context 'when project is private and bot is not invited' do
          let(:project) { private_project }
          let(:bot_member_of_project) { false }
          let(:instance_level_token_scope_enabled) { false }
          let(:token_scope_enabled) { false }

          it do
            expect_disallowed(
              :build_download_code,
              :create_bot_pipeline,
              :create_pipeline,
              :read_build,
              :read_package,
              :update_pipeline
            )
          end
        end

        context 'when accessing cross-project container registry via job token' do
          # Scenario: Bot is member of Project A, job runs in Project A,
          # job tries to pull images from Project B (where bot is NOT a member)
          # but Project B is in the job token allowlist.
          # See: https://gitlab.com/gitlab-org/gitlab/-/issues/630692
          let_it_be_with_reload(:bot_home_project) { create(:project, :private) }
          let_it_be_with_reload(:registry_project) { create(:project, :private) }

          let(:project) { registry_project }
          let(:scope_project) { bot_home_project }
          let(:job) { build_stubbed(:ci_build, project: bot_home_project, user: current_user) }
          let(:bot_member_of_project) { false }
          let(:instance_level_token_scope_enabled) { true }
          let(:token_scope_enabled) { true }

          before do
            bot_home_project.add_guest(security_policy_bot)
          end

          context 'when registry project is in the job token allowlist' do
            before do
              create(:ci_job_token_project_scope_link,
                source_project: registry_project,
                target_project: bot_home_project,
                direction: :inbound)
            end

            # Verifies the security_policy_bot_via_job_token condition grants this permission
            it { expect_allowed(:build_read_container_image) }

            it 'does not grant other permissions' do
              expect_disallowed(:create_pipeline)
              expect_disallowed(:build_download_code)
              expect_disallowed(:read_build)
            end
          end

          context 'when registry project is NOT in the job token allowlist' do
            it { expect_disallowed(:build_read_container_image) }
          end

          context 'when registry project has inbound job token scope disabled' do
            let(:instance_level_token_scope_enabled) { false }
            let(:token_scope_enabled) { false }

            before do
              create(:ci_job_token_project_scope_link,
                source_project: registry_project,
                target_project: bot_home_project,
                direction: :inbound)
            end

            it { expect_disallowed(:build_read_container_image) }
          end

          context 'when registry project is public' do
            # Override with public project - cannot use let_it_be here as it overrides parent
            let(:registry_project) { create(:project, :public) }

            # Public projects already allow build_read_container_image via public_authenticated role
            it { expect_allowed(:build_read_container_image) }
          end
        end

        context 'when regular user accesses cross-project registry via job token' do
          # Verifies that the security_policy_bot_via_job_token condition does NOT
          # grant permissions to regular users, only to security policy bots.
          let_it_be(:regular_user) { create(:user) }
          let(:current_user) { regular_user }
          let_it_be_with_reload(:bot_home_project) { create(:project, :private) }
          let_it_be_with_reload(:registry_project) { create(:project, :private) }

          let(:project) { registry_project }
          let(:scope_project) { bot_home_project }
          let(:job) { build_stubbed(:ci_build, project: bot_home_project, user: current_user) }
          let(:bot_member_of_project) { false }
          let(:instance_level_token_scope_enabled) { true }
          let(:token_scope_enabled) { true }

          before do
            bot_home_project.add_guest(regular_user)
            create(:ci_job_token_project_scope_link,
              source_project: registry_project,
              target_project: bot_home_project,
              direction: :inbound)
          end

          it { expect_disallowed(:build_read_container_image) }
        end
      end

      context 'when security policy bot is on the project' do
        before do
          project.add_guest(security_policy_bot)
        end

        context 'when user is not authenticated via CI_JOB_TOKEN' do
          context 'when on_demand_scans are enabled' do
            before do
              stub_licensed_features(security_on_demand_scans: true)
            end

            it { expect_allowed(:read_on_demand_dast_scan, :create_on_demand_dast_scan) }
          end

          describe 'read_build permission' do
            context 'when public_builds is enabled' do
              it { expect_allowed(:read_build) }
            end

            context 'when public_builds is disabled' do
              before do
                project.update!(public_builds: false)
              end

              it { expect_allowed(:read_build) }
            end
          end

          describe 'read_package permission' do
            context 'when packages are enabled' do
              it { expect_allowed(:read_package) }
            end

            context 'when packages are disabled' do
              before do
                project.project_feature.update!(package_registry_access_level: ProjectFeature::DISABLED)
              end

              it { expect_disallowed(:read_package) }
            end
          end
        end

        context 'when security_dashboard is not enabled' do
          it { expect_disallowed(:create_vulnerability_state_transition) }
        end

        context 'when security_dashboard is enabled' do
          before do
            stub_licensed_features(security_dashboard: true)
          end

          it { expect_allowed(:create_vulnerability_state_transition) }
        end

        context 'when on_demand_scans are disabled' do
          before do
            stub_licensed_features(security_on_demand_scans: false)
          end

          it { expect_disallowed(:read_on_demand_dast_scan, :create_on_demand_dast_scan) }
        end

        context 'when on_demand_scans are enabled' do
          before do
            stub_licensed_features(security_on_demand_scans: true)
          end

          it { expect_allowed(:read_on_demand_dast_scan, :create_on_demand_dast_scan) }
        end

        describe 'least privilege enforcement' do
          let(:guest_only_permissions) do
            %i[
              create_issue
              create_note
              read_issue
              read_wiki
              upload_file
            ]
          end

          it 'prevents guest permissions not explicitly granted in YAML role' do
            expect_disallowed(*guest_only_permissions)
          end

          context 'when all required features are licensed' do
            before do
              stub_licensed_features(
                security_on_demand_scans: true,
                security_dashboard: true
              )
            end

            it 'allows permissions defined in security_policy_bot YAML role' do
              yaml_permissions = ::Authz::Role.get(:security_policy_bot).direct_permissions(:project)

              expect_allowed(*yaml_permissions)
            end
          end
        end
      end
    end

    describe 'generate_description' do
      let(:authorizer) { instance_double(::Gitlab::Llm::FeatureAuthorizer) }
      let(:current_user) { guest }
      let(:project) { private_project }

      before do
        allow(::Gitlab::Llm::FeatureAuthorizer).to receive(:new).and_return(authorizer)
      end

      context "when feature is authorized" do
        before do
          allow(authorizer).to receive(:allowed?).and_return(true)
        end

        context 'when user can create issue' do
          it { expect_allowed(:generate_description) }
        end

        context 'when user cannot create issue' do
          let(:current_user) { non_member }

          it { expect_disallowed(:generate_description) }
        end
      end

      context "when feature is not authorized" do
        before do
          allow(authorizer).to receive(:allowed?).and_return(false)
        end

        it { expect_disallowed(:generate_description) }
      end
    end

    describe 'access_summarize_new_merge_request' do
      let(:authorizer) { instance_double(::Gitlab::Llm::FeatureAuthorizer) }
      let(:current_user) { user_can_create_mr ? developer : nil }

      where(:feature_flag_enabled, :llm_authorized, :user_can_create_mr, :expected_result) do
        true  | true  | true  | be_allowed(:access_summarize_new_merge_request)
        true  | true  | false | be_disallowed(:access_summarize_new_merge_request)
        true  | false | true  | be_disallowed(:access_summarize_new_merge_request)
        false | true  | true  | be_disallowed(:access_summarize_new_merge_request)
      end

      with_them do
        before do
          # Setup feature flag
          stub_feature_flags(add_ai_summary_for_new_mr: feature_flag_enabled)

          # Setup LLM authorizer
          allow(::Gitlab::Llm::FeatureAuthorizer).to receive(:new).and_return(authorizer)
          allow(authorizer).to receive(:allowed?).and_return(llm_authorized)
        end

        it { is_expected.to expected_result }
      end
    end

    describe 'summarize_comments' do
      subject { described_class.new(current_user, project) }

      context 'when user is nil' do
        let(:current_user) { nil }

        it { expect_disallowed(:summarize_comments) }
      end

      context 'when user is present' do
        let(:current_user) { reporter }

        using RSpec::Parameterized::TableSyntax

        where(:authorizer_allowed, :expected) do
          true  | true
          false | false
        end

        with_them do
          let(:authorizer) { instance_double(::Gitlab::Llm::FeatureAuthorizer) }

          before do
            allow(::Gitlab::Llm::FeatureAuthorizer).to receive(:new).and_return(authorizer)
            allow(authorizer).to receive(:allowed?).and_return(authorizer_allowed)
          end

          it { is_expected.to public_send("be_#{expected ? 'allowed' : 'disallowed'}", :summarize_comments) }
        end

        context 'when verifying FeatureAuthorizer parameters' do
          let(:authorizer) { instance_double(::Gitlab::Llm::FeatureAuthorizer) }

          before do
            allow(::Gitlab::Llm::FeatureAuthorizer).to receive(:new).and_return(authorizer)
            allow(authorizer).to receive(:allowed?).and_return(true)
          end

          it 'creates FeatureAuthorizer with correct parameters' do
            expect(::Gitlab::Llm::FeatureAuthorizer).to receive(:new).with(
              container: project,
              feature_name: :summarize_comments,
              user: current_user
            ).and_return(authorizer)

            subject.allowed?(:summarize_comments)
          end
        end
      end
    end

    describe 'admin_target_branch_rule policy' do
      let(:current_user) { owner }

      describe 'when the project does not have the correct license' do
        before do
          stub_licensed_features(target_branch_rules: false)
        end

        it { expect_disallowed(:admin_target_branch_rule) }
      end
    end

    describe 'read_target_branch_rule policy' do
      let(:current_user) { owner }

      describe 'when the user has permission' do
        before do
          stub_licensed_features(target_branch_rules: true)
        end

        it { expect_allowed(:read_target_branch_rule) }
      end
    end

    describe 'read_observability policy' do
      let(:current_user) { reporter }

      before do
        stub_licensed_features(observability: true)
      end

      describe 'when observability_features is disabled' do
        before do
          stub_feature_flags(observability_features: false)
        end

        it { expect_disallowed(:read_observability) }
      end

      describe 'when observability feature flag is enabled for root namespace' do
        before do
          stub_feature_flags(observability_features: project.root_namespace)
        end

        it { expect_allowed(:read_observability) }
      end

      describe 'when the project does not have the correct license' do
        before do
          stub_feature_flags(observability_features: true)
          stub_licensed_features(observability: false)
        end

        it { expect_disallowed(:read_observability) }
      end
    end

    describe 'write_observability policy' do
      let(:current_user) { developer }

      before do
        stub_licensed_features(observability: true)
      end

      describe 'when observability_features feature flag is disabled' do
        before do
          stub_feature_flags(observability_features: false)
        end

        it { expect_disallowed(:write_observability) }
      end

      describe 'when observability feature flag is enabled for root namespace' do
        before do
          stub_feature_flags(observability_features: project.root_namespace)
        end

        it { expect_allowed(:write_observability) }
      end

      describe 'when the project does not have the correct license' do
        before do
          stub_feature_flags(observability_features: true)
          stub_licensed_features(observability: false)
        end

        it { expect_disallowed(:write_observability) }
      end
    end

    describe "#view_edit_page granted via the SAST Vulnerability Resolution setting permission" do
      context "with security manager" do
        let(:current_user) { security_manager }

        it "can open the project settings page without admin_project" do
          expect_disallowed(:admin_project)
          expect_allowed(:update_sec_ai_workflow_settings, :view_edit_page)
        end

        context "when all sec AI workflow feature flags are disabled" do
          before do
            stub_feature_flags(
              update_sast_vr_setting_permission: false,
              update_false_positive_detection_setting_permission: false
            )
          end

          it { expect_disallowed(:update_sec_ai_workflow_settings, :view_edit_page) }
        end
      end
    end

    context 'when project is scheduled for deletion' do
      let_it_be_with_reload(:project) do
        create(:project, :small_repo, :in_group, owners: owner, marked_for_deletion_at: Time.current)
      end

      subject { described_class.new(owner, project) }

      before do
        stub_licensed_features(
          security_dashboard: true,
          iterations: true,
          quality_management: true,
          license_scanning: true
        )
      end

      it 'disallows write operations' do
        expect_disallowed(
          :admin_ai_catalog_item,
          :admin_feature_flag,
          :admin_feature_flags_client,
          :admin_issue_board,
          :admin_issue_link,
          :admin_iteration,
          :admin_software_license_policy,
          :admin_vulnerability,
          :confirm_vulnerability,
          :create_feature_flag,
          :create_feature_flags_client,
          :create_issue_board,
          :create_issue_link,
          :create_iteration,
          :create_test_case,
          :create_vulnerability,
          :create_vulnerability_feedback,
          :destroy_feature_flag,
          :destroy_feature_flags_client,
          :destroy_issue_board,
          :destroy_issue_link,
          :destroy_iteration,
          :destroy_vulnerability,
          :destroy_vulnerability_feedback,
          :dismiss_vulnerability,
          :resolve_vulnerability,
          :revert_vulnerability,
          :update_approvers,
          :update_feature_flag,
          :update_feature_flags_client,
          :update_issue_board,
          :update_issue_link,
          :update_iteration,
          :update_vulnerability,
          :update_vulnerability_feedback,
          :update_vulnerability_severity
        )
      end

      it 'allows read operations' do
        expect_allowed(:read_vulnerability, :read_vulnerability_feedback, :read_vulnerability_scanner, :read_iteration)
      end
    end

    describe 'access_code_suggestions', :saas do
      let_it_be_with_refind(:current_user) { create(:user) }
      let_it_be_with_reload(:group) { create(:group_with_plan, plan: :premium_plan) }
      # Public, so the anonymous `prevent_all` rule does not hide the
      # `next false unless @user` check in the "user is nil" example.
      let_it_be_with_reload(:project) { create(:project, :public, group: group) }

      let(:user) { current_user }

      subject(:policy) { described_class.new(user, project) }

      # A real Duo seat instead of stubbing allowed_to_use?, so the enable rule is
      # exercised for real. 'with duo pro addon' gives current_user a seat in group.
      include_context 'with duo pro addon'

      before do
        stub_licensed_features(code_suggestions: true)
        project.project_setting.update!(duo_features_enabled: true)
      end

      it { expect_allowed(:access_code_suggestions) }

      context 'when the user is nil' do
        let(:user) { nil }

        it { expect_disallowed(:access_code_suggestions) }
      end

      context 'when the user has no Duo seat' do
        let_it_be(:user_without_seat) { create(:user) }

        let(:user) { user_without_seat }

        it { expect_disallowed(:access_code_suggestions) }
      end

      context 'when the user cannot read the project' do
        let_it_be_with_reload(:project) { create(:project, :private, group: group) }

        it { expect_disallowed(:access_code_suggestions) }
      end

      context 'when GitLab Duo is set to "Always off" for the instance' do
        before do
          # Stub the check directly. Setting the real instance values would also
          # cascade duo_features_enabled to the project and hide this rule.
          allow(Gitlab::CurrentSettings).to receive(:duo_never_on?).and_return(true)
        end

        it { expect_disallowed(:access_code_suggestions) }
      end

      context 'when the project has GitLab Duo turned off' do
        before do
          project.project_setting.update!(duo_features_enabled: false)
        end

        it { expect_disallowed(:access_code_suggestions) }
      end

      # On GitLab.com the license check is always true, so this rule can only be
      # tested on self-managed. Without a license, allowed_to_use? is also false
      # and would hide this rule, so we stub it to true to test the license alone.
      context 'when on self-managed without a Code Suggestions license' do
        before do
          stub_saas_features(gitlab_com_subscriptions: false)
          allow(::GitlabSubscriptions::Duo).to receive(:active_self_managed_gitlab_credits?).and_return(false)
          stub_licensed_features(code_suggestions: false)
          allow(current_user).to receive(:allowed_to_use?)
            .with(:code_suggestions, root_namespace: project.root_ancestor).and_return(true)
        end

        it { expect_disallowed(:access_code_suggestions) }
      end

      context 'when the group is "Off by default" but the project opts back in' do
        before do
          group.namespace_settings.update!(duo_availability: 'default_off')
          project.project_setting.update!(duo_features_enabled: true)
        end

        it 'is allowed, because the setting is not locked' do
          expect_allowed(:access_code_suggestions)
        end
      end

      context 'when the group is "Always off" and the project tries to opt back in' do
        before do
          group.namespace_settings.update!(duo_availability: 'never_on')
          project.project_setting.update!(duo_features_enabled: true)
        end

        it 'is disallowed, because the locked ancestor wins' do
          expect_disallowed(:access_code_suggestions)
        end
      end

      it 'checks the seat against the root namespace of the project' do
        expect(current_user).to receive(:allowed_to_use?)
          .with(:code_suggestions, root_namespace: project.root_ancestor).and_call_original

        expect_allowed(:access_code_suggestions)
      end

      # The seat stays in `group`. The project lives in another top-level group,
      # so that group's Duo access rules decide, not the rules of the seat group.
      context 'when the seat is in a different group than the project' do
        let_it_be(:subject_group) { create(:group, :public) }
        let_it_be_with_reload(:project) { create(:project, :public, group: subject_group) }

        it { expect_allowed(:access_code_suggestions) }

        context 'when the project group restricts GitLab Duo by group membership' do
          let_it_be(:allowed_subgroup) { create(:group, parent: subject_group) }

          before_all do
            create(:ai_namespace_feature_access_rules, :duo_classic,
              root_namespace: subject_group, through_namespace: allowed_subgroup)
          end

          context 'when the user is not a member of the project group' do
            it 'is allowed, because the rules only apply to members' do
              expect_allowed(:access_code_suggestions)
            end
          end

          context 'when the user is a member of the project group but not of the allowed subgroup' do
            before_all do
              subject_group.add_guest(current_user)
            end

            it { expect_disallowed(:access_code_suggestions) }
          end

          context 'when the user is a member of the allowed subgroup' do
            before_all do
              allowed_subgroup.add_guest(current_user)
            end

            it { expect_allowed(:access_code_suggestions) }
          end
        end
      end
    end

    describe 'access_duo_classic_chat' do
      let_it_be(:current_user) { create(:user) }
      let(:project) { create(:project, :public, group: group) }

      subject { described_class.new(current_user, project) }

      context 'when on SaaS instance', :saas do
        let_it_be_with_reload(:group) { create(:group_with_plan, plan: :premium_plan) }

        context 'when container is a group with AI enabled' do
          include_context 'with duo features enabled and ai chat available for group on SaaS'

          context 'when user is nil' do
            subject { described_class.new(nil, project) }

            it { expect_disallowed(:access_duo_classic_chat) }
          end

          context 'when user is a member of the group' do
            before do
              group.add_guest(current_user)
            end

            it { expect_allowed(:access_duo_classic_chat) }

            context 'when the group does not have an Premium SaaS license' do
              let_it_be(:group) { create(:group) }

              it { expect_disallowed(:access_duo_classic_chat) }
            end
          end

          context 'when user is not a member of the parent group' do
            context 'when the user has AI enabled via another group' do
              context 'user can view project' do
                it 'is allowed' do
                  expect_allowed(:access_duo_classic_chat)
                end
              end

              context 'user cannot view project' do
                before do
                  project.update!(visibility_level: Gitlab::VisibilityLevel::PRIVATE)
                end

                it 'is not allowed' do
                  expect_disallowed(:access_duo_classic_chat)
                end
              end
            end
          end

          context 'when user is a member of the project' do
            before do
              project.add_guest(current_user)
            end

            context 'when the user has AI enabled through parent group' do
              it 'is allowed' do
                expect_allowed(:access_duo_classic_chat)
              end
            end
          end
        end
      end

      context 'for self-managed', :with_cloud_connector do
        let_it_be_with_reload(:group) { create(:group) }
        let(:policy) { :access_duo_classic_chat }

        before do
          project.add_guest(current_user)
        end

        context 'when not on .org or .com' do
          where(:enabled_for_user, :duo_features_enabled, :duo_features_banned, :duo_chat_matcher) do
            true  | true  | false | be_allowed(policy)
            true  | false | false | be_disallowed(policy)
            false | false | false | be_disallowed(policy)
            false | true  | false | be_disallowed(policy)
            true  | true  | true  | be_disallowed(policy)
          end

          with_them do
            before do
              allow(::Gitlab).to receive(:org_or_com?).and_return(false)
              allow(::Gitlab::CurrentSettings).to receive(:duo_never_on?).and_return(duo_features_banned)
              stub_ee_application_setting(duo_features_enabled: duo_features_enabled, lock_duo_features_enabled: true)
              allow(current_user).to receive(:allowed_to_use?).and_return(enabled_for_user)
            end

            it { is_expected.to duo_chat_matcher }
          end
        end
      end
    end

    context 'access_duo_features' do
      let(:project) { private_project }

      where(:current_user, :duo_features_enabled, :cs_matcher) do
        ref(:guest) | true | be_allowed(:access_duo_features)
        ref(:guest) | false | be_disallowed(:access_duo_features)
        nil | true | be_disallowed(:access_duo_features)
        nil | false | be_disallowed(:access_duo_features)
      end

      with_them do
        before do
          project.update!(duo_features_enabled: duo_features_enabled)
        end

        it do
          is_expected.to cs_matcher
        end
      end
    end

    describe 'access to project for duo workflow' do
      let_it_be_with_reload(:project) { public_project }

      where(:current_user, :token_info, :duo_features_enabled, :cs_matcher) do
        ref(:guest)      | { token_scopes: [:ai_workflows] } | true  | be_allowed(:read_project)
        ref(:guest)      | { token_scopes: [:ai_workflows] } | false | be_disallowed(:read_project, :admin_project)
        ref(:guest)      | { token_scopes: [:other_scope] }  | true  | be_allowed(:read_project)
        ref(:maintainer) | { token_scopes: [:ai_workflows] } | false | be_disallowed(:read_project, :admin_project)
      end

      with_them do
        before do
          project.update!(duo_features_enabled: duo_features_enabled)
          ::Current.token_info = token_info
        end

        it { is_expected.to cs_matcher }
      end
    end

    describe 'permissions for security_on_demand_scans feature' do
      it_behaves_like 'prevents permissions when the licensed feature is disabled',
        licensed_feature: :security_on_demand_scans,
        permissions: %i[read_on_demand_dast_scan create_on_demand_dast_scan edit_on_demand_dast_scan],
        roles: %w[developer owner]
    end

    describe 'read_runner_cloud_provisioning_info policy' do
      let(:current_user) { maintainer }

      it { expect_disallowed(:read_runner_cloud_provisioning_info) }
    end

    describe 'read_runner_gke_provisioning_info policy' do
      let(:current_user) { maintainer }

      it { expect_disallowed(:read_runner_gke_provisioning_info) }
    end

    describe 'provision_cloud_runner policy' do
      let(:current_user) { maintainer }

      it { expect_disallowed(:provision_cloud_runner) }
    end

    describe 'provision_gke_runner policy' do
      let(:current_user) { maintainer }

      it { expect_disallowed(:provision_gke_runner) }
    end

    describe 'read_google_cloud_artifact_registry' do
      where(:saas_feature_enabled, :current_user, :match_expected_result) do
        false | ref(:owner)      | be_disallowed(:read_google_cloud_artifact_registry)
        false | ref(:reporter)   | be_disallowed(:read_google_cloud_artifact_registry)
      end

      with_them do
        before do
          stub_saas_features(google_cloud_support: saas_feature_enabled)
        end

        it { is_expected.to match_expected_result }
      end
    end

    describe 'admin_google_cloud_artifact_registry' do
      where(:saas_feature_enabled, :current_user, :match_expected_result) do
        false | ref(:owner)      | be_disallowed(:admin_google_cloud_artifact_registry)
        false | ref(:maintainer) | be_disallowed(:admin_google_cloud_artifact_registry)
      end

      with_them do
        before do
          stub_saas_features(google_cloud_support: saas_feature_enabled)
        end

        it { is_expected.to match_expected_result }
      end
    end

    context 'saved replies permissions' do
      let(:current_user) { owner }

      context 'when no license is present' do
        before do
          stub_licensed_features(project_saved_replies: false)
        end

        it do
          expect_disallowed(:read_saved_replies, :create_saved_replies, :update_saved_replies, :destroy_saved_replies)
        end
      end
    end

    describe 'secret push protection' do
      it_behaves_like 'prevents permissions when the licensed feature is disabled',
        licensed_feature: :secret_push_protection,
        permissions: %i[enable_secret_push_protection read_secret_push_protection_info],
        roles: %w[developer security_manager owner]
    end

    describe 'secret_detection_validity_checks' do
      using RSpec::Parameterized::TableSyntax

      describe 'update_secret_detection_validity_check' do
        where(:current_user, :licensed, :match_expected_result) do
          ref(:owner)            | true  | be_allowed(:update_secret_detection_validity_check)
          ref(:maintainer)       | true  | be_allowed(:update_secret_detection_validity_check)
          ref(:security_manager) | true  | be_allowed(:update_secret_detection_validity_check)
          ref(:developer)        | true  | be_disallowed(:update_secret_detection_validity_check)
          ref(:owner)            | false | be_disallowed(:update_secret_detection_validity_check)
          ref(:maintainer)       | false | be_disallowed(:update_secret_detection_validity_check)
          ref(:developer)        | false | be_disallowed(:update_secret_detection_validity_check)
          ref(:security_manager) | false | be_disallowed(:update_secret_detection_validity_check)
        end

        with_them do
          before do
            stub_licensed_features(secret_detection_validity_checks: licensed)
          end

          it { is_expected.to match_expected_result }
        end
      end

      describe 'update_secret_detection_validity_check_status' do
        where(:current_user, :licensed, :match_expected_result) do
          ref(:owner)            | true  | be_allowed(:update_secret_detection_validity_check_status)
          ref(:maintainer)       | true  | be_allowed(:update_secret_detection_validity_check_status)
          ref(:security_manager) | true  | be_allowed(:update_secret_detection_validity_check_status)
          ref(:developer)        | true  | be_allowed(:update_secret_detection_validity_check_status)
          ref(:reporter)         | true  | be_disallowed(:update_secret_detection_validity_check_status)
          ref(:owner)            | false | be_disallowed(:update_secret_detection_validity_check_status)
          ref(:maintainer)       | false | be_disallowed(:update_secret_detection_validity_check_status)
          ref(:developer)        | false | be_disallowed(:update_secret_detection_validity_check_status)
          ref(:security_manager) | false | be_disallowed(:update_secret_detection_validity_check_status)
          ref(:reporter)         | false | be_disallowed(:update_secret_detection_validity_check_status)
        end

        with_them do
          before do
            stub_licensed_features(secret_detection_validity_checks: licensed)
          end

          it { is_expected.to match_expected_result }
        end
      end

      describe 'when the project does not have the correct license' do
        let(:current_user) { owner }

        it do
          expect_disallowed(:update_secret_detection_validity_check, :update_secret_detection_validity_check_status)
        end
      end
    end

    describe 'duo_workflow' do
      let(:project) { public_project_in_group }

      where(:stage_check_available, :duo_features_enabled, :current_user, :match_expected_result) do
        true  | true  | ref(:owner)      | be_allowed(:duo_workflow)
        true  | true  | ref(:maintainer) | be_allowed(:duo_workflow)
        true  | true  | ref(:developer)  | be_allowed(:duo_workflow)
        true  | true  | ref(:planner)    | be_disallowed(:duo_workflow)
        true  | true  | ref(:guest)      | be_disallowed(:duo_workflow)
        true  | true  | ref(:non_member) | be_disallowed(:duo_workflow)
        false | true  | ref(:owner)      | be_disallowed(:duo_workflow)
        false | true  | ref(:developer)  | be_disallowed(:duo_workflow)
      end

      with_them do
        before do
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project,
            :duo_workflow).and_return(stage_check_available)
          stub_ee_application_setting(duo_features_enabled: duo_features_enabled)
          allow(current_user).to receive(:allowed_to_use?)
            .with(:duo_agent_platform, root_namespace: project.root_ancestor)
            .and_return(false)
        end

        context 'when user is not allowed to use duo_agent_platform' do
          it { expect_disallowed(:duo_workflow) }
        end

        context 'when user is allowed to use duo_agent_platform' do
          before do
            allow(current_user).to receive(:allowed_to_use?)
              .with(:duo_agent_platform, root_namespace: project.root_ancestor)
              .and_return(true)
          end

          it { is_expected.to match_expected_result }
        end
      end

      context 'when duo_workflow conditions are met but user not allowed to use duo_agent_platform' do
        let(:current_user) { developer }

        before do
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
          stub_ee_application_setting(duo_features_enabled: true)
          allow(current_user).to receive(:allowed_to_use?)
            .with(:duo_agent_platform, root_namespace: project.root_ancestor)
            .and_return(false)
        end

        it { expect_disallowed(:duo_workflow) }
      end

      context 'when user is nil' do
        let(:current_user) { nil }

        before do
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
          stub_ee_application_setting(duo_features_enabled: true)
        end

        it { expect_disallowed(:duo_workflow) }
      end

      describe 'autonomous_service_account condition' do
        it 'is false for an actor that is not a user' do
          expect(described_class.new(nil, project).autonomous_service_account?).to be(false)
          expect(described_class.new(create(:deploy_token), project).autonomous_service_account?).to be(false)
        end
      end

      context 'when user is a composite identity service account', :request_store do
        let_it_be(:scoped_user) { create(:user) }
        let_it_be(:service_account) { create(:user, :service_account, composite_identity_enforced: true) }

        before do
          project.add_developer(service_account)
          project.add_developer(scoped_user)
          allow(project).to receive(:duo_features_enabled).and_return(true)
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
          allow(scoped_user).to receive(:allowed_to_use)
            .and_return(Ai::UserAuthorizable::Response.new(allowed?: true, namespace_ids: [],
              authorized_by_duo_core: false))

          ::Gitlab::Auth::Identity.new(service_account).link!(scoped_user)
        end

        it 'evaluates duo_workflow permission against the scoped human user' do
          policy = described_class.new(service_account, project)

          expect(policy.allowed?(:duo_workflow)).to be(true)
        end

        context 'when the scoped user does not have permission' do
          before do
            allow(scoped_user).to receive(:allowed_to_use)
              .and_return(Ai::UserAuthorizable::Response.new(allowed?: false, namespace_ids: [],
                authorized_by_duo_core: false))
          end

          it 'denies duo_workflow' do
            policy = described_class.new(service_account, project)

            expect(policy.allowed?(:duo_workflow)).to be(false)
          end
        end
      end

      context 'when two users share a policy cache on the same project' do
        let_it_be(:non_authorized_developer) { create(:user) }

        before do
          project.add_developer(non_authorized_developer)
          allow(project).to receive(:duo_features_enabled).and_return(true)
          allow(Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).with(project).and_return(true)
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
          allow(developer).to receive(:allowed_to_use?).with(:duo_agent_platform,
            root_namespace: project.root_ancestor).and_return(true)
          allow(non_authorized_developer).to receive(:allowed_to_use?).with(:duo_agent_platform,
            root_namespace: project.root_ancestor).and_return(false)
        end

        it 'does not use cached policy for non-authorized user', :aggregate_failures do
          shared_cache = {}
          authorized_policy = described_class.new(developer, project, cache: shared_cache)
          unauthorized_policy = described_class.new(non_authorized_developer, project, cache: shared_cache)

          expect(authorized_policy.allowed?(:duo_workflow)).to be(true)
          expect(unauthorized_policy.allowed?(:duo_workflow)).to be(false)
        end
      end
    end

    describe 'create_duo_workflow_for_ci' do
      let(:project) { public_project_in_group }

      where(:stage_check_available, :duo_features_enabled, :current_user, :match_expected_result) do
        true  | true  | ref(:owner)      | be_allowed(:create_duo_workflow_for_ci)
        true  | true  | ref(:maintainer) | be_allowed(:create_duo_workflow_for_ci)
        true  | true  | ref(:developer)  | be_allowed(:create_duo_workflow_for_ci)
        true  | true  | ref(:planner)    | be_disallowed(:create_duo_workflow_for_ci)
        true  | true  | ref(:guest)      | be_disallowed(:create_duo_workflow_for_ci)
        true  | true  | ref(:non_member) | be_disallowed(:create_duo_workflow_for_ci)
        false | true  | ref(:owner)      | be_disallowed(:create_duo_workflow_for_ci)
        false | true  | ref(:developer)  | be_disallowed(:create_duo_workflow_for_ci)
      end

      with_them do
        before do
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project,
            :duo_workflow).and_return(stage_check_available)
          stub_ee_application_setting(duo_features_enabled: duo_features_enabled)
          allow(current_user).to receive(:allowed_to_use?).and_return(false)
        end

        context 'when user is not allowed to use duo_agent_platform' do
          it { expect_disallowed(:create_duo_workflow_for_ci) }
        end

        context 'when user is allowed to use duo_agent_platform' do
          before do
            allow(current_user).to receive(:allowed_to_use?).and_return(true)
          end

          it { is_expected.to match_expected_result }
        end
      end

      context 'with customizable permissions' do
        before do
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
          stub_ee_application_setting(duo_features_enabled: true)
          allow(current_user).to receive(:allowed_to_use?).and_return(true)
        end

        context 'when the minimum role has been set in a saas environment', :saas do
          before do
            project.root_ancestor.create_ai_settings(minimum_access_level_execute_async: ::Gitlab::Access::MAINTAINER)
          end

          context 'when the role requirement is not met' do
            let(:current_user) { developer }

            it { expect_disallowed(:create_duo_workflow_for_ci) }
          end

          context 'when the role requirement is met' do
            let(:current_user) { maintainer }

            it { expect_allowed(:create_duo_workflow_for_ci) }
          end
        end

        context 'when the minimum role has been set in a self-managed environment' do
          before do
            Ai::Setting.for_organization(project.organization).update!(minimum_access_level_execute_async: ::Gitlab::Access::MAINTAINER)
          end

          context 'when the role requirement is not met' do
            let(:current_user) { developer }

            it { expect_disallowed(:create_duo_workflow_for_ci) }
          end

          context 'when the role requirement is met' do
            let(:current_user) { maintainer }

            it { expect_allowed(:create_duo_workflow_for_ci) }
          end
        end
      end
    end

    # :create_duo_workflow_for_ci is :duo_workflow plus the minimum role for asynchronous
    # execution. The setting must not reach a run the caller performs itself, which
    # Ai::DuoWorkflows::CreateWorkflowService relies on to pick the matching check.
    describe 'duo_workflow when the asynchronous minimum role excludes the user' do
      let(:project) { public_project_in_group }
      let(:current_user) { developer }

      before do
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
        stub_ee_application_setting(duo_features_enabled: true)
        allow(current_user).to receive(:allowed_to_use?).and_return(true)
      end

      context 'in a saas environment', :saas do
        before do
          project.root_ancestor.create_ai_settings(minimum_access_level_execute_async: ::Gitlab::Access::MAINTAINER)
        end

        it { expect_allowed(:duo_workflow) }
      end

      context 'in a self-managed environment' do
        before do
          Ai::Setting.for_organization(project.organization).update!(minimum_access_level_execute_async: ::Gitlab::Access::MAINTAINER)
        end

        it { expect_allowed(:duo_workflow) }
      end
    end

    describe 'create_duo_otel_workflow' do
      let_it_be_with_reload(:project) do
        create(:project, :small_repo, :public, namespace: group,
          owners: owner, maintainers: maintainer, developers: developer, planners: planner, guests: guest)
      end

      before_all do
        project.project_setting.update!(
          duo_features_enabled: true,
          duo_remote_flows_enabled: true,
          duo_foundational_flows_enabled: true
        )
        create(:repository_language, project: project)
      end

      before do
        stub_licensed_features(ai_features: true)
      end

      context 'when all conditions are met' do
        where(:current_user, :match_expected_result) do
          ref(:owner)      | be_allowed(:create_duo_otel_workflow)
          ref(:maintainer) | be_allowed(:create_duo_otel_workflow)
          ref(:developer)  | be_allowed(:create_duo_otel_workflow)
          ref(:planner)    | be_disallowed(:create_duo_otel_workflow)
          ref(:guest)      | be_disallowed(:create_duo_otel_workflow)
          ref(:non_member) | be_disallowed(:create_duo_otel_workflow)
        end

        with_them do
          it { is_expected.to match_expected_result }
        end
      end

      context 'when feature flag is disabled' do
        let(:current_user) { developer }

        before do
          stub_feature_flags(duo_add_otel: false)
        end

        it { expect_disallowed(:create_duo_otel_workflow) }
      end

      context 'when project has empty repo' do
        let(:current_user) { developer }
        let(:project) { create(:project, :public, namespace: group) }

        it { expect_disallowed(:create_duo_otel_workflow) }
      end

      context 'when project has no repository languages' do
        let(:current_user) { developer }

        before do
          RepositoryLanguage.where(project_id: project.id).delete_all
        end

        it { expect_disallowed(:create_duo_otel_workflow) }
      end

      context 'when duo features are disabled' do
        let(:current_user) { developer }

        before do
          project.project_setting.update!(duo_features_enabled: false)
        end

        it { expect_disallowed(:create_duo_otel_workflow) }
      end

      context 'when duo remote flows are disabled' do
        let(:current_user) { developer }

        before do
          project.project_setting.update!(duo_remote_flows_enabled: false)
        end

        it { expect_disallowed(:create_duo_otel_workflow) }
      end

      context 'when licensed AI features are not available' do
        let(:current_user) { developer }

        before do
          stub_licensed_features(ai_features: false)
        end

        it { expect_disallowed(:create_duo_otel_workflow) }
      end

      context 'when duo foundational flows are disabled' do
        let(:current_user) { developer }

        before do
          project.project_setting.update!(duo_foundational_flows_enabled: false)
        end

        it { expect_disallowed(:create_duo_otel_workflow) }
      end
    end

    describe 'access_ai_review_mr permission' do
      let(:current_user) { developer }

      before do
        stub_licensed_features(ai_features: true)
        stub_ee_application_setting(duo_features_enabled: true)
      end

      it 'calls allowed_to_use? with correct root_namespace parameter' do
        expect(current_user).to receive(:allowed_to_use?).with(
          :review_merge_request,
          licensed_feature: :review_merge_request,
          root_namespace: project.root_ancestor
        ).and_return(true)

        expect_allowed(:access_ai_review_mr)
      end

      context 'when user is not allowed' do
        before do
          allow(current_user).to receive(:allowed_to_use?)
            .with(:review_merge_request, licensed_feature: :review_merge_request, root_namespace: project.root_ancestor)
            .and_return(false)
        end

        it { expect_disallowed(:access_ai_review_mr) }
      end

      context 'when user is nil' do
        let(:current_user) { nil }

        it { expect_disallowed(:access_ai_review_mr) }
      end
    end

    describe 'enable_container_scanning_for_registry' do
      it_behaves_like 'prevents permissions when the licensed feature is disabled',
        licensed_feature: :container_scanning_for_registry,
        permissions: [:enable_container_scanning_for_registry],
        roles: %w[security_manager owner]
    end

    describe 'update_cvs_for_container_scanning' do
      it_behaves_like 'prevents permissions when the licensed feature is disabled',
        licensed_feature: :container_scanning,
        permissions: [:update_cvs_for_container_scanning],
        roles: %w[security_manager owner]
    end

    describe 'update_cvs_for_dependency_scanning' do
      it_behaves_like 'prevents permissions when the licensed feature is disabled',
        licensed_feature: :dependency_scanning,
        permissions: [:update_cvs_for_dependency_scanning],
        roles: %w[security_manager owner]
    end

    describe 'toggle_license_scanning_for_cyclonedx' do
      it_behaves_like 'prevents permissions when the licensed feature is disabled',
        licensed_feature: :license_scanning,
        permissions: [:toggle_license_scanning_for_cyclonedx],
        roles: %w[security_manager owner]
    end

    describe 'create_dependency_firewall_evaluation' do
      let(:policy) { :create_dependency_firewall_evaluation }

      # The decoupling this permission exists for: packages_disabled hard-vetoes :read_package
      # for every role, but the firewall evaluates upstream dependencies, so turning off the
      # package registry must not turn off evaluation.
      context 'when the package registry is disabled for the project' do
        let(:current_user) { reporter }

        before do
          project.update!(packages_enabled: false)
        end

        it { expect_allowed(policy) }

        it 'is the veto scenario: read_package is prevented for the same user' do
          expect_disallowed(:read_package)
        end
      end
    end

    describe 'read_path_locks' do
      let(:current_user) { reporter }

      it { expect_allowed(:read_path_locks) }
    end

    describe 'create_security_project_tracked_ref' do
      let(:policy) { :create_security_project_tracked_ref }
      let(:current_user) { maintainer }

      before do
        stub_licensed_features(security_dashboard: true)
      end

      it { expect_allowed(policy) }
    end

    describe 'delete_security_project_tracked_ref' do
      let(:policy) { :delete_security_project_tracked_ref }
      let(:current_user) { maintainer }

      before do
        stub_licensed_features(security_dashboard: true)
      end

      it { expect_allowed(policy) }
    end

    describe 'read_ascp_component' do
      let(:policy) { :read_ascp_component }

      context 'when security_dashboard is not licensed' do
        let(:current_user) { developer }

        before do
          stub_licensed_features(security_dashboard: false)
        end

        it { expect_disallowed(policy) }
      end
    end

    describe 'create_ascp_component' do
      let(:policy) { :create_ascp_component }

      context 'when security_dashboard is not licensed' do
        let(:current_user) { maintainer }

        before do
          stub_licensed_features(security_dashboard: false)
        end

        it { expect_disallowed(policy) }
      end
    end

    describe 'read_ascp_security_context' do
      let(:policy) { :read_ascp_security_context }

      context 'when security_dashboard is not licensed' do
        let(:current_user) { developer }

        before do
          stub_licensed_features(security_dashboard: false)
        end

        it { expect_disallowed(policy) }
      end
    end

    describe 'create_ascp_security_context' do
      let(:policy) { :create_ascp_security_context }

      context 'when security_dashboard is not licensed' do
        let(:current_user) { maintainer }

        before do
          stub_licensed_features(security_dashboard: false)
        end

        it { expect_disallowed(policy) }
      end
    end

    describe 'read_ascp_scan' do
      let(:policy) { :read_ascp_scan }
      let(:project) { private_project }

      context 'when security_dashboard is not licensed' do
        let(:current_user) { developer }

        before do
          stub_licensed_features(security_dashboard: false)
        end

        it { expect_disallowed(policy) }
      end
    end

    describe 'create_ascp_scan' do
      let(:policy) { :create_ascp_scan }
      let(:project) { private_project }

      context 'when security_dashboard is not licensed' do
        let(:current_user) { maintainer }

        before do
          stub_licensed_features(security_dashboard: false)
        end

        it { expect_disallowed(policy) }
      end
    end

    describe 'access_security_scans_api' do
      context 'when on SaaS', :saas do
        context 'when feature is disabled' do
          let(:current_user) { owner }

          before do
            stub_licensed_features(security_scans_api: false)
          end

          it 'is not allowed' do
            expect_disallowed(:access_security_scans_api)
          end
        end
      end

      context 'when on Self-Managed' do
        # access_security_scans_api is only available on SaaS while in beta
        let(:current_user) { owner }

        before do
          # enable feature explicitly to show that it is still not available because of SaaS check
          stub_licensed_features(security_scans_api: true)
        end

        it 'is not allowed' do
          expect_disallowed(:access_security_scans_api)
        end
      end
    end

    describe 'access_ai_review_mr' do
      let(:current_user) { owner }

      where(:duo_features_enabled, :allowed_to_use, :enabled_for_user) do
        true  | false | be_disallowed(:access_ai_review_mr)
        false | true  | be_disallowed(:access_ai_review_mr)
        true  | true  | be_allowed(:access_ai_review_mr)
      end

      with_them do
        before do
          allow(project).to receive(:duo_features_enabled).and_return(duo_features_enabled)

          allow(current_user).to receive(:allowed_to_use?)
            .with(:review_merge_request, licensed_feature: :review_merge_request, root_namespace: project.root_ancestor)
            .and_return(allowed_to_use)
        end

        it { is_expected.to enabled_for_user }
      end
    end
  end

  describe ':read_dependency' do
    it_behaves_like 'prevents permissions when the licensed feature is disabled',
      licensed_feature: :dependency_scanning,
      permissions: [:read_dependency],
      roles: %w[reporter owner]
  end

  describe ':read_licenses, :read_software_license_policy' do
    it_behaves_like 'prevents permissions when the licensed feature is disabled',
      licensed_feature: :license_scanning,
      permissions: %i[read_licenses read_software_license_policy],
      roles: %w[reporter owner]
  end

  describe 'invite_group_members policy' do
    let(:app_setting) { :disable_invite_members }
    let(:policy) { :invite_project_members }
    let(:group) { create(:group) }

    context 'when on saas', :saas do
      before do
        allow(project).to receive(:group).and_return(group)

        stub_saas_features(group_disable_invite_members: true)
      end

      context 'with disable_invite_members is available in license' do
        where(:role, :parent_group_setting, :application_setting, :allowed) do
          :maintainer | false | true | true
          :maintainer | true | true | false
          :maintainer | true | false | false
          :owner      | false | true | true
          :owner      | true  | true | false
          :owner      | true  | false | false
          :admin      | false | true |  true
        end

        with_them do
          let(:current_user) { public_send(role) }

          before do
            stub_licensed_features(disable_invite_members: true)
            stub_application_setting(app_setting => application_setting)
            allow(project.group).to receive(:disable_invite_members?).and_return(parent_group_setting)
            enable_admin_mode!(current_user) if role == :admin
          end

          it { is_expected.to(allowed ? be_allowed(policy) : be_disallowed(policy)) }
        end
      end

      context 'with disable_invite_members not available in license' do
        where(:role, :parent_group_setting, :application_setting, :allowed) do
          :maintainer | true | true | true
          :owner      | true | true | true
          :admin      | true | false | true
        end

        with_them do
          let(:current_user) { public_send(role) }

          before do
            stub_licensed_features(disable_invite_members: false)
            stub_application_setting(app_setting => application_setting)
            allow(project.group).to receive(:disable_invite_members?).and_return(parent_group_setting)
            enable_admin_mode!(current_user) if role == :admin
          end

          it { is_expected.to(allowed ? be_allowed(policy) : be_disallowed(policy)) }
        end
      end
    end

    context 'with disable_invite_members available in license' do
      where(:role, :setting, :admin_mode, :allowed) do
        :maintainer | true  | nil    | false
        :owner      | true  | nil    | false
        :admin      | true  | false  | false
      end

      with_them do
        let(:current_user) { public_send(role) }

        before do
          stub_licensed_features(disable_invite_members: true)
          stub_application_setting(app_setting => setting)
          enable_admin_mode!(current_user) if admin_mode
        end

        it { is_expected.to(allowed ? be_allowed(policy) : be_disallowed(policy)) }
      end
    end

    context 'with disable_invite_members not available in license' do
      where(:role, :setting, :admin_mode, :allowed) do
        :maintainer | true  | nil    | true
        :owner      | true  | nil    | true
        :admin      | true  | true   | true
      end

      with_them do
        let(:current_user) { public_send(role) }

        before do
          stub_licensed_features(disable_invite_members: false)
          stub_application_setting(app_setting => setting)
          enable_admin_mode!(current_user) if admin_mode
        end

        it { is_expected.to(allowed ? be_allowed(policy) : be_disallowed(policy)) }
      end
    end
  end

  describe 'admin_project_member policy' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }

    let(:policy) { :admin_project_member }

    let(:enable_membership_lock) { true }
    let(:enable_group_link) { true }
    let(:enable_group_sync) { true }

    before do
      stub_application_setting(lock_memberships_to_saml: true) if enable_membership_lock
      create(:saml_group_link, group: group) if enable_group_link

      if enable_group_sync
        stub_licensed_features(saml_group_sync: true)
        create(:saml_provider, group: group.root_ancestor, enabled: true)
        allow(::Gitlab::Auth::GroupSaml::Config).to receive_messages(enabled?: true)
      end
    end

    shared_examples 'allows policy for all maintainers, owners and admins' do
      context 'with maintainer' do
        let(:current_user) { maintainer }

        before do
          project.add_maintainer(current_user)
        end

        it { expect_allowed(policy) }
      end

      context 'with owner' do
        let(:current_user) { owner }

        before do
          project.add_owner(current_user)
        end

        it { expect_allowed(policy) }
      end

      context 'with admin' do
        let(:current_user) { admin }

        context 'when admin mode is enabled', :enable_admin_mode do
          it { expect_allowed(policy) }
        end

        context 'when admin mode is disabled' do
          it { expect_disallowed(policy) }
        end
      end
    end

    shared_examples 'restricts policy to admins only' do
      context 'with maintainer' do
        let(:current_user) { maintainer }

        before do
          project.add_maintainer(current_user)
        end

        it { expect_disallowed(policy) }
      end

      context 'with owner' do
        let(:current_user) { owner }

        before do
          project.add_owner(current_user)
        end

        it { expect_disallowed(policy) }
      end

      context 'with admin' do
        let(:current_user) { admin }

        context 'when admin mode is enabled', :enable_admin_mode do
          it { expect_allowed(policy) }
        end

        context 'when admin mode is disabled' do
          it { expect_disallowed(policy) }
        end
      end
    end

    shared_examples 'restricts policy based on SAML configuration for all maintainers, owners and admins' do
      it_behaves_like 'restricts policy to admins only'

      context 'without membership lock' do
        let(:enable_membership_lock) { false }

        it_behaves_like 'allows policy for all maintainers, owners and admins'
      end

      context 'without group sync' do
        let(:enable_group_sync) { false }

        it_behaves_like 'allows policy for all maintainers, owners and admins'
      end

      # The lock applies even without SAML group links; their absence must not unlock member management.
      context 'without group link' do
        let(:enable_group_link) { false }

        it_behaves_like 'restricts policy to admins only'
      end
    end

    it_behaves_like 'restricts policy based on SAML configuration for all maintainers, owners and admins'

    context 'with project from subgroup' do
      let_it_be(:subgroup) { create(:group, parent: group) }
      let_it_be(:project) { create(:project, group: subgroup) }

      it_behaves_like 'restricts policy based on SAML configuration for all maintainers, owners and admins'
    end

    context 'with project from user namespace' do
      let_it_be(:user_namespace) { create(:user_namespace) }
      let_it_be(:project) { create(:project, namespace: user_namespace) }

      it_behaves_like 'allows policy for all maintainers, owners and admins'
    end
  end

  describe 'pages_multiple_versions_available' do
    let(:current_user) { maintainer }

    before do
      stub_licensed_features(pages_multiple_versions: licensed)
    end

    context 'when pages_multiple_versions feature is not available' do
      let(:licensed) { false }

      it 'denies access to pages multiple deployments' do
        expect_disallowed(:pages_multiple_versions)
      end
    end
  end

  describe 'create_epic' do
    where(role: %i[planner owner])

    with_them do
      let(:current_user) { public_send(role) }

      context 'when epics feature is available' do
        before do
          stub_licensed_features(epics: true)
        end

        context 'when project_work_item_epics feature flag is disabled' do
          before do
            stub_feature_flags(project_work_item_epics: false)
          end

          it { expect_disallowed(:create_epic) }
        end

        context 'when issues are disabled for the project' do
          before do
            project.update!(issues_enabled: false)
          end

          it { expect_disallowed(:create_epic) }
        end
      end

      context 'when epic feature is not available' do
        before do
          stub_licensed_features(epics: false)
        end

        it { expect_disallowed(:create_epic) }
      end
    end
  end

  describe 'access_duo_agentic_chat' do
    let_it_be(:current_user) { create(:user) }
    let_it_be_with_reload(:group) { create(:group) }
    let_it_be_with_reload(:project) { create(:project, group: group) }

    let(:policy) { :access_duo_agentic_chat }

    subject { described_class.new(current_user, project) }

    shared_examples 'duo agentic chat access control' do
      where(
        :stage_check_passed,
        :allowed_to_use_for_resource,
        :duo_agent_platform_enabled,
        :project_duo_features_enabled,
        :can_read_project,
        :amazon_q_enabled,
        :duo_features_banned,
        :cs_matcher
      ) do
        true  | true  | true  | true  | true  | false | false | be_allowed(policy)
        true  | true  | true  | true  | true  | false | true  | be_disallowed(policy)
        true  | false | true  | true  | true  | false | false | be_disallowed(policy)
        true  | true  | true  | false | true  | false | false | be_disallowed(policy)
        true  | true  | true  | true  | false | false | false | be_disallowed(policy)
        true  | true  | true  | true  | true  | true  | false | be_disallowed(policy)
        false | true  | true  | false | true  | false | false | be_disallowed(policy)
        false | true  | true  | true  | true  | false | false | be_disallowed(policy)
        false | false | true  | true  | true  | false | false | be_disallowed(policy)
        false | true  | true  | true  | true  | true  | false | be_disallowed(policy)
        true  | true  | false | true  | true  | true  | false | be_disallowed(policy)
      end

      with_them do
        before do
          project.update!(duo_features_enabled: project_duo_features_enabled)
          group.namespace_settings.update!(duo_features_enabled: false)
          allow(::Gitlab::CurrentSettings).to receive(:duo_never_on?).and_return(duo_features_banned)
          project.add_guest(current_user) if can_read_project
          allow(current_user).to receive(:allowed_to_use_for_resource?).with(:agentic_chat,
            unit_primitive_name: :duo_chat, resource: project)
            .and_return(allowed_to_use_for_resource)
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project,
            :agentic_chat).and_return(stage_check_passed)
          allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).and_return(duo_agent_platform_enabled)
          allow(::Ai::AmazonQ).to receive(:enabled?).and_return(amazon_q_enabled)
        end

        it { is_expected.to cs_matcher }

        context 'when current user is nil' do
          it 'is false' do
            expect(described_class.new(nil, project)).to be_disallowed(:access_duo_agentic_chat)
          end
        end
      end
    end

    context 'for SaaS', :saas do
      context 'with standard access controls' do
        include_context 'with duo pro addon'

        include_examples 'duo agentic chat access control'
      end

      context 'with customizable permissions' do
        include_context 'with duo features enabled and agentic chat available for group on SaaS'

        before do
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :agentic_chat).and_return(true)
          allow(current_user).to receive(:allowed_to_use_for_resource?)
            .with(:agentic_chat, resource: project, unit_primitive_name: :duo_chat)
            .and_return(true)

          group.ai_settings.update!(minimum_access_level_execute: ::Gitlab::Access::MAINTAINER)
        end

        context 'when user is a member' do
          where(:role, :allowed) do
            :developer  | false
            :maintainer | true
          end

          with_them do
            before do
              project.add_member(current_user, role)
            end

            it { is_expected.to(allowed ? be_allowed(policy) : be_disallowed(policy)) }
          end
        end

        context 'when user is an org owner' do
          let(:current_user) { create(:organization_owner, organization: group.organization).user }

          before do
            group.ai_settings.update!(minimum_access_level_execute: ::Gitlab::Access::GUEST)
          end

          it { expect_allowed(policy) }
        end

        context 'when minimum_access_level_execute is enabled for all users' do
          before do
            project.add_guest(current_user)
            group.ai_settings.update!(minimum_access_level_execute: nil)
          end

          it { expect_allowed(policy) }
        end

        context 'when user is not a member of the public project' do
          before do
            project.update!(visibility_level: Gitlab::VisibilityLevel::PUBLIC)
          end

          context 'when minimum_access_level_execute is enabled for all users' do
            before do
              group.ai_settings.update!(minimum_access_level_execute: nil)
            end

            it { expect_allowed(policy) }
          end

          context 'when minimum_access_level_execute requires membership' do
            before do
              group.ai_settings.update!(minimum_access_level_execute: ::Gitlab::Access::GUEST)
            end

            it { expect_disallowed(policy) }
          end
        end

        context 'when dap_group_customizable_permissions feature flag is disabled' do
          before do
            project.add_developer(current_user)
            stub_feature_flags(dap_group_customizable_permissions: false)
          end

          it { expect_allowed(policy) }
        end
      end
    end

    context 'for self-managed' do
      include_examples 'duo agentic chat access control'

      context 'with customizable permissions' do
        include_context 'with duo pro self-managed addon'

        before do
          stub_application_setting(duo_features_enabled: true)
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :agentic_chat).and_return(true)

          project.update!(visibility_level: Gitlab::VisibilityLevel::PUBLIC)
        end

        context 'when user is a member' do
          where(:role, :allowed) do
            :developer  | false
            :maintainer | true
          end

          with_them do
            before do
              project.add_member(current_user, role)
              Ai::Setting.for_organization(project.organization).update!(minimum_access_level_execute: ::Gitlab::Access::MAINTAINER)
            end

            it { is_expected.to(allowed ? be_allowed(policy) : be_disallowed(policy)) }
          end
        end

        context 'when minimum_access_level_execute is enabled for all users' do
          before do
            project.add_guest(current_user)
            Ai::Setting.for_organization(project.organization).update!(minimum_access_level_execute: nil)
          end

          it { expect_allowed(policy) }
        end

        context 'when the user is an org owner' do
          let(:current_user) { create(:organization_owner, organization: group.organization).user }

          before do
            Ai::Setting.for_organization(project.organization).update!(minimum_access_level_execute: ::Gitlab::Access::GUEST)
          end

          it { expect_allowed(policy) }
        end

        context 'when minimum access level is ADMIN' do
          before do
            Ai::Setting.for_organization(project.organization).update!(minimum_access_level_execute: ::Gitlab::Access::ADMIN)
          end

          context 'with an instance admin', :enable_admin_mode do
            let(:current_user) { admin }

            it { expect_allowed(policy) }
          end

          it 'is disabled for members' do
            project.add_owner(current_user)

            expect_disallowed(policy)
          end
        end

        context 'when the user is not a member of the public project' do
          context 'when minimum_access_level_execute is enabled for all users' do
            before do
              Ai::Setting.for_organization(project.organization).update!(minimum_access_level_execute: nil)
            end

            it { expect_allowed(policy) }
          end

          context 'when minimum_access_level_execute requires membership' do
            before do
              Ai::Setting.for_organization(project.organization).update!(minimum_access_level_execute: ::Gitlab::Access::GUEST)
            end

            it { expect_disallowed(policy) }
          end
        end

        context 'when dap_instance_customizable_permissions feature flag is disabled' do
          before do
            stub_feature_flags(dap_instance_customizable_permissions: false)
            Ai::Setting.for_organization(project.organization).update!(minimum_access_level_execute: ::Gitlab::Access::GUEST)
          end

          it { expect_allowed(policy) }
        end
      end
    end

    context 'when current user is nil and project is public' do
      let_it_be(:public_project) { create(:project, :public, group: group) }

      it 'evaluates agentic_chat_available_for_user to false' do
        policy = described_class.new(nil, public_project)
        expect(policy.agentic_chat_available_for_user?).to be(false)
      end
    end
  end

  describe 'project service accounts' do
    let(:service_account_permissions) do
      %i[
        create_service_account
        delete_service_account
        read_service_account
        admin_service_account_member
        admin_service_accounts
      ]
    end

    context 'with admin when admin mode is disabled' do
      let(:current_user) { admin }

      it { expect_disallowed(*service_account_permissions) }
    end

    context 'when trial is active', :saas do
      let_it_be(:trial_group) { create(:group_with_plan, plan: :ultimate_trial_plan) }
      let_it_be(:project_in_trial_group) { create(:project, :public, namespace: trial_group) }

      let(:project) { project_in_trial_group }

      before_all do
        project_in_trial_group.add_guest(guest)
        project_in_trial_group.add_planner(planner)
        project_in_trial_group.add_reporter(reporter)
        project_in_trial_group.add_developer(developer)
        project_in_trial_group.add_maintainer(maintainer)
        project_in_trial_group.add_owner(owner)
      end

      before do
        allow(project.group.root_ancestor).to receive(:trial_active?).and_return(true)
      end

      describe 'identity verification requirement' do
        where(:role, :identity_verified, :allowed) do
          :owner      | true  | true
          :owner      | false | false
          :maintainer | true  | true
          :maintainer | false | false
        end

        with_them do
          let(:current_user) { public_send(role) }

          before do
            allow(current_user).to receive(:identity_verified?).and_return(identity_verified)
          end

          if params[:allowed]
            it { expect_allowed(*service_account_permissions) }
          else
            specify :aggregate_failures do
              expect_disallowed(
                :admin_service_account_member,
                :admin_service_accounts,
                :create_service_account,
                :delete_service_account
              )
              expect_allowed(:read_service_account)
            end
          end
        end
      end

      context 'when user is admin with admin mode enabled', :enable_admin_mode do
        let(:current_user) { admin }

        before do
          allow(admin).to receive(:identity_verified?).and_return(false)
        end

        it { expect_allowed(*service_account_permissions) }
      end
    end

    context 'for project in personal namespace' do
      let_it_be(:project) { private_project }

      where(:role) do
        [[:owner], [:maintainer]]
      end

      with_them do
        let(:current_user) { public_send(role) }

        it { expect_allowed(*service_account_permissions) }
      end
    end

    context 'for project in subgroup' do
      let_it_be(:root_group) { create(:group) }
      let_it_be(:subgroup) { create(:group, parent: root_group) }
      let_it_be(:project_in_subgroup) { create(:project, namespace: subgroup) }

      let(:project) { project_in_subgroup }
      let(:current_user) { user_in_subgroup }
      let_it_be(:user_in_subgroup) { create(:user) }

      before_all do
        project_in_subgroup.add_maintainer(user_in_subgroup)
      end

      it 'allows service account permissions' do
        expect_allowed(*service_account_permissions)
      end
    end
  end

  describe 'AI catalog abilities' do
    let(:project) { public_project_in_group }
    let(:ai_catalog_available) { true }
    let(:flows_available) { true }
    let(:third_party_flows_available) { true }
    let(:foundational_flows_available) { true }
    let(:duo_features_enabled) { true }

    shared_examples 'no permissions when StageCheck :ai_catalog is false' do
      let(:ai_catalog_available) { false }

      it do
        expect_disallowed(
          :admin_ai_catalog_item,
          :admin_ai_catalog_item_consumer,
          :create_ai_catalog_agent,
          :create_ai_catalog_agent_item_consumer,
          :create_ai_catalog_flow,
          :create_ai_catalog_third_party_flow,
          :execute_ai_catalog_item,
          :read_ai_catalog_flow,
          :read_ai_catalog_item_consumer,
          :read_ai_catalog_third_party_flow
        )
      end
    end

    shared_examples 'no flow permissions when StageCheck :ai_catalog_flows is false' do
      let(:flows_available) { false }

      it { expect_disallowed(:read_ai_catalog_flow, :create_ai_catalog_flow) }
    end

    shared_examples 'no third party flow permissions when StageCheck :ai_catalog_third_party_flows is false' do
      let(:third_party_flows_available) { false }

      it { expect_disallowed(:read_ai_catalog_third_party_flow, :create_ai_catalog_third_party_flow) }
    end

    shared_examples 'no create third party flow permission when ai_catalog_create_third_party_flows flag disabled' do
      before do
        stub_feature_flags(ai_catalog_create_third_party_flows: false)
      end

      it { expect_disallowed(:create_ai_catalog_third_party_flow) }
    end

    shared_examples 'no foundational flow permissions when StageCheck :foundational_flows is false' do
      let(:foundational_flows_available) { false }

      it { expect_disallowed(:read_ai_foundational_flow, :create_ai_foundational_flow_item_consumer) }
    end

    shared_examples 'no permissions when Duo features are not available' do
      let(:duo_features_enabled) { false }

      it do
        expect_disallowed(
          :admin_ai_catalog_item,
          :admin_ai_catalog_item_consumer,
          :create_ai_catalog_agent,
          :create_ai_catalog_agent_item_consumer,
          :create_ai_catalog_flow,
          :create_ai_catalog_third_party_flow,
          :execute_ai_catalog_item,
          :read_ai_catalog_flow,
          :read_ai_catalog_item_consumer,
          :read_ai_catalog_third_party_flow
        )
      end
    end

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?)
        .with(project, :ai_catalog).and_return(ai_catalog_available)
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project,
        :ai_catalog_flows).and_return(flows_available)
      allow(::Gitlab::Llm::StageCheck).to receive(:available?)
        .with(project, :ai_catalog_third_party_flows).and_return(third_party_flows_available)
      allow(::Gitlab::Llm::StageCheck).to receive(:available?)
        .with(project, :foundational_flows).and_return(foundational_flows_available)
      project.duo_features_enabled = duo_features_enabled
    end

    context 'when maintainer' do
      let(:current_user) { maintainer }

      it_behaves_like 'no permissions when StageCheck :ai_catalog is false'
      it_behaves_like 'no flow permissions when StageCheck :ai_catalog_flows is false'
      it_behaves_like 'no third party flow permissions when StageCheck :ai_catalog_third_party_flows is false'
      it_behaves_like 'no foundational flow permissions when StageCheck :foundational_flows is false'
      it_behaves_like 'no create third party flow permission when ai_catalog_create_third_party_flows flag disabled'
      it_behaves_like 'no permissions when Duo features are not available'

      context 'when duo_custom_flows_enabled is false' do
        before do
          project.root_ancestor.namespace_settings.update!(duo_custom_flows_enabled: false)
        end

        it { expect_disallowed(:create_ai_catalog_flow, :create_ai_catalog_flow_item_consumer) }
      end

      context 'when duo_external_agents_enabled is false' do
        before do
          allow(project.root_ancestor).to receive(:duo_external_agents_enabled).and_return(false)
        end

        it do
          expect_disallowed(
            :create_ai_catalog_third_party_flow,
            :create_ai_catalog_third_party_flow_item_consumer
          )
        end

        it 'does not block external agent sessions' do
          project.project_setting.update!(ai_governance_enabled: true)

          expect_allowed(:create_ai_agent_audit_event)
        end
      end

      describe 'ai_governance_enabled' do
        let(:governance_permissions) do
          %i[
            create_ai_agent_identity
            create_ai_agent_session
            create_ai_agent_audit_event
            update_ai_agent_session
            read_ai_agent_session
          ]
        end

        let(:enabled) { true }

        before do
          project.project_setting.update!(ai_governance_enabled: enabled)
        end

        it { expect_allowed(*governance_permissions) }

        context 'when it is false for the project' do
          let(:enabled) { false }

          it { expect_allowed(:create_ai_catalog_third_party_flow) }
          it { expect_disallowed(*governance_permissions) }
        end

        context 'when the instance locks it on' do
          let(:enabled) { false }

          before do
            stub_application_setting(ai_governance_enabled: true, lock_ai_governance_enabled: true)
          end

          it { expect_allowed(*governance_permissions) }
        end

        context 'on GitLab.com' do
          before do
            stub_saas_features(gitlab_com_subscriptions: true)
          end

          it { expect_allowed(*governance_permissions) }
        end

        context 'when the project is in a personal namespace' do
          let(:project) { public_project }

          it 'follows the project setting on self-managed' do
            stub_saas_features(gitlab_com_subscriptions: false)

            expect_allowed(*governance_permissions)
          end

          it 'is disabled on GitLab.com, where only groups can turn it on' do
            stub_saas_features(gitlab_com_subscriptions: true)

            expect_disallowed(*governance_permissions)
          end
        end

        context 'when the ai_governance_session_gate feature flag is disabled' do
          before do
            stub_feature_flags(ai_governance_session_gate: false)
          end

          context 'when duo_external_agents_enabled is false' do
            before do
              allow(project.root_ancestor).to receive(:duo_external_agents_enabled).and_return(false)
            end

            it { expect_disallowed(*governance_permissions) }
          end

          context 'when ai_governance_enabled is false for the project' do
            let(:enabled) { false }

            it { expect_allowed(*governance_permissions) }
          end

          context 'when the project is in a personal namespace on GitLab.com' do
            let(:project) { public_project }

            before do
              stub_saas_features(gitlab_com_subscriptions: true)
            end

            it 'remains disallowed on GitLab.com, as before the ai_governance_enabled gate' do
              expect_disallowed(*governance_permissions)
            end
          end
        end
      end

      context 'when duo_custom_agents_enabled is false' do
        before do
          project.root_ancestor.namespace_settings.update!(duo_custom_agents_enabled: false)
        end

        it { expect_disallowed(:create_ai_catalog_agent, :create_ai_catalog_agent_item_consumer) }
      end
    end

    describe 'group-based access control' do
      let(:current_user) { maintainer }

      let_it_be(:membership_rule) do
        create(
          :ai_instance_accessible_entity_rules,
          :duo_agent_platform
        )
      end

      it 'calls allowed_to_use_through_namespace? with correct root_namespace parameter' do
        expect(current_user).to receive(:allowed_to_use_through_namespace?).with(
          :ai_catalog,
          project.root_ancestor
        ).and_return(true)

        expect_allowed(:read_ai_catalog_item_consumer)
      end

      context 'when catalog is available for user' do
        before do
          membership_rule.through_namespace.add_guest(current_user)
        end

        it 'enables the catalog permissions' do
          expect_allowed(:read_ai_catalog_flow)
          expect_allowed(:create_ai_catalog_flow)
          expect_allowed(:read_ai_catalog_third_party_flow)
          expect_allowed(:create_ai_catalog_third_party_flow)
          expect_allowed(:admin_ai_catalog_item)
          expect_allowed(:admin_ai_catalog_item_consumer)
          expect_allowed(:read_ai_catalog_item_consumer)
          expect_allowed(:execute_ai_catalog_item)
          expect_allowed(:create_ai_catalog_agent)
        end
      end

      context 'when catalog is not available for user' do
        it 'disables the catalog permissions' do
          expect_disallowed(:read_ai_catalog_flow)
          expect_disallowed(:create_ai_catalog_flow)
          expect_disallowed(:read_ai_catalog_third_party_flow)
          expect_disallowed(:create_ai_catalog_third_party_flow)
          expect_disallowed(:admin_ai_catalog_item)
          expect_disallowed(:admin_ai_catalog_item_consumer)
          expect_disallowed(:read_ai_catalog_item_consumer)
          expect_disallowed(:execute_ai_catalog_item)
          expect_disallowed(:create_ai_catalog_agent)
        end
      end
    end
  end

  describe 'provision_ai_catalog ability' do
    let(:ai_catalog_available) { true }

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?)
        .with(project, :ai_catalog).and_return(ai_catalog_available)
    end

    shared_examples 'provision_ai_catalog allowed for maintainer+' do
      context 'when maintainer' do
        let(:current_user) { maintainer }

        it { expect_allowed(:provision_ai_catalog) }
      end

      context 'when owner' do
        let(:current_user) { owner }

        it { expect_allowed(:provision_ai_catalog) }
      end
    end

    context 'when duo_features_enabled is false and not locked (off by default)' do
      before do
        project.project_setting.update!(duo_features_enabled: false)
        allow(project.project_setting).to receive(:duo_features_enabled_locked?).and_return(false)
      end

      it_behaves_like 'provision_ai_catalog allowed for maintainer+'
    end

    context 'when duo_features_enabled is locked to false (never on)' do
      before do
        project.project_setting.update!(duo_features_enabled: false)
        allow(project.project_setting).to receive(:duo_features_enabled_locked?).and_return(true)
      end

      context 'when maintainer' do
        let(:current_user) { maintainer }

        it { expect_disallowed(:provision_ai_catalog) }
      end

      context 'when owner' do
        let(:current_user) { owner }

        it { expect_disallowed(:provision_ai_catalog) }
      end
    end

    context 'when project_setting is nil' do
      before do
        allow(project).to receive(:project_setting).and_return(nil)
      end

      it_behaves_like 'provision_ai_catalog allowed for maintainer+'
    end
  end

  describe 'create_ai_catalog_item_consumer ability' do
    let(:ai_catalog_available) { true }

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?)
        .with(project, :ai_catalog).and_return(ai_catalog_available)
    end

    shared_examples 'create_ai_catalog_item_consumer allowed for maintainer+' do
      context 'when maintainer' do
        let(:current_user) { maintainer }

        it { expect_allowed(:create_ai_catalog_item_consumer) }
      end

      context 'when owner' do
        let(:current_user) { owner }

        it { expect_allowed(:create_ai_catalog_item_consumer) }
      end
    end

    context 'when duo_features_enabled is false and not locked (off by default)' do
      before do
        project.project_setting.update!(duo_features_enabled: false)
        allow(project.project_setting).to receive(:duo_features_enabled_locked?).and_return(false)
      end

      it_behaves_like 'create_ai_catalog_item_consumer allowed for maintainer+'
    end

    context 'when duo_features_enabled is locked to false (never on)' do
      before do
        project.project_setting.update!(duo_features_enabled: false)
        allow(project.project_setting).to receive(:duo_features_enabled_locked?).and_return(true)
      end

      context 'when maintainer' do
        let(:current_user) { maintainer }

        it { expect_disallowed(:create_ai_catalog_item_consumer) }
      end

      context 'when owner' do
        let(:current_user) { owner }

        it { expect_disallowed(:create_ai_catalog_item_consumer) }
      end
    end

    context 'when project_setting is nil' do
      before do
        allow(project).to receive(:project_setting).and_return(nil)
      end

      it_behaves_like 'create_ai_catalog_item_consumer allowed for maintainer+'
    end
  end

  context 'deploy token access' do
    subject { described_class.new(deploy_token, project) }

    context 'private project' do
      let(:project) { private_project }

      context 'a deploy token with read_registry scope' do
        let(:deploy_token) { create(:deploy_token, read_registry: true, write_registry: false, projects: [project]) }

        context 'with registry disabled' do
          include_context 'registry disabled via project features'

          it { expect_disallowed(:create_container_registry_protection_immutable_tag_rule) }
        end
      end
    end
  end

  describe 'creating container registry protection immutable tag rules' do
    let(:current_user) { public_send(user_role) }

    before do
      stub_licensed_features(container_registry_immutable_tag_rules: feature_available)
      enable_admin_mode!(current_user) if user_role == :admin
    end

    where(:feature_available, :user_role, :expected_result) do
      false | :admin      | :be_disallowed
      false | :owner      | :be_disallowed
    end

    with_them do
      it { is_expected.to send(expected_result, :create_container_registry_protection_immutable_tag_rule) }
    end
  end

  describe 'set_license_information_source' do
    let(:license_information_source_feature) { true }

    before do
      stub_licensed_features(security_dashboard: true, license_information_source: license_information_source_feature)
    end

    context 'when user is a maintainer' do
      let(:current_user) { maintainer }

      context 'when admin_security_testing is disabled' do
        before do
          allow(Ability).to receive(:allowed?).and_call_original
          allow(Ability).to receive(:allowed?).with(current_user, :admin_security_testing, project).and_return(false)
        end

        it { expect_allowed(:set_license_information_source) }
      end

      context 'when the licensed feature is disabled' do
        let(:license_information_source_feature) { false }

        it { expect_disallowed(:set_license_information_source) }
      end
    end
  end

  describe 'security policy project' do
    context 'for security_manager role' do
      let(:current_user) { security_manager }
      let_it_be(:spp) { create(:project, namespace: group) }

      let_it_be(:policy_config) do
        create(:security_orchestration_policy_configuration, :namespace,
          security_policy_management_project: spp, namespace: group)
      end

      subject { described_class.new(current_user, spp) }

      before do
        stub_licensed_features(security_orchestration_policies: true)
        group.add_security_manager(security_manager)
      end

      context 'when the project is a Security Policy management project' do
        it do
          expect_allowed(
            :create_merge_request_from,
            :create_merge_request_in,
            :push_code,
            :read_security_orchestration_policies
          )
        end

        it { expect_disallowed(:update_security_orchestration_policy_project) }
      end

      context 'when evaluating a target project with a direct SPP assignment' do
        let_it_be(:target_project) { create(:project, namespace: group) }

        let_it_be(:target_policy_config) do
          create(:security_orchestration_policy_configuration,
            project: target_project, security_policy_management_project: spp)
        end

        subject { described_class.new(current_user, target_project) }

        it { expect_allowed(:modify_security_policy) }

        # Security managers should not be able to create/assign/unassign
        # security policy projects until security concerns are addressed.
        # https://gitlab.com/groups/gitlab-org/-/work_items/22056
        it { expect_disallowed(:update_security_orchestration_policy_project) }
      end

      context 'when the project is not registered as a management project' do
        let_it_be(:unrelated_project) { create(:project, namespace: group, creator: security_manager) }
        let(:current_user) { security_manager }

        subject { described_class.new(current_user, unrelated_project) }

        it { expect_disallowed(:push_code, :create_merge_request_from) }
      end

      context 'when the security_orchestration_policies feature is not licensed' do
        before do
          stub_licensed_features(security_orchestration_policies: false)
        end

        it { expect_disallowed(:push_code, :create_merge_request_from, :read_security_orchestration_policies) }
      end
    end
  end

  describe 'configure_security_scanner' do
    before do
      stub_licensed_features(security_dashboard: true)
    end

    context 'when user has maintainer and above role' do
      where(role: %i[maintainer owner])

      with_them do
        let(:current_user) { public_send(role) }

        it do
          expect_allowed(
            :configure_security_scanner,
            :create_merge_request_from,
            :download_code,
            :push_code,
            :read_merge_request
          )
        end
      end
    end
  end

  describe 'AI flow triggers permissions' do
    let(:project) { private_project }

    context 'with duo agent platform available' do
      before do
        allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
        stub_ee_application_setting(duo_features_enabled: true)
        allow(current_user).to receive(:allowed_to_use?)
          .with(:duo_agent_platform, root_namespace: project.root_ancestor)
          .and_return(true)
      end

      describe 'manage_ai_flow_triggers permission' do
        where(:role, :allowed) do
          :anonymous  | false
          :guest      | false
          :planner    | false
          :reporter   | false
          :developer  | false
          :maintainer | true
          :owner      | true
          :admin      | true
        end

        with_them do
          let(:current_user) { public_send(role) }

          before do
            enable_admin_mode!(current_user) if role == :admin
          end

          it do
            is_expected.to(allowed ? be_allowed(:manage_ai_flow_triggers) : be_disallowed(:manage_ai_flow_triggers))
          end
        end
      end

      %i[create_ai_flow_schedule update_ai_flow_schedule delete_ai_flow_schedule].each do |permission|
        describe "#{permission} permission" do
          where(:role, :allowed) do
            :anonymous  | false
            :guest      | false
            :planner    | false
            :reporter   | false
            :developer  | false
            :maintainer | true
            :owner      | true
            :admin      | true
          end

          with_them do
            let(:current_user) { public_send(role) }

            before do
              enable_admin_mode!(current_user) if role == :admin
            end

            it { is_expected.to(allowed ? be_allowed(permission) : be_disallowed(permission)) }
          end
        end
      end

      describe 'read_ai_flow_triggers permission' do
        where(:role, :allowed) do
          :anonymous  | false
          :guest      | false
          :planner    | false
          :reporter   | false
          :developer  | true
          :maintainer | true
          :owner      | true
          :admin      | true
        end

        with_them do
          let(:current_user) { public_send(role) }

          before do
            enable_admin_mode!(current_user) if role == :admin
          end

          it { is_expected.to(allowed ? be_allowed(:read_ai_flow_triggers) : be_disallowed(:read_ai_flow_triggers)) }
        end
      end

      describe 'trigger_ai_flow permission' do
        context 'with general roles' do
          where(:role, :allowed) do
            :guest      | false
            :planner    | false
            :reporter   | false
            :developer  | true
            :maintainer | true
            :owner      | true
            :admin      | true
          end

          with_them do
            let(:current_user) { public_send(role) }

            before do
              enable_admin_mode!(current_user) if role == :admin
            end

            it { is_expected.to(allowed ? be_allowed(:trigger_ai_flow) : be_disallowed(:trigger_ai_flow)) }
          end
        end

        context 'with project that allows collaboration' do
          let(:project) { public_project }

          where(:role, :allowed) do
            :reporter   | false
            :developer  | true
          end

          with_them do
            let(:current_user) { public_send(role) }

            before do
              allow(project).to receive(:merge_requests_allowing_push_to_user).and_return(
                [instance_double(MergeRequest)]
              )
            end

            it { is_expected.to(allowed ? be_allowed(:trigger_ai_flow) : be_disallowed(:trigger_ai_flow)) }
          end
        end

        context 'with customizable permissions' do
          let(:project) { public_project_in_group }

          before_all do
            public_project_in_group.root_ancestor.update!(organization: organization)
            public_project_in_group.update!(organization: organization)
          end

          context 'when the minimum role has been set in a saas environment', :saas do
            before do
              project.root_ancestor.create_ai_settings(minimum_access_level_execute_async: ::Gitlab::Access::MAINTAINER)

              enable_admin_mode!(current_user) if role == :admin
            end

            where(:role, :allowed) do
              :guest                    | false
              :planner                  | false
              :reporter                 | false
              :developer                | false
              :maintainer               | true
              :owner                    | true
              :organization_owner       | true
              :admin                    | true
            end

            with_them do
              let(:current_user) { public_send(role) }

              it { is_expected.to(allowed ? be_allowed(:trigger_ai_flow) : be_disallowed(:trigger_ai_flow)) }
            end

            context 'when the feature flag is disabled' do
              let(:role) { :developer }
              let(:current_user) { public_send(role) }

              before do
                stub_feature_flags(dap_group_customizable_permissions: false)
              end

              it 'does not use the setting' do
                expect(subject).to be_allowed(:trigger_ai_flow)
              end
            end
          end

          context 'when the minimum role has been set on self-managed' do
            before do
              Ai::Setting.for_organization(project.organization).update!(minimum_access_level_execute_async: ::Gitlab::Access::MAINTAINER)

              enable_admin_mode!(current_user) if role == :admin
            end

            where(:role, :allowed) do
              :guest                    | false
              :planner                  | false
              :reporter                 | false
              :developer                | false
              :maintainer               | true
              :owner                    | true
              :organization_owner       | true
              :admin                    | true
            end

            with_them do
              let(:current_user) { public_send(role) }

              it { is_expected.to(allowed ? be_allowed(:trigger_ai_flow) : be_disallowed(:trigger_ai_flow)) }
            end

            context 'when the feature flag is disabled' do
              let(:role) { :developer }
              let(:current_user) { public_send(role) }

              before do
                stub_feature_flags(dap_instance_customizable_permissions: false)
              end

              it 'does not use the setting' do
                expect(subject).to be_allowed(:trigger_ai_flow)
              end
            end
          end

          context 'when the minimum role has been set to admin in a self-managed environment' do
            before do
              Ai::Setting.for_organization(project.organization).update!(minimum_access_level_execute_async: ::Gitlab::Access::ADMIN)
            end

            where(:role, :allowed) do
              :guest                    | false
              :planner                  | false
              :reporter                 | false
              :developer                | false
              :maintainer               | false
              :owner                    | false
              :organization_owner       | true
            end

            with_them do
              let(:current_user) { public_send(role) }

              it { is_expected.to(allowed ? be_allowed(:trigger_ai_flow) : be_disallowed(:trigger_ai_flow)) }
            end

            context 'when admin mode is on', :enable_admin_mode do
              let(:current_user) { admin }

              it { expect_allowed(:trigger_ai_flow) }
            end

            context 'when admin mode is off' do
              let(:current_user) { admin }

              it { expect_disallowed(:trigger_ai_flow) }
            end
          end
        end
      end
    end

    context 'when duo agent platform is not available' do
      where(role: %i[developer owner admin])

      with_them do
        let(:current_user) { public_send(role) }

        before do
          allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(false)
          allow(current_user).to receive(:allowed_to_use?).with(:duo_agent_platform).and_return(false)
          enable_admin_mode!(current_user) if role == :admin
        end

        it do
          expect_disallowed(
            :create_ai_flow_schedule,
            :delete_ai_flow_schedule,
            :manage_ai_flow_triggers,
            :read_ai_flow_triggers,
            :trigger_ai_flow,
            :update_ai_flow_schedule
          )
        end
      end

      context 'when Amazon Q is enabled' do
        where(:role, :allowed_to_trigger, :allowed_to_manage, :allowed_to_read) do
          :anonymous  | false | false | false
          :reporter   | false | false | false
          :developer  | true  | false | true
          :maintainer | true  | true  | true
          :admin      | true  | true  | true
        end

        with_them do
          let(:current_user) { public_send(role) }

          before do
            enable_admin_mode!(current_user) if role == :admin

            allow(::Ai::AmazonQ).to receive(:enabled?).and_return(true)
          end

          it { is_expected.to(allowed_to_trigger ? be_allowed(:trigger_ai_flow) : be_disallowed(:trigger_ai_flow)) }

          it do
            is_expected.to(allowed_to_manage ? be_allowed(:manage_ai_flow_triggers) : be_disallowed(:manage_ai_flow_triggers))
          end

          it do
            is_expected.to(allowed_to_read ? be_allowed(:read_ai_flow_triggers) : be_disallowed(:read_ai_flow_triggers))
          end
        end
      end
    end
  end

  # GitLab Secrets Manager Permissions
  describe 'GitLab Secrets Manager permissions' do
    secrets_manager_write_permissions = %i[
      admin_project_secrets_manager
      provision_secrets_manager
      create_project_secrets
      update_project_secrets
      delete_project_secrets
    ].freeze

    # Reads that surface the Secrets Manager status so the UI can render the current
    # state (and upgrade/trial CTA). These stay available regardless of entitlement;
    # only secret-data reads and writes are entitlement-gated.
    secrets_manager_surface_permissions = %i[
      read_project_secrets_manager
      read_project_secrets_manager_status
    ].freeze

    # Mints a JWT for reading straight from OpenBao (the non-CI/CD REST access-token
    # endpoint). Follows the stricter CI-pipeline carve-out (grace only), not the
    # broader Web/GraphQL one.
    secrets_manager_direct_read_permissions = %i[
      create_secrets_manager_api_jwt
    ].freeze

    # Deletes stay allowed in read-only entitlement states (`blocked`) so users
    # can still remove the secrets they can see.
    secrets_manager_delete_permissions = %i[
      delete_project_secrets
    ].freeze

    shared_examples 'handling secrets manager permission' do
      # The condition delegates to Availability.for_project? (licensed? && enabled).
      # enabled_for_project? combinations are covered in availability_spec.rb; here
      # we stub it plus the license and assert the policy reacts to both dimensions.
      context 'when SM availability is satisfied' do
        before do
          stub_licensed_features(native_secrets_management: true)
          allow(::SecretsManagement::Availability).to receive(:enabled_for_project?).with(project).and_return(true)
        end

        # Baseline role tests under a paid entitlement; each entitlement state is
        # exercised below.
        context 'when the entitlement permits access' do
          before do
            stub_secrets_manager_entitlement
          end

          it 'allows or disallows the permission based on role' do
            if allowed
              expect_allowed(permission)
            else
              expect_disallowed(permission)
            end
          end

          context 'when the native_secrets_management license is not available' do
            before do
              stub_licensed_features(native_secrets_management: false)
            end

            it { expect_disallowed(permission) }
          end
        end

        [
          [:ineligible, nil],
          [:blocked, :trial_expired],
          [:blocked, :credits_exhausted],
          [:blocked, :on_demand_disabled],
          [:blocked, :grace],
          [:blocked, :subscription_grace_period_expired],
          [:trial_eligible, nil],
          [:trial, nil],
          [:paid, nil],
          [:offline_paid, nil]
        ].each do |state, blocked_reason|
          label = blocked_reason ? "#{state} (#{blocked_reason})" : state.to_s

          context "when the entitlement state is #{label}" do
            before do
              entitlement = ::SecretsManagement::Entitlement.new(state: state, blocked_reason: blocked_reason)
              allow(::SecretsManagement::Entitlement).to receive(:for).and_return(entitlement)
            end

            it 'enforces the entitlement on top of the role' do
              surface_permission = secrets_manager_surface_permissions.include?(permission)
              write_permission = secrets_manager_write_permissions.include?(permission)
              delete_permission = secrets_manager_delete_permissions.include?(permission)
              direct_read_permission = secrets_manager_direct_read_permissions.include?(permission)
              entitlement_permits =
                if direct_read_permission
                  state != :ineligible && (state != :blocked || blocked_reason == :grace)
                elsif state == :trial_eligible
                  false
                elsif surface_permission
                  true
                else
                  case state
                  when :ineligible then false
                  when :blocked then !write_permission || delete_permission
                  else true
                  end
                end

              if allowed && entitlement_permits
                expect_allowed(permission)
              else
                expect_disallowed(permission)
              end
            end
          end
        end
      end

      context 'when SM availability is not satisfied' do
        before do
          stub_licensed_features(native_secrets_management: true)
          allow(::SecretsManagement::Availability).to receive(:enabled_for_project?).with(project).and_return(false)
        end

        it 'disallows the permission' do
          expect_disallowed(permission)
        end
      end
    end

    describe 'admin_project_secrets_manager' do
      let(:permission) { :admin_project_secrets_manager }

      # The entitlement and availability prevents are role-independent, so the roles that hold the
      # permission are enough. The role definitions spec covers the others.
      where(:current_user, :allowed) do
        ref(:owner) | true
      end

      with_them do
        it_behaves_like 'handling secrets manager permission'
      end
    end

    # The granular project counterpart of `admin_project_secrets_manager`, same
    # split groups already have. Gates the project provisioning mutation.
    # Maintainers and Developers are in the project's default role policies,
    # so they may provision too.
    describe 'provision_secrets_manager' do
      let(:permission) { :provision_secrets_manager }

      where(:current_user, :allowed) do
        ref(:owner)      | true
        ref(:developer)  | true
      end

      with_them do
        it_behaves_like 'handling secrets manager permission'
      end
    end

    describe 'read_project_secrets_manager' do
      let(:permission) { :read_project_secrets_manager }

      where(:current_user, :allowed) do
        ref(:owner)      | true
        ref(:maintainer) | true
      end

      with_them do
        it_behaves_like 'handling secrets manager permission'
      end
    end

    describe 'read_project_secrets_manager_status' do
      let(:permission) { :read_project_secrets_manager_status }

      where(:current_user, :allowed) do
        ref(:owner)      | true
        ref(:reporter)   | true
      end

      with_them do
        it_behaves_like 'handling secrets manager permission'
      end
    end

    %i[read_project_secrets create_project_secrets update_project_secrets delete_project_secrets
      create_secrets_manager_api_jwt].each do |perm|
      describe perm.to_s do
        let(:permission) { perm }

        where(:current_user, :allowed) do
          ref(:owner)      | true
          ref(:reporter)   | true
        end

        with_them do
          it_behaves_like 'handling secrets manager permission'
        end
      end
    end

    # Policy conditions deliberately do not emit denial telemetry: they are
    # pure predicates re-run on speculative `can?` checks and GraphQL type
    # authorization. Emission happens at the entry points instead (GraphQL
    # write concern, CI runner payload gate, service gate).
    describe 'entitlement denial telemetry' do
      let(:policy) { described_class.new(owner, project) }
      let(:entitlement) { ::SecretsManagement::Entitlement.new(state: :blocked, blocked_reason: :trial_expired) }

      before do
        stub_licensed_features(native_secrets_management: true)
        allow(::SecretsManagement::Availability).to receive(:enabled_for_project?).with(project).and_return(true)
        allow(::SecretsManagement::Entitlement).to receive(:for).and_return(entitlement)
      end

      it 'does not emit denial telemetry from policy conditions' do
        expect(::SecretsManagement::Entitlement::DenialTelemetry).not_to receive(:track)

        policy.allowed?(:create_project_secrets)
        policy.allowed?(:read_project_secrets)
      end
    end

    describe 'trial_eligible entitlement after the beta cutoff' do
      let(:policy) { described_class.new(owner, project) }
      let(:entitlement) do
        ::SecretsManagement::Entitlement.new(state: :trial_eligible, beta_program_ended: true)
      end

      before do
        stub_licensed_features(native_secrets_management: true)
        allow(::SecretsManagement::Availability).to receive(:enabled_for_project?).with(project).and_return(true)
        allow(::SecretsManagement::Entitlement).to receive(:for).and_return(entitlement)
      end

      it 'disallows the direct-read JWT (REST access-token endpoint)' do
        expect(policy).to be_disallowed(:create_secrets_manager_api_jwt)
      end
    end

    describe 'trial_eligible entitlement for the beta cohort' do
      subject { described_class.new(owner, public_project_in_group) }

      before do
        stub_licensed_features(native_secrets_management: true)
        allow(::SecretsManagement::Availability)
          .to receive(:enabled_for_project?).with(public_project_in_group).and_return(true)
        stub_secrets_manager_entitlement(state: :trial_eligible)
      end

      # The policy reads the beta cohort off the resolved entitlement
      # (`beta_window_eligible`), which the resolver derives per realm, so the
      # same rules cover SaaS namespace enrollment and self-managed instance
      # enrollment.
      context 'when the root group is in the beta cohort' do
        before do
          entitlement = ::SecretsManagement::Entitlement.new(state: :trial_eligible, beta_window_eligible: true)
          allow(::SecretsManagement::Entitlement).to receive(:for).and_return(entitlement)
        end

        it 'keeps read visibility' do
          expect_allowed(:read_project_secrets, :read_project_secrets_manager, :read_project_secrets_manager_status)
        end

        it 'keeps writes until the beta program ends' do
          expect_allowed(:create_project_secrets, :update_project_secrets, :delete_project_secrets)
        end

        context 'when the beta program has ended' do
          before do
            entitlement = ::SecretsManagement::Entitlement.new(
              state: :trial_eligible, beta_window_eligible: true, beta_program_ended: true
            )
            allow(::SecretsManagement::Entitlement).to receive(:for).and_return(entitlement)
          end

          it 'keeps read visibility' do
            expect_allowed(:read_project_secrets, :read_project_secrets_manager, :read_project_secrets_manager_status)
          end

          it 'denies creates and updates' do
            expect_disallowed(:create_project_secrets, :update_project_secrets)
          end

          it 'keeps deletes so the cohort can clean up its secrets' do
            expect_allowed(:delete_project_secrets)
          end

          it 'still denies the direct-read JWT' do
            expect_disallowed(:create_secrets_manager_api_jwt)
          end
        end

        context 'when the entitlement resolves to ineligible during the beta window' do
          before do
            entitlement = ::SecretsManagement::Entitlement.new(state: :ineligible, beta_window_eligible: true)
            allow(::SecretsManagement::Entitlement).to receive(:for).and_return(entitlement)
          end

          it 'keeps reads and writes' do
            expect_allowed(
              :create_project_secrets,
              :delete_project_secrets,
              :read_project_secrets,
              :update_project_secrets
            )
          end

          context 'when the beta program has ended' do
            before do
              entitlement = ::SecretsManagement::Entitlement.new(
                state: :ineligible, beta_window_eligible: true, beta_program_ended: true
              )
              allow(::SecretsManagement::Entitlement).to receive(:for).and_return(entitlement)
            end

            it 'denies reads and deletes alike (nothing is visible to clean up)' do
              expect_disallowed(:read_project_secrets, :delete_project_secrets)
            end
          end
        end
      end

      context 'when the entitlement is explicitly not beta-window eligible' do
        before do
          entitlement = ::SecretsManagement::Entitlement.new(state: :trial_eligible, beta_window_eligible: false)
          allow(::SecretsManagement::Entitlement).to receive(:for).and_return(entitlement)
        end

        it 'hides project secrets' do
          expect_disallowed(:read_project_secrets, :read_project_secrets_manager, :read_project_secrets_manager_status)
        end

        it 'disallows deletes along with reads' do
          expect_disallowed(:delete_project_secrets)
        end
      end

      context 'when the entitlement carries no beta signal' do
        it 'hides project secrets' do
          expect_disallowed(:read_project_secrets, :read_project_secrets_manager, :read_project_secrets_manager_status)
        end
      end
    end

    # See ee/spec/support/shared_examples/policies/secrets_manager_ui_abilities_shared_examples.rb
    # for the expected matrix.
    describe 'Secrets Manager UI abilities matrix' do
      include_context 'with secrets manager UI abilities matrix setup'

      # `can_provision` on a project page.
      describe 'provision_secrets_manager' do
        let(:ability) { :provision_secrets_manager }

        context 'when the project belongs to a group' do
          let(:policy) { described_class.new(current_user, public_project_in_group) }

          it_behaves_like 'secrets manager provisioning ability',
            'with secrets manager allowed roles (developer and up)'

          context 'when SM availability is not satisfied' do
            let(:current_user) { owner }

            before do
              allow(::SecretsManagement::Availability).to receive(:enabled_for_project?).and_return(false)
              stub_secrets_manager_entitlement(state: :paid)
            end

            it { expect(policy.allowed?(ability)).to be(false) }
          end
        end

        # A personal namespace has no top-level group, so the entitlement resolves
        # at instance level: nothing on SaaS, the instance subscription on self-managed.
        context 'when the project belongs to a personal namespace' do
          let(:policy) { described_class.new(current_user, private_project) }

          include_context 'with secrets manager allowed roles (developer and up)'

          with_them :enable_admin_mode do
            it_behaves_like 'secrets manager ability kept by allowed roles per realm only in',
              saas: SecretsManagerUiAbilities::WRITE_STATES,
              self_managed: SecretsManagerUiAbilities::WRITE_STATES
          end

          context 'when on GitLab.com without a stubbed entitlement', :saas do
            let(:current_user) { owner }

            it 'is disallowed because the entitlement resolves to ineligible' do
              expect(policy.allowed?(ability)).to be(false)
            end
          end
        end
      end

      # The role-policy arm behind creating secrets: Reporter and above, not
      # Owner-only like `provision_secrets_manager` above. The "New secret"
      # button itself follows the OpenBao `userPermissions.createSecrets`
      # capability; this ability still gates the create mutation.
      describe 'create_project_secrets' do
        let(:ability) { :create_project_secrets }
        let(:policy) { described_class.new(current_user, public_project_in_group) }

        it_behaves_like 'secrets manager secret-creation ability'
      end
    end

    describe 'update_ai_tool_rule' do
      context 'when duo_features_enabled is false' do
        before do
          allow(project).to receive(:duo_features_enabled).and_return(false)
        end

        context 'when user is an owner' do
          let(:current_user) { owner }

          it { expect_disallowed(:update_ai_tool_rule, :read_ai_tool_rule) }
        end
      end
    end

    describe 'block_ai_catalog_mcp_server' do
      context 'when duo_features_enabled is false' do
        before do
          allow(project).to receive(:duo_features_enabled).and_return(false)
        end

        context 'when user is an owner' do
          let(:current_user) { owner }

          it { expect_disallowed(:block_ai_catalog_mcp_server) }
        end
      end
    end
  end

  describe 'remove_project for enterprise user personal projects', :saas do
    let_it_be(:enterprise_group) { create(:group) }
    let_it_be(:enterprise_user) { create(:enterprise_user, :with_namespace, enterprise_group: enterprise_group) }
    let_it_be(:personal_project) { create(:project, namespace: enterprise_user.namespace) }

    subject { described_class.new(current_user, personal_project) }

    before do
      stub_licensed_features(domain_verification: true)
    end

    context 'when current user is an owner of the enterprise group' do
      let_it_be(:current_user) { create(:user, owner_of: enterprise_group) }

      it { expect_allowed(:remove_project) }
    end

    context 'when domain verification is not available' do
      let_it_be(:current_user) { create(:user, owner_of: enterprise_group) }

      before do
        stub_licensed_features(domain_verification: false)
      end

      it { expect_disallowed(:remove_project) }
    end

    context 'when current user is a maintainer of the enterprise group' do
      let_it_be(:current_user) { create(:user, maintainer_of: enterprise_group) }

      it { expect_disallowed(:remove_project) }
    end

    context 'when the project is not a personal project' do
      let_it_be(:current_user) { create(:user, owner_of: enterprise_group) }
      let_it_be(:other_group) { create(:group) }
      let_it_be(:group_project) { create(:project, group: other_group) }

      subject { described_class.new(current_user, group_project) }

      it { expect_disallowed(:remove_project) }
    end

    context 'when current user is anonymous' do
      subject { described_class.new(nil, public_project) }

      it { expect_disallowed(:remove_project) }
    end

    context 'when current user is not a member of the enterprise group' do
      let_it_be(:current_user) { create(:user) }

      it { expect_disallowed(:remove_project) }
    end

    context 'when the project owner is not an enterprise user' do
      let_it_be(:current_user) { create(:user, owner_of: enterprise_group) }
      let_it_be(:regular_user) { create(:user) }
      let_it_be(:regular_project) { create(:project, namespace: regular_user.namespace) }

      subject { described_class.new(current_user, regular_project) }

      it { expect_disallowed(:remove_project) }
    end
  end
end
