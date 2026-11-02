# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GroupsFinder, feature_category: :groups_and_projects do
  include AdminModeHelper

  describe '#execute' do
    let_it_be(:user) { create(:user) }
    let_it_be(:group_with_wiki) { create(:group, :wiki_repo) }
    let_it_be(:group_without_wiki) { create(:group) }

    subject(:execute) { described_class.new(user, params).execute }

    before_all do
      group_with_wiki.add_developer(user)
      group_without_wiki.add_developer(user)
    end

    context 'when repository storage name is given' do
      let(:params) { { repository_storage: group_with_wiki.repository_storage } }

      it 'filters by the repository storage name' do
        expect(subject).to eq([group_with_wiki])
      end
    end

    context 'when repository storage name is not given' do
      let(:params) { {} }

      it 'returns all groups' do
        expect(subject).to match_array([group_with_wiki, group_without_wiki])
      end
    end

    context 'with Knowledge Graph enabled top-level groups', feature_category: :knowledge_graph do
      let_it_be(:enabled_group) { create(:group, :private, name: 'enabled-group') }
      let_it_be(:enabled_parent_group) { create(:group, :private, name: 'enabled-parent-group') }
      let_it_be(:enabled_subgroup) { create(:group, :private, parent: enabled_parent_group) }
      let_it_be(:disabled_group) { create(:group, :private, name: 'disabled-group') }
      let_it_be(:project_member_group) { create(:group, :private, name: 'project-member-group') }
      let_it_be(:guest_group) { create(:group, :private, name: 'guest-group') }
      let_it_be(:shared_group) { create(:group, :private, name: 'shared-group') }
      let_it_be(:sharing_group) { create(:group, :private, name: 'sharing-group') }

      let(:params) do
        {
          all_available: false,
          top_level_only: true,
          with_knowledge_graph_enabled: true
        }
      end

      before_all do
        create(:knowledge_graph_enabled_namespace, namespace: enabled_group)
        create(:knowledge_graph_enabled_namespace, namespace: enabled_parent_group)
        enabled_group.add_developer(user)
        enabled_subgroup.add_developer(user)
        disabled_group.add_developer(user)

        [project_member_group, guest_group].each do |group|
          create(:knowledge_graph_enabled_namespace, namespace: group)
        end
        create(:project, group: project_member_group).add_developer(user)
        guest_group.add_guest(user)

        create(:knowledge_graph_enabled_namespace, namespace: shared_group)
        create(:group_group_link, shared_group: shared_group, shared_with_group: sharing_group,
          group_access: ::Gitlab::Access::REPORTER)
        sharing_group.add_reporter(user)
      end

      it 'returns enabled root groups from Reporter+ group, subgroup, and shared group memberships' do
        expect(execute).to contain_exactly(enabled_group, enabled_parent_group, shared_group)
      end

      context 'when the Orbit promo access gate is on for a root group without Orbit access', :saas do
        before do
          stub_saas_features(gitlab_com_subscriptions: true)
          stub_feature_flags(orbit_promo_access_gate: enabled_group)
        end

        it 'does not return the gated root group' do
          expect(execute).to contain_exactly(enabled_parent_group, shared_group)
        end
      end
    end

    context 'when filtering by Duo Agent Platform', feature_category: :value_stream_management do
      let_it_be(:enabled_root) { create(:group, :private) }
      let_it_be(:enabled_subgroup) { create(:group, :private, parent: enabled_root) }
      let_it_be(:disabled_root) { create(:group, :private) }
      let_it_be(:disabled_subgroup) { create(:group, :private, parent: disabled_root) }

      let(:params) { { all_available: false, with_duo_agent_platform_enabled: true } }

      before_all do
        create(:namespace_ai_settings, namespace: enabled_root, duo_agent_platform_enabled: true)
        create(:namespace_ai_settings, namespace: disabled_root, duo_agent_platform_enabled: false)
        # Only the top-level group's setting counts, so these opposite subgroup values are ignored.
        create(:namespace_ai_settings, namespace: enabled_subgroup, duo_agent_platform_enabled: false)
        create(:namespace_ai_settings, namespace: disabled_subgroup, duo_agent_platform_enabled: true)

        [enabled_root, enabled_subgroup, disabled_root, disabled_subgroup].each { |group| group.add_developer(user) }
      end

      context 'when on GitLab.com', :saas_gitlab_com_subscriptions do
        it 'returns groups whose top-level group has not turned Duo Agent Platform off' do
          expect(execute).to contain_exactly(group_with_wiki, group_without_wiki, enabled_root, enabled_subgroup)
        end

        context 'with top-level groups only' do
          let(:params) { super().merge(top_level_only: true) }

          it 'returns only the enabled top-level groups' do
            expect(execute).to contain_exactly(group_with_wiki, group_without_wiki, enabled_root)
          end
        end

        context 'when with_duo_agent_platform_enabled is false' do
          let(:params) { super().merge(with_duo_agent_platform_enabled: false) }

          it 'does not filter' do
            expect(execute).to contain_exactly(
              group_with_wiki, group_without_wiki, enabled_root, enabled_subgroup, disabled_root, disabled_subgroup
            )
          end
        end
      end

      context 'when on a self-managed instance' do
        include_context 'with current_organization setting'

        before do
          ::Ai::Setting.for_organization(current_organization).update!(duo_agent_platform_enabled: instance_enabled)
        end

        context 'when Duo Agent Platform is on for the instance' do
          let(:instance_enabled) { true }

          it 'does not filter' do
            expect(execute).to contain_exactly(
              group_with_wiki, group_without_wiki, enabled_root, enabled_subgroup, disabled_root, disabled_subgroup
            )
          end
        end

        context 'when Duo Agent Platform is off for the instance' do
          let(:instance_enabled) { false }

          it 'returns no groups' do
            expect(execute).to be_empty
          end
        end
      end
    end

    it_behaves_like 'groups finder with SAML session filtering' do
      let(:finder) { described_class.new(current_user, params) }
    end

    context 'when user has custom admin role with read_admin_groups permission' do
      let_it_be(:role) { create(:admin_member_role, :read_admin_groups, user: user) }

      let_it_be(:authorized_groups) { [group_with_wiki, group_without_wiki] }
      let_it_be(:unauthorized_group) { create(:group, :private) } # group the user is not a member of
      let_it_be(:internal_group) { create(:group, :internal) }
      let_it_be(:public_group) { create(:group, :public) }

      let(:params) { {} }

      before do
        stub_licensed_features(custom_roles: true)
        enable_admin_mode!(user)
      end

      it 'returns all groups' do
        expect(execute).to match_array([*authorized_groups, unauthorized_group, internal_group, public_group])
      end
    end
  end
end
