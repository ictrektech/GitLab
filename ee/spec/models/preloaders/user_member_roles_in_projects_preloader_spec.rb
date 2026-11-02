# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Preloaders::UserMemberRolesInProjectsPreloader, feature_category: :permissions do
  include MemberRoleHelpers

  let_it_be(:user) { create(:user) }

  let_it_be(:group) { create(:group) }
  let_it_be(:sub_group) { create(:group, parent: group) }

  let_it_be(:project) { create(:project, :private, group: sub_group) }
  let_it_be(:project_2) { create(:project, :private, group: group) }

  let_it_be_with_reload(:group_member) { create(:group_member, :guest, user: user, source: group) }
  let_it_be_with_reload(:sub_group_member) { create(:group_member, :guest, user: user, source: sub_group) }

  let_it_be_with_reload(:project_member) { create(:project_member, :guest, user: user, source: project) }
  let_it_be_with_reload(:project_2_member) { create(:project_member, :guest, user: user, source: project_2) }

  let(:projects_list) { [project, project_2] }

  subject(:result) { described_class.new(projects: projects_list, user: user).execute }

  before do
    stub_licensed_features(custom_roles: true)
  end

  shared_examples 'custom roles' do |ability|
    context "with ability: #{ability}" do
      let_it_be(:member_role) { create_member_role(group, ability) }

      context 'when custom_roles license is not enabled on project root ancestor' do
        before do
          stub_licensed_features(custom_roles: false)

          project_member.update!(member_role: member_role)
        end

        it 'returns project id with empty array' do
          expect(result).to eq(project.id => [], project_2.id => [])
        end
      end

      context 'when custom_roles license is enabled on project root ancestor' do
        let_it_be(:ability_2) { random_ability(ability, :all_customizable_project_permissions) }

        let_it_be(:member_role_2) { create_member_role(group, ability_2) }

        let_it_be(:expected_abilities) { expected_project_abilities(ability) }
        let_it_be(:expected_abilities_2) { expected_project_abilities(ability_2) }

        context 'when project members are assigned a custom role' do
          before do
            project_member.update!(member_role: member_role)
            project_2_member.update!(member_role: member_role_2)
          end

          context 'when ability is enabled' do
            it 'returns all requested project IDs with their respective abilities' do
              expect(result[project.id]).to match_array(expected_abilities)
              expect(result[project_2.id]).to match_array(expected_abilities_2)
            end

            it 'logs the query' do
              expect(Gitlab::AppLogger).to receive(:info).with({
                class: described_class.name,
                user_id: user.id,
                projects_count: 2
              })

              result
            end

            it 'avoids N+1 queries' do
              control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
                described_class.new(projects: [project], user: user).execute
              end

              expect do
                described_class.new(projects: [project, project_2], user: user).execute
              end.to issue_same_number_of_queries_as(control).or_fewer
            end

            context 'with RequestStore enabled', :request_store do
              it 'only requests the extra projects when uncached projects are passed' do
                described_class.new(projects: [project], user: user).execute

                queries = ActiveRecord::QueryRecorder.new do
                  described_class.new(projects: [project, project_2], user: user).execute
                end

                if Feature.enabled?(:resolve_project_access_from_memberships, user)
                  # The extra project's shares and membership, its root namespace, and the member_roles permissions.
                  expect(queries.count).to eq(4)
                  expect(queries.log_message).to match(/"project_group_links"."project_id" = #{project_2.id}/)
                else
                  expect(queries.log_message).to match(/"projects"."id" = #{project_2.id}/)
                  expect(queries.count).to eq(4)
                  expect(queries.log_message).to match(/VALUES \(#{project_2.id}/)
                  expect(queries.log_message).not_to match(/VALUES \(#{project.id}/)
                end
              end
            end

            context 'when an array of project IDs is passed instead of objects' do
              let(:projects_list) { [project.id, project_2.id] }

              it 'returns all requested project IDs with their respective abilities', :aggregate_failures do
                expect(result[project.id]).to match_array(expected_abilities)
                expect(result[project_2.id]).to match_array(expected_abilities_2)
              end
            end
          end

          context 'when ActiveRecord::Relation of projects passed' do
            let(:projects_list) { Project.where(id: project.id) }

            it 'returns the project_id with a value array that includes the ability' do
              expect(result[project.id]).to match_array(expected_abilities)
            end
          end

          context 'when nil projects are passed' do
            let(:projects_list) { nil }

            it 'returns an empty hash' do
              expect(result).to eq({})
            end
          end

          context 'when nil user is passed' do
            let(:user) { nil }

            it 'returns an empty hash' do
              expect(result).to eq({})
            end
          end
        end

        context 'when a user is assigned custom roles in both group and project' do
          let(:expected) { (expected_abilities + expected_abilities_2).uniq }

          before do
            project_member.update!(member_role: member_role)
            assign_member_role(group_member, member_role_2)
          end

          it 'returns abilities assigned to the custom role inside both project and group' do
            expect(result[project.id]).to match_array(expected)
          end
        end

        context 'when a user is assigned custom roles in group, sub_group and project' do
          let_it_be(:expected) { (expected_abilities + [:read_code, :read_vulnerability]).uniq }

          let_it_be(:read_code_member_role) { create_member_role(group, :read_code) }
          let_it_be(:read_vulnerability_member_role) { create_member_role(group, :read_vulnerability) }

          before do
            project_member.update!(member_role: member_role)
            assign_member_role(group_member, read_code_member_role)
            assign_member_role(sub_group_member, read_vulnerability_member_role)
          end

          it 'returns abilities assigned to the custom role inside group, sub_group and project' do
            expect(result[project.id]).to match_array(expected)
          end
        end

        context 'when project membership has no custom role' do
          it 'returns project id with empty value array' do
            expect(result).to eq(project.id => [], project_2.id => [])
          end
        end

        context 'when project member is awaiting approval' do
          let_it_be(:awaiting_user) { create(:user) }
          let_it_be_with_reload(:awaiting_project_member) do
            create(:project_member, :guest, :awaiting, user: awaiting_user, source: project, member_role: member_role)
          end

          let(:user) { awaiting_user }

          it 'does not grant custom role abilities to the awaiting member' do
            expect(result).to eq({ project.id => [], project_2.id => [] })
          end
        end

        context 'when user has custom role that enables custom permission outside of project hierarchy' do
          let_it_be(:sub_group_2) { create(:group, :private, parent: group) }
          let_it_be_with_reload(:sub_group_2_member) do
            create(:group_member, :guest, user: user, source: sub_group_2, member_role: member_role)
          end

          it 'ignores custom role outside of project hierarchy' do
            expect(result).to eq({ project.id => [], project_2.id => [] })
          end
        end
      end
    end
  end

  MemberRole.all_customizable_project_permissions.each do |ability|
    it_behaves_like 'custom roles', ability
  end

  shared_examples 'parity between project_authorizations and memberships' do
    let_it_be(:member_role) { create_member_role(group, :read_code) }

    it 'gives a Minimal Access group member their custom role' do
      minimal_user = create(:user)
      member = create(:group_member, :minimal_access, user: minimal_user, source: group)
      member.update_column(:member_role_id, member_role.id)
      # The SQL path reads user_group_member_roles, which is normally filled asynchronously.
      Authz::UserGroupMemberRoles::UpdateForGroupService.new(member.reload).execute

      result = described_class.new(projects: [project], user: minimal_user).execute

      expect(result[project.id]).to include(:read_code)
    end

    it 'gives no custom role through a project share' do
      shared_user = create(:user)
      invited = create(:group)
      invited.add_guest(shared_user)
      create(:project_group_link, project: project, group: invited, group_access: Gitlab::Access::GUEST)
        .update_column(:member_role_id, member_role.id)

      expect(described_class.new(projects: [project], user: shared_user).execute).to eq(project.id => [])
    end

    it 'gives no custom role on a personal project' do
      owner = create(:user, :with_namespace)
      personal_project = create(:project, namespace: owner.namespace)

      expect(described_class.new(projects: [personal_project], user: owner).execute).to eq(personal_project.id => [])
    end

    # On SaaS each root group's plan decides the license, so each project must be checked against its own root.
    it 'gives custom roles only on projects under the licensed root group', :saas do
      stub_saas_features(gitlab_com_subscriptions: true)
      stub_ee_application_setting(should_check_namespace_plan: true)
      licensed_project = create(:project, :private, group: create(:group_with_plan, plan: :ultimate_plan))
      unlicensed_project = create(:project, :private, group: create(:group_with_plan, plan: :free_plan))
      [licensed_project, unlicensed_project].each do |root_project|
        role = create_member_role(root_project.root_namespace, :read_code)
        create(:project_member, :guest, user: user, source: root_project, member_role: role)
      end

      result = described_class.new(projects: [unlicensed_project, licensed_project], user: user).execute

      expect(result).to eq(licensed_project.id => expected_project_abilities(:read_code), unlicensed_project.id => [])
    end
  end

  it_behaves_like 'parity between project_authorizations and memberships'

  context 'when resolve_project_access_from_memberships is disabled' do
    before do
      stub_feature_flags(resolve_project_access_from_memberships: false)
    end

    it_behaves_like 'custom roles', MemberRole.all_customizable_project_permissions.first
    it_behaves_like 'parity between project_authorizations and memberships'

    context "when project's parent group invites a group with a custom role" do
      let(:source) { project }

      include_context 'with multiple users in a group with custom roles'

      it_behaves_like 'returns expected member role abilities'
    end

    context "when project's parent group invites multiple groups with a custom role" do
      let(:source) { project }

      include_context 'with a user in multiple groups with custom role'

      it_behaves_like 'returns expected member role abilities for the user'
    end
  end

  context "when project's parent group invites a group with a custom role" do
    let(:source) { project }

    include_context 'with multiple users in a group with custom roles'

    it_behaves_like 'returns expected member role abilities'

    context 'when an array of project IDs is passed instead of objects' do
      let(:projects_list) { [project.id, project_2.id] }

      it_behaves_like 'returns expected member role abilities'
    end
  end

  context "when project's parent group invites multiple groups with a custom role" do
    let(:source) { project }

    include_context 'with a user in multiple groups with custom role'

    it_behaves_like 'returns expected member role abilities for the user'

    context 'when an array of project IDs is passed instead of objects' do
      let(:projects_list) { [project.id, project_2.id] }

      it_behaves_like 'returns expected member role abilities for the user'
    end
  end
end
