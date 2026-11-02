# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::Transfer::GroupsService, :aggregate_failures, feature_category: :organization do
  let_it_be(:old_organization) { create(:organization) }
  let_it_be(:new_organization) { create(:organization) }
  let_it_be(:user) { create(:user, organization: old_organization) }
  let_it_be_with_refind(:group) { create(:group, organization: old_organization) }

  let(:service) { described_class.new(group: group, new_organization: new_organization, current_user: user) }

  before_all do
    group.add_owner(user)
    new_organization.add_owner(user)
  end

  describe '#execute' do
    context 'when transfer is successful' do
      let_it_be_with_refind(:subgroup) { create(:group, parent: group, organization: old_organization) }
      let_it_be_with_refind(:project) { create(:project, namespace: group, organization: old_organization) }

      it 'logs an audit event with the source organization' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
          hash_including(
            name: 'group_transferred_to_organization',
            author: user,
            scope: group,
            target: new_organization,
            additional_details: {
              source_organization_id: old_organization.id,
              target_organization_id: new_organization.id
            }
          )
        ).and_call_original

        expect { service.execute }.to change { AuditEventReader.count }.by(1)
      end

      context 'when the top-level group is already in the target organization' do
        before do
          # Organizations::ConfirmService moves the root and logs the transfer before activation.
          group.update_column(:organization_id, new_organization.id)
          group.namespace_details.update!(
            state_metadata: { 'organization_transfer_source_id' => old_organization.id }
          )
        end

        it 'does not log another audit event' do
          expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

          expect(service.execute).to be_success
        end
      end

      it 'enqueues the SBOM transfer worker' do
        expect(Organizations::Transfer::SbomWorker).to receive(:perform_async).with(
          group.id,
          old_organization.id,
          new_organization.id
        )

        service.execute
      end

      context 'for cd environments' do
        let_it_be_with_refind(:cd_environment) do
          create(:cd_environment, organization: old_organization)
        end

        let_it_be_with_refind(:cd_environment2) do
          create(:cd_environment, organization: old_organization)
        end

        # Cd::Environment records are organization-scoped and stay with the
        # organization during a group transfer. See discussion:
        # https://gitlab.com/gitlab-org/gitlab/-/merge_requests/238712#note_3424705739
        it 'does not move organization-scoped cd environments to the new organization' do
          service.execute

          expect(cd_environment.reload.organization_id).to eq(old_organization.id)
          expect(cd_environment2.reload.organization_id).to eq(old_organization.id)
        end
      end

      context 'for seat assignment transfers' do
        let_it_be_with_refind(:user1) { create(:user, organization: old_organization) }
        let_it_be_with_refind(:user2) { create(:user, organization: old_organization) }
        let_it_be_with_refind(:user3) { create(:user, organization: old_organization) }
        let_it_be_with_refind(:seat_assignment1) do
          create(:gitlab_subscription_seat_assignment,
            namespace: group,
            user: user1,
            organization_id: old_organization.id)
        end

        let_it_be_with_refind(:seat_assignment2) do
          create(:gitlab_subscription_seat_assignment,
            namespace: group,
            user: user2,
            organization_id: old_organization.id)
        end

        let_it_be_with_refind(:seat_assignment3) do
          create(:gitlab_subscription_seat_assignment,
            namespace: group,
            user: user3,
            organization_id: old_organization.id)
        end

        before_all do
          group.add_maintainer(user1)
          group.add_developer(user2)
          group.add_guest(user3)
        end

        it 'updates organization_id for seat assignments' do
          service.execute

          expect(seat_assignment1.reload.organization_id).to eq(new_organization.id)
          expect(seat_assignment2.reload.organization_id).to eq(new_organization.id)
          expect(seat_assignment3.reload.organization_id).to eq(new_organization.id)
        end

        it 'only updates seat assignments for the transferring group' do
          other_group = create(:group, organization: old_organization)
          other_seat_assignment = create(:gitlab_subscription_seat_assignment,
            namespace: other_group,
            user: user1,
            organization_id: old_organization.id)

          service.execute

          expect(other_seat_assignment.reload.organization_id).to eq(old_organization.id)
        end

        context 'when batching updates' do
          include_context 'with transfer batch size of 1'

          let(:execute_service) { service.execute }
          let(:expected_batch_queries) do
            { 'subscription_seat_assignments' => 3 }
          end

          it 'processes all seat assignments across multiple batches' do
            service.execute

            expect(seat_assignment1.reload.organization_id).to eq(new_organization.id)
            expect(seat_assignment2.reload.organization_id).to eq(new_organization.id)
            expect(seat_assignment3.reload.organization_id).to eq(new_organization.id)
          end

          it_behaves_like 'generates batched transfer queries'
        end
      end

      context 'for add-on purchase transfers' do
        let_it_be(:add_on) { create(:gitlab_subscription_add_on, :duo_pro) }
        let_it_be_with_refind(:add_on_purchase) do
          create(:gitlab_subscription_add_on_purchase,
            :active,
            add_on: add_on,
            namespace: group,
            organization: old_organization)
        end

        let_it_be_with_refind(:add_on_purchase_2) do
          create(:gitlab_subscription_add_on_purchase,
            :active,
            add_on: create(:gitlab_subscription_add_on, :duo_enterprise),
            namespace: group,
            organization: old_organization)
        end

        it 'updates organization_id for all add-on purchases' do
          service.execute

          expect(add_on_purchase.reload.organization_id).to eq(new_organization.id)
          expect(add_on_purchase_2.reload.organization_id).to eq(new_organization.id)
        end
      end

      context 'for user add-on assignment transfers' do
        let_it_be(:add_on) { create(:gitlab_subscription_add_on, :duo_pro) }
        let_it_be_with_refind(:add_on_purchase) do
          create(:gitlab_subscription_add_on_purchase,
            :active,
            add_on: add_on,
            namespace: group,
            organization: old_organization)
        end

        let_it_be_with_refind(:user1) { create(:user, organization: old_organization) }
        let_it_be_with_refind(:user2) { create(:user, organization: old_organization) }
        let_it_be_with_refind(:user3) { create(:user, organization: old_organization) }
        let_it_be_with_refind(:user_add_on_assignment1) do
          create(:gitlab_subscription_user_add_on_assignment,
            user: user1,
            add_on_purchase: add_on_purchase,
            organization_id: old_organization.id)
        end

        let_it_be_with_refind(:user_add_on_assignment2) do
          create(:gitlab_subscription_user_add_on_assignment,
            user: user2,
            add_on_purchase: add_on_purchase,
            organization_id: old_organization.id)
        end

        let_it_be_with_refind(:user_add_on_assignment3) do
          create(:gitlab_subscription_user_add_on_assignment,
            user: user3,
            add_on_purchase: add_on_purchase,
            organization_id: old_organization.id)
        end

        before_all do
          group.add_maintainer(user1)
          group.add_developer(user2)
          group.add_guest(user3)
        end

        it 'updates organization_id for user add-on assignments' do
          service.execute

          expect(user_add_on_assignment1.reload.organization_id).to eq(new_organization.id)
          expect(user_add_on_assignment2.reload.organization_id).to eq(new_organization.id)
          expect(user_add_on_assignment3.reload.organization_id).to eq(new_organization.id)
        end

        context 'when user add-on assignments belong to different add-on purchase' do
          let_it_be(:other_group) { create(:group, organization: old_organization) }
          let_it_be_with_refind(:other_add_on_purchase) do
            create(:gitlab_subscription_add_on_purchase,
              :active,
              add_on: add_on,
              namespace: other_group,
              organization: old_organization)
          end

          let_it_be_with_refind(:other_assignment) do
            create(:gitlab_subscription_user_add_on_assignment,
              user: user1,
              add_on_purchase: other_add_on_purchase,
              organization_id: old_organization.id)
          end

          it 'does not update assignments for other add-on purchases' do
            service.execute

            expect(user_add_on_assignment1.reload.organization_id).to eq(new_organization.id)
            expect(other_assignment.reload.organization_id).to eq(old_organization.id)
          end
        end

        it 'updates organization_id for user add-on assignment versions' do
          service.execute

          version_1 = GitlabSubscriptions::UserAddOnAssignmentVersion.find_by(purchase_id: add_on_purchase.id,
            user_id: user1.id)
          version_2 = GitlabSubscriptions::UserAddOnAssignmentVersion.find_by(purchase_id: add_on_purchase.id,
            user_id: user2.id)
          version_3 = GitlabSubscriptions::UserAddOnAssignmentVersion.find_by(purchase_id: add_on_purchase.id,
            user_id: user3.id)

          expect(version_1.organization_id).to eq(new_organization.id)
          expect(version_2.organization_id).to eq(new_organization.id)
          expect(version_3.organization_id).to eq(new_organization.id)
        end

        context 'when user add-on assignment versions belong to different add-on purchase' do
          let_it_be(:other_group) { create(:group, organization: old_organization) }
          let_it_be_with_refind(:other_add_on_purchase) do
            create(:gitlab_subscription_add_on_purchase,
              :active,
              add_on: add_on,
              namespace: other_group,
              organization: old_organization)
          end

          let_it_be_with_refind(:other_assignment) do
            create(:gitlab_subscription_user_add_on_assignment,
              user: user1,
              add_on_purchase: other_add_on_purchase,
              organization_id: old_organization.id)
          end

          it 'does not update versions for other add-on purchases' do
            service.execute

            transferring_version = GitlabSubscriptions::UserAddOnAssignmentVersion.find_by(
              purchase_id: add_on_purchase.id,
              user_id: user1.id)
            other_version = GitlabSubscriptions::UserAddOnAssignmentVersion.find_by(
              purchase_id: other_add_on_purchase.id,
              user_id: user1.id)

            expect(transferring_version.organization_id).to eq(new_organization.id)
            expect(other_version.organization_id).to eq(old_organization.id)
          end
        end
      end

      context 'for security export upload transfers' do
        let_it_be_with_refind(:dep_part_upload) do
          create(:geo_dependency_list_export_part_upload,
            parent_model: create(:dependency_list_export_part,
              dependency_list_export: create(:dependency_list_export, project: nil, group: group, organization: nil),
              organization: old_organization))
        end

        let_it_be_with_refind(:vuln_export_upload) do
          create(:geo_vulnerability_export_upload,
            parent_model: create(:vulnerability_export, :group, group: group, organization: old_organization))
        end

        let_it_be_with_refind(:vuln_part_upload) do
          create(:geo_vulnerability_export_part_upload,
            parent_model: create(:vulnerability_export_part,
              vulnerability_export: create(:vulnerability_export, project: project, organization: old_organization),
              organization: old_organization))
        end

        it 'updates organization_id for security export uploads' do
          service.execute

          expect(dep_part_upload.reload.organization_id).to eq(new_organization.id)
          expect(vuln_export_upload.reload.organization_id).to eq(new_organization.id)
          expect(vuln_part_upload.reload.organization_id).to eq(new_organization.id)
        end

        it 'fires triggers on upload state tables' do
          # Ensure state records exist and have the old org_id
          dep_state = dep_part_upload.dependency_list_export_part_upload_state
          dep_state.save! unless dep_state.persisted?
          dep_state.update_column(:organization_id, old_organization.id)

          vuln_state = vuln_export_upload.vulnerability_export_upload_state
          vuln_state.save! unless vuln_state.persisted?
          vuln_state.update_column(:organization_id, old_organization.id)

          vuln_part_state = vuln_part_upload.vulnerability_export_part_upload_state
          vuln_part_state.save! unless vuln_part_state.persisted?
          vuln_part_state.update_column(:organization_id, old_organization.id)

          service.execute

          expect(dep_state.reload.organization_id).to eq(new_organization.id)
          expect(vuln_state.reload.organization_id).to eq(new_organization.id)
          expect(vuln_part_state.reload.organization_id).to eq(new_organization.id)
        end

        it 'does not update uploads belonging to an unrelated organization' do
          unrelated_organization = create(:organization)
          unrelated_group = create(:group, organization: unrelated_organization)
          unrelated_project = create(:project, namespace: unrelated_group, organization: unrelated_organization)

          unrelated_export = create(:vulnerability_export,
            project: unrelated_project, organization: unrelated_organization)
          unrelated_upload = create(:geo_vulnerability_export_upload, parent_model: unrelated_export)

          service.execute

          expect(unrelated_upload.reload.organization_id).to eq(unrelated_organization.id)
        end

        it 'does not update state records for uploads outside the transferred group' do
          unrelated_group = create(:group, organization: new_organization)
          unrelated_project = create(:project, namespace: unrelated_group, organization: new_organization)

          unrelated_upload = create(:geo_vulnerability_export_upload,
            parent_model: create(:vulnerability_export, project: unrelated_project, organization: new_organization))

          unrelated_state = unrelated_upload.vulnerability_export_upload_state
          unrelated_state.save! unless unrelated_state.persisted?
          unrelated_state.update_column(:organization_id, old_organization.id)

          service.execute

          expect(unrelated_state.reload.organization_id).to eq(old_organization.id)
        end

        context 'when batching updates' do
          include_context 'with transfer batch size of 1'

          let_it_be_with_refind(:dep_part_upload2) do
            create(:geo_dependency_list_export_part_upload,
              parent_model: create(:dependency_list_export_part,
                dependency_list_export: create(:dependency_list_export, project: nil, group: group,
                  organization: nil),
                organization: old_organization))
          end

          let_it_be_with_refind(:dep_part_upload3) do
            create(:geo_dependency_list_export_part_upload,
              parent_model: create(:dependency_list_export_part,
                dependency_list_export: create(:dependency_list_export, project: project, organization: nil),
                organization: old_organization))
          end

          let_it_be_with_refind(:vuln_export_upload2) do
            create(:geo_vulnerability_export_upload,
              parent_model: create(:vulnerability_export, :group, group: group, organization: old_organization))
          end

          let_it_be_with_refind(:vuln_export_upload3) do
            create(:geo_vulnerability_export_upload,
              parent_model: create(:vulnerability_export, project: project, organization: old_organization))
          end

          let_it_be_with_refind(:vuln_part_upload2) do
            create(:geo_vulnerability_export_part_upload,
              parent_model: create(:vulnerability_export_part,
                vulnerability_export: create(:vulnerability_export, :group, group: group,
                  organization: old_organization),
                organization: old_organization))
          end

          let_it_be_with_refind(:vuln_part_upload3) do
            create(:geo_vulnerability_export_part_upload,
              parent_model: create(:vulnerability_export_part,
                vulnerability_export: create(:vulnerability_export, project: project,
                  organization: old_organization),
                organization: old_organization))
          end

          let(:execute_service) { service.execute }
          let(:expected_batch_queries) do
            {
              'dependency_list_export_part_uploads' => 3,
              'vulnerability_export_uploads' => 3,
              'vulnerability_export_part_uploads' => 3
            }
          end

          it 'processes all upload records across multiple batches' do
            service.execute

            expect(dep_part_upload2.reload.organization_id).to eq(new_organization.id)
            expect(dep_part_upload3.reload.organization_id).to eq(new_organization.id)
            expect(vuln_export_upload2.reload.organization_id).to eq(new_organization.id)
            expect(vuln_export_upload3.reload.organization_id).to eq(new_organization.id)
            expect(vuln_part_upload2.reload.organization_id).to eq(new_organization.id)
            expect(vuln_part_upload3.reload.organization_id).to eq(new_organization.id)
          end

          it_behaves_like 'generates batched transfer queries'
        end
      end

      context 'for security export parts async transfer' do
        it 'schedules SecurityExportsWorker after the transfer completes' do
          expect(::Organizations::Transfer::SecurityExportsWorker)
            .to receive(:perform_async)
            .with(group.id, old_organization.id, new_organization.id)

          service.execute
        end
      end

      context 'for ai catalog item transfers' do
        let_it_be_with_refind(:ai_catalog_item) do
          create(:ai_catalog_item, project: project, organization: old_organization)
        end

        it 'updates organization_id for ai catalog items linked to projects in the group' do
          service.execute

          expect(ai_catalog_item.reload.organization_id).to eq(new_organization.id)
        end

        it 'updates organization_id for item versions, dependencies, and stars owned by the item' do
          version = ai_catalog_item.versions.first
          dependency = create(:ai_catalog_item_version_dependency, ai_catalog_item_version: version,
            organization: old_organization)
          star = create(:ai_catalog_item_star, item: ai_catalog_item, organization: old_organization)

          service.execute

          expect(version.reload.organization_id).to eq(new_organization.id)
          expect(dependency.reload.organization_id).to eq(new_organization.id)
          expect(star.reload.organization_id).to eq(new_organization.id)
        end

        it 'does not update ai catalog items for projects outside the group' do
          other_group = create(:group, organization: old_organization)
          other_project = create(:project, namespace: other_group, organization: old_organization)
          other_item = create(:ai_catalog_item, project: other_project, organization: old_organization)
          other_version = other_item.versions.first
          other_star = create(:ai_catalog_item_star, item: other_item, organization: old_organization)

          service.execute

          expect(other_item.reload.organization_id).to eq(old_organization.id)
          expect(other_version.reload.organization_id).to eq(old_organization.id)
          expect(other_star.reload.organization_id).to eq(old_organization.id)
        end

        context 'when ai catalog items are in subgroup projects' do
          let_it_be_with_refind(:nested_subgroup) { create(:group, parent: subgroup, organization: old_organization) }
          let_it_be_with_refind(:subgroup_project) do
            create(:project, namespace: nested_subgroup, organization: old_organization)
          end

          let_it_be_with_refind(:subgroup_catalog_item) do
            create(:ai_catalog_item, project: subgroup_project, organization: old_organization)
          end

          it 'updates organization_id for ai catalog items in subgroup projects' do
            service.execute

            expect(subgroup_catalog_item.reload.organization_id).to eq(new_organization.id)
          end
        end
      end

      context 'for upcoming reconciliation transfers' do
        let_it_be_with_refind(:reconciliation) do
          create(:upcoming_reconciliation, :saas, namespace: group, organization: old_organization)
        end

        let_it_be_with_refind(:subgroup_reconciliation) do
          create(:upcoming_reconciliation, :saas, namespace: subgroup, organization: old_organization)
        end

        it 'updates organization_id for reconciliations in the transferred group' do
          service.execute

          expect(reconciliation.reload.organization_id).to eq(new_organization.id)
          expect(subgroup_reconciliation.reload.organization_id).to eq(new_organization.id)
        end

        it 'does not update reconciliations for other groups' do
          other_group = create(:group, organization: old_organization)
          other_reconciliation = create(:upcoming_reconciliation, :saas,
            namespace: other_group, organization: old_organization)

          service.execute

          expect(other_reconciliation.reload.organization_id).to eq(old_organization.id)
        end
      end

      context 'for security policy settings' do
        let_it_be_with_refind(:policy_setting) do
          create(:security_policy_settings, organization: old_organization, csp_namespace: group)
        end

        it 'unassigns the transferred group as the old organization CSP namespace' do
          expect(ComplianceManagement::ProjectSettingsDestroyWorker).to receive(:perform_async).with(group.id)

          service.execute

          expect(policy_setting.reload.csp_namespace_id).to be_nil
          expect(policy_setting.organization_id).to eq(old_organization.id)
        end

        it 'leaves the old organization free to designate a new CSP namespace' do
          service.execute

          expect(policy_setting.reload.csp_namespace_locked_until).to be_nil
        end

        context 'when another group is the CSP namespace' do
          let_it_be(:other_group) { create(:group, organization: old_organization) }

          before do
            policy_setting.update_columns(csp_namespace_id: other_group.id)
          end

          it 'keeps the CSP namespace' do
            service.execute

            expect(policy_setting.reload.csp_namespace_id).to eq(other_group.id)
          end
        end
      end

      it 'enqueues the cross-organization policy unassign worker' do
        expect(Security::UnassignCrossOrganizationPolicyConfigurationsWorker).to receive(:perform_async).with(group.id)

        service.execute
      end

      context 'for scim token transfers' do
        it 'does not update instance-level SCIM tokens' do
          instance_token = create(:scim_oauth_access_token, organization: old_organization)

          service.execute

          expect(instance_token.reload.organization_id).to eq(old_organization.id)
        end
      end

      context 'when batching fulfillment and identity table updates' do
        include_context 'with transfer batch size of 1'

        let_it_be(:nested_subgroup) { create(:group, parent: subgroup, organization: old_organization) }

        let_it_be_with_refind(:reconciliation1) do
          create(:upcoming_reconciliation, :saas, namespace: group, organization: old_organization)
        end

        let_it_be_with_refind(:reconciliation2) do
          create(:upcoming_reconciliation, :saas, namespace: subgroup, organization: old_organization)
        end

        let_it_be_with_refind(:reconciliation3) do
          create(:upcoming_reconciliation, :saas, namespace: nested_subgroup, organization: old_organization)
        end

        let(:execute_service) { service.execute }
        let(:expected_batch_queries) do
          {
            'upcoming_reconciliations' => 3
          }
        end

        it 'processes all records across multiple batches' do
          service.execute

          expect(reconciliation1.reload.organization_id).to eq(new_organization.id)
          expect(reconciliation2.reload.organization_id).to eq(new_organization.id)
          expect(reconciliation3.reload.organization_id).to eq(new_organization.id)
        end

        it_behaves_like 'generates batched transfer queries'
      end

      context 'for custom dashboards transfers' do
        let_it_be_with_refind(:dashboard) do
          create(:dashboard, namespace: group, organization: old_organization)
        end

        let_it_be_with_refind(:subgroup_dashboard) do
          create(:dashboard, namespace: subgroup, organization: old_organization)
        end

        let_it_be_with_refind(:org_scoped_dashboard) do
          create(:dashboard, :organization_scoped, organization: old_organization)
        end

        let_it_be_with_refind(:dashboard_version) do
          create(:dashboard_version, dashboard: dashboard)
        end

        it 'updates organization_id for dashboards, search data, and dashboard versions' do
          service.execute

          expect(dashboard.reload.organization_id).to eq(new_organization.id)
          expect(dashboard.search_data.organization_id).to eq(new_organization.id)
          expect(dashboard_version.reload.organization_id).to eq(new_organization.id)
          expect(subgroup_dashboard.reload.organization_id).to eq(new_organization.id)
        end

        it 'does not update organization-scoped dashboards' do
          service.execute

          expect(org_scoped_dashboard.reload.organization_id).to eq(old_organization.id)
          expect(org_scoped_dashboard.search_data.organization_id).to eq(old_organization.id)
        end

        it 'does not update dashboards belonging to other groups in the old organization' do
          other_group = create(:group, organization: old_organization)
          other_dashboard = create(:dashboard, namespace: other_group, organization: old_organization)
          other_version = create(:dashboard_version, dashboard: other_dashboard)

          service.execute

          expect(other_dashboard.reload.organization_id).to eq(old_organization.id)
          expect(other_dashboard.search_data.organization_id).to eq(old_organization.id)
          expect(other_version.reload.organization_id).to eq(old_organization.id)
        end

        it 'does not update dashboards in other organizations' do
          other_organization = create(:organization)
          other_dashboard = create(:dashboard, :organization_scoped, organization: other_organization)

          expect { service.execute }.not_to change { other_dashboard.reload.organization_id }
        end
      end

      context 'for secrets managers' do
        let_it_be_with_refind(:group_secrets_manager) { create(:group_secrets_manager, group: group) }
        let_it_be_with_refind(:subgroup_secrets_manager) { create(:group_secrets_manager, group: subgroup) }
        let_it_be_with_refind(:project_secrets_manager) { create(:project_secrets_manager, project: project) }

        let(:secrets_managers) { [group_secrets_manager, subgroup_secrets_manager, project_secrets_manager] }

        it 'keeps the OpenBao namespace paths of existing secrets managers' do
          paths_before = secrets_managers.map(&:full_namespace_path)

          service.execute

          expect(group.reload.organization_id).to eq(new_organization.id)
          expect(secrets_managers.map { |sm| sm.reload.organization_id }).to all(eq(old_organization.id))
          expect(secrets_managers.map(&:full_namespace_path)).to eq(paths_before)
          expect(paths_before).to all(start_with("org_#{old_organization.id}/group_#{group.id}/"))
        end

        it 'creates new secrets managers under the new organization' do
          service.execute

          new_subgroup = create(:group, parent: group.reload, organization: new_organization)
          new_secrets_manager = create(:group_secrets_manager, group: new_subgroup)

          expect(new_secrets_manager.full_namespace_path)
            .to eq("org_#{new_organization.id}/group_#{group.id}/group_#{new_subgroup.id}")
        end
      end
    end

    context 'when transfer fails' do
      let_it_be(:add_on) { create(:gitlab_subscription_add_on, :duo_pro) }
      let_it_be_with_refind(:add_on_purchase) do
        create(:gitlab_subscription_add_on_purchase,
          :active,
          add_on: add_on,
          namespace: group,
          organization: old_organization)
      end

      let_it_be_with_refind(:user1) { create(:user, organization: old_organization) }
      let_it_be_with_refind(:seat_assignment) do
        create(:gitlab_subscription_seat_assignment,
          namespace: group,
          user: user1,
          organization_id: old_organization.id)
      end

      let_it_be_with_refind(:user_add_on_assignment) do
        create(:gitlab_subscription_user_add_on_assignment,
          user: user1,
          add_on_purchase: add_on_purchase,
          organization_id: old_organization.id)
      end

      before_all do
        group.add_maintainer(user1)
      end

      context 'when an exception occurs during transfer' do
        let(:error_message) { 'Transfer failed' }

        before do
          allow(ForkNetwork).to receive(:where).and_raise(StandardError, error_message)
        end

        it_behaves_like 'leaves organization_id unchanged on failure' do
          let(:records) { [add_on_purchase, seat_assignment, user_add_on_assignment] }
        end

        it 'does not log an audit event' do
          expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

          service.execute
        end

        it 'returns error ServiceResponse without enqueuing post-commit workers' do
          expect(Organizations::Transfer::SbomWorker).not_to receive(:perform_async)
          expect(Security::UnassignCrossOrganizationPolicyConfigurationsWorker).not_to receive(:perform_async)

          result = service.execute

          expect(result).to be_a(ServiceResponse)
          expect(result).to be_error
          expect(result.message).to eq(error_message)
        end
      end
    end
  end
end
