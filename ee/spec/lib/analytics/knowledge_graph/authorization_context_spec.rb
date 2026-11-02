# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::KnowledgeGraph::AuthorizationContext, feature_category: :knowledge_graph do
  let_it_be(:user) { create(:user) }
  let_it_be(:admin) { create(:admin) }
  let_it_be(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }
  let_it_be(:project) { create(:project, namespace: subgroup) }
  let_it_be(:enabled_namespace) { create(:knowledge_graph_enabled_namespace, namespace: root_group) }

  describe '#admin_user?' do
    context 'with regular user' do
      subject(:context) { described_class.new(user) }

      it 'returns false' do
        expect(context.admin_user?).to be(false)
      end
    end

    context 'with admin user' do
      subject(:context) { described_class.new(admin) }

      before do
        allow(admin).to receive(:can_read_all_resources?).and_return(true)
      end

      it 'returns true' do
        expect(context.admin_user?).to be(true)
      end
    end

    context 'with nil user' do
      subject(:context) { described_class.new(nil) }

      it 'returns false' do
        expect(context.admin_user?).to be(false)
      end
    end
  end

  describe '#anonymous_user?' do
    context 'with user' do
      subject(:context) { described_class.new(user) }

      it 'returns false' do
        expect(context.anonymous_user?).to be(false)
      end
    end

    context 'with nil user' do
      subject(:context) { described_class.new(nil) }

      it 'returns true' do
        expect(context.anonymous_user?).to be(true)
      end
    end
  end

  describe '#reporter_plus_traversal_ids' do
    subject(:context) { described_class.new(user) }

    # Helper: extract just the path strings, ignoring role tags.
    def paths_only(result)
      result[:group_traversal_ids].map { |entry| entry.fetch('path') }
    end

    def path_to_roles(result)
      result[:group_traversal_ids].to_h { |entry| [entry.fetch('path'), entry.fetch('access_levels')] }
    end

    context 'on SaaS with the Orbit promo access gate' do
      let(:root_prefix) { "#{root_group.organization_id}/#{root_group.id}/" }

      before_all do
        root_group.add_reporter(user)
      end

      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'leaves out an enabled root group without the add-on or a trial' do
        expect(paths_only(context.reporter_plus_traversal_ids)).to be_empty
      end

      it 'includes an enabled root group with an active orbit_promo add-on' do
        create(:gitlab_subscription_add_on_purchase, :orbit_promo, namespace: root_group)

        expect(paths_only(context.reporter_plus_traversal_ids)).to include(root_prefix)
      end
    end

    context 'when user has reporter access to a root group' do
      before_all do
        root_group.add_reporter(user)
      end

      it 'returns hash with group_traversal_ids containing role-tagged tuples' do
        result = context.reporter_plus_traversal_ids

        expect(result).to be_a(Hash)
        expect(result).to have_key(:group_traversal_ids)
        expect(result[:group_traversal_ids]).not_to be_empty
        expect(result[:group_traversal_ids]).to all(include('path', 'access_levels'))
        expect(result[:group_traversal_ids].flat_map(&:keys)).not_to include('access_level')
      end

      it 'tags each entry with integer access_levels matching Gitlab::Access' do
        result = context.reporter_plus_traversal_ids

        access_levels = result[:group_traversal_ids].map { |e| e.fetch('access_levels') }
        expect(access_levels).to all(be_an(Array))
        expect(access_levels.flatten).to all(be_a(Integer))
      end

      it 'marks reporter-only paths at exactly Gitlab::Access::REPORTER' do
        result = context.reporter_plus_traversal_ids

        root_prefix = "#{root_group.organization_id}/#{root_group.id}/"
        expect(path_to_roles(result)[root_prefix]).to eq([Gitlab::Access::REPORTER])
      end

      it 'formats traversal_ids as slash-separated with trailing slash' do
        paths = paths_only(context.reporter_plus_traversal_ids)

        expect(paths).to all(end_with('/'))
        expect(paths).to all(match(%r{\A[\d/]+\z}))
      end

      it 'prefixes traversal_ids with organization_id' do
        paths = paths_only(context.reporter_plus_traversal_ids)

        expect(paths).to all(start_with("#{root_group.organization_id}/"))
      end

      it 'compacts parent and subgroup into a single parent prefix via trie' do
        paths = paths_only(context.reporter_plus_traversal_ids)

        root_prefix = "#{root_group.organization_id}/#{root_group.id}/"
        subgroup_prefix = "#{root_group.organization_id}/#{subgroup.traversal_ids.join('/')}/"

        expect(paths).to include(root_prefix)
        expect(paths).not_to include(subgroup_prefix)
      end

      it 'observes traversal ID count metric' do
        expect(Gitlab::Metrics::KnowledgeGraph::TraversalIds).to receive(:observe_traversal_ids_count)
          .with(a_value > 0).at_least(:once)

        context.reporter_plus_traversal_ids
      end

      it 'memoizes the result within the same instance' do
        control = ActiveRecord::QueryRecorder.new { context.reporter_plus_traversal_ids }
        cached = ActiveRecord::QueryRecorder.new { context.reporter_plus_traversal_ids }

        expect(cached.count).to eq(0)
        expect(control.count).to be > 0
      end
    end

    context 'when user has security manager access on one path and reporter on another' do
      let_it_be(:reporter_group) { create(:group) }
      let_it_be(:sec_manager_group) { create(:group) }
      let_it_be(:mixed_user) { create(:user) }

      subject(:context) { described_class.new(mixed_user) }

      before_all do
        create(:knowledge_graph_enabled_namespace, namespace: reporter_group)
        create(:knowledge_graph_enabled_namespace, namespace: sec_manager_group)
        reporter_group.add_reporter(mixed_user)
        sec_manager_group.add_security_manager(mixed_user)
      end

      it 'tags the security-manager path with SECURITY_MANAGER and the reporter path with REPORTER' do
        result = context.reporter_plus_traversal_ids

        reporter_prefix = "#{reporter_group.organization_id}/#{reporter_group.id}/"
        sec_manager_prefix = "#{sec_manager_group.organization_id}/#{sec_manager_group.id}/"

        mapping = path_to_roles(result)
        expect(mapping[reporter_prefix]).to eq([Gitlab::Access::REPORTER])
        expect(mapping[sec_manager_prefix]).to eq([Gitlab::Access::SECURITY_MANAGER])
      end
    end

    context 'when user has developer access (above security manager)' do
      let_it_be(:developer_group) { create(:group) }
      let_it_be(:dev_user) { create(:user) }

      subject(:context) { described_class.new(dev_user) }

      before_all do
        create(:knowledge_graph_enabled_namespace, namespace: developer_group)
        developer_group.add_developer(dev_user)
      end

      it 'tags the path with the raw Developer access level' do
        result = context.reporter_plus_traversal_ids

        prefix = "#{developer_group.organization_id}/#{developer_group.id}/"
        expect(path_to_roles(result)[prefix]).to eq([Gitlab::Access::DEVELOPER])
      end
    end

    context 'when user has access via a GroupGroupLink' do
      # The shared group is tagged at LEAST(link_access, direct_access_on_sharer).
      # GroupGroupLink.group_access is restricted to [Guest, Planner, Reporter,
      # Developer, Maintainer, Owner].
      let_it_be(:shared_group) { create(:group) }
      let_it_be(:shared_with_group) { create(:group) }

      context 'when direct access on the sharer exceeds the link level' do
        let_it_be(:dev_on_sharer_user) { create(:user) }

        subject(:context) { described_class.new(dev_on_sharer_user) }

        before_all do
          create(:knowledge_graph_enabled_namespace, namespace: shared_group)
          create(:group_group_link, shared_group: shared_group, shared_with_group: shared_with_group,
            group_access: Gitlab::Access::MAINTAINER)
          shared_with_group.add_developer(dev_on_sharer_user)
        end

        it 'tags the shared group at the link cap (LEAST(MAINTAINER, DEVELOPER) = DEVELOPER)' do
          result = context.reporter_plus_traversal_ids

          shared_prefix = "#{shared_group.organization_id}/#{shared_group.id}/"
          expect(path_to_roles(result)[shared_prefix]).to eq([Gitlab::Access::DEVELOPER])
        end
      end

      context 'when direct access on the sharer is below the link level' do
        let_it_be(:reporter_on_sharer_user) { create(:user) }
        let_it_be(:other_shared) { create(:group) }
        let_it_be(:other_sharer) { create(:group) }

        subject(:context) { described_class.new(reporter_on_sharer_user) }

        before_all do
          create(:knowledge_graph_enabled_namespace, namespace: other_shared)
          create(:group_group_link, shared_group: other_shared, shared_with_group: other_sharer,
            group_access: Gitlab::Access::MAINTAINER)
          other_sharer.add_reporter(reporter_on_sharer_user)
        end

        it 'tags the shared group at the direct cap (LEAST(MAINTAINER, REPORTER) = REPORTER)' do
          result = context.reporter_plus_traversal_ids

          shared_prefix = "#{other_shared.organization_id}/#{other_shared.id}/"
          expect(path_to_roles(result)[shared_prefix]).to eq([Gitlab::Access::REPORTER])
        end
      end
    end

    context 'when user has security manager access on the same path that also yields reporter rows' do
      let_it_be(:promoted_group) { create(:group) }
      let_it_be(:promoted_user) { create(:user) }

      subject(:context) { described_class.new(promoted_user) }

      before_all do
        create(:knowledge_graph_enabled_namespace, namespace: promoted_group)
        promoted_group.add_security_manager(promoted_user)
      end

      it 'keeps the higher role on that path' do
        result = context.reporter_plus_traversal_ids

        promoted_prefix = "#{promoted_group.organization_id}/#{promoted_group.id}/"
        expect(path_to_roles(result)[promoted_prefix]).to eq([Gitlab::Access::SECURITY_MANAGER])
      end
    end

    context 'when user has access to a subgroup but not the parent' do
      let_it_be(:other_root) { create(:group) }
      let_it_be(:other_sub) { create(:group, parent: other_root) }
      let_it_be(:leaf_user) { create(:user) }

      subject(:context) { described_class.new(leaf_user) }

      before_all do
        create(:knowledge_graph_enabled_namespace, namespace: other_root)
        other_sub.add_reporter(leaf_user)
      end

      it 'returns the subgroup traversal path, not the parent' do
        paths = paths_only(context.reporter_plus_traversal_ids)

        sub_prefix = "#{other_sub.organization_id}/#{other_sub.traversal_ids.join('/')}/"
        root_only = "#{other_root.organization_id}/#{other_root.id}/"

        expect(paths).to include(sub_prefix)
        expect(paths).not_to include(root_only)
      end
    end

    context 'when user has access to multiple unrelated groups' do
      let_it_be(:group_a) { create(:group) }
      let_it_be(:group_b) { create(:group) }
      let_it_be(:multi_user) { create(:user) }

      subject(:context) { described_class.new(multi_user) }

      before_all do
        create(:knowledge_graph_enabled_namespace, namespace: group_a)
        create(:knowledge_graph_enabled_namespace, namespace: group_b)
        group_a.add_reporter(multi_user)
        group_b.add_reporter(multi_user)
      end

      it 'returns separate traversal paths for each group' do
        paths = paths_only(context.reporter_plus_traversal_ids)

        expect(paths.size).to be >= 2
        expect(paths).to include("#{group_a.organization_id}/#{group_a.id}/")
        expect(paths).to include("#{group_b.organization_id}/#{group_b.id}/")
      end
    end

    context 'when user has access to both parent and child' do
      let_it_be(:parent) { create(:group) }
      let_it_be(:child) { create(:group, parent: parent) }
      let_it_be(:both_user) { create(:user) }

      subject(:context) { described_class.new(both_user) }

      before_all do
        create(:knowledge_graph_enabled_namespace, namespace: parent)
        parent.add_reporter(both_user)
        child.add_reporter(both_user)
      end

      it 'deduplicates via trie to parent prefix only' do
        paths = paths_only(context.reporter_plus_traversal_ids)
        parent_prefix = "#{parent.organization_id}/#{parent.id}/"
        child_prefix = "#{parent.organization_id}/#{child.traversal_ids.join('/')}/"

        expect(paths).to include(parent_prefix)
        expect(paths).not_to include(child_prefix)
      end
    end

    context 'when user has access to deeply nested group' do
      let_it_be(:level1) { create(:group) }
      let_it_be(:level2) { create(:group, parent: level1) }
      let_it_be(:level3) { create(:group, parent: level2) }
      let_it_be(:deep_user) { create(:user) }

      subject(:context) { described_class.new(deep_user) }

      before_all do
        create(:knowledge_graph_enabled_namespace, namespace: level1)
        level3.add_reporter(deep_user)
      end

      it 'returns the full traversal path for the leaf group' do
        paths = paths_only(context.reporter_plus_traversal_ids)

        expected = "#{level3.organization_id}/#{level3.traversal_ids.join('/')}/"
        expect(paths).to include(expected)
        expect(paths.size).to eq(1)
      end
    end

    context 'when user has reporter access to enabled and non-enabled roots' do
      let_it_be(:enabled_group) { create(:group) }
      let_it_be(:non_enabled_group) { create(:group) }
      let_it_be(:partial_user) { create(:user) }

      subject(:context) { described_class.new(partial_user) }

      before_all do
        create(:knowledge_graph_enabled_namespace, namespace: enabled_group)
        enabled_group.add_reporter(partial_user)
        non_enabled_group.add_reporter(partial_user)
      end

      it 'includes only paths under enabled root namespaces' do
        paths = paths_only(context.reporter_plus_traversal_ids)

        expect(paths).to contain_exactly("#{enabled_group.organization_id}/#{enabled_group.id}/")
      end
    end

    context 'when user has several paths with different access levels' do
      let_it_be(:reporter_group) { create(:group) }
      let_it_be(:maintainer_subgroup) { create(:group, parent: reporter_group) }
      let_it_be(:sec_manager_group) { create(:group) }
      let_it_be(:payload_user) do
        create(:user, reporter_of: reporter_group, maintainer_of: maintainer_subgroup)
      end

      subject(:context) { described_class.new(payload_user) }

      before_all do
        create(:knowledge_graph_enabled_namespace, namespace: reporter_group)
        create(:knowledge_graph_enabled_namespace, namespace: sec_manager_group)
        sec_manager_group.add_security_manager(payload_user)
      end

      it 'returns the exact payload, sorted by path' do
        expected = [
          { 'path' => reporter_group.traversal_path(with_organization: true),
            'access_levels' => [Gitlab::Access::REPORTER] },
          { 'path' => maintainer_subgroup.traversal_path(with_organization: true),
            'access_levels' => [Gitlab::Access::MAINTAINER] },
          { 'path' => sec_manager_group.traversal_path(with_organization: true),
            'access_levels' => [Gitlab::Access::SECURITY_MANAGER] }
        ].sort_by { |entry| entry['path'] }

        expect(context.reporter_plus_traversal_ids).to eq({ group_traversal_ids: expected })
      end

      it 'stops at the limit of member group entries' do
        stub_const('Analytics::Orbit::MemberGroups::MAX_ENTRIES', 2)

        expect(paths_only(context.reporter_plus_traversal_ids)).to eq(
          [reporter_group, maintainer_subgroup, sec_manager_group]
            .map { |group| group.traversal_path(with_organization: true) }.sort.first(2)
        )
      end
    end

    context 'when user has no group access' do
      let_it_be(:user_without_groups) { create(:user) }

      subject(:context) { described_class.new(user_without_groups) }

      it 'returns hash with empty group_traversal_ids' do
        result = context.reporter_plus_traversal_ids

        expect(result).to eq({ group_traversal_ids: [] })
      end
    end

    context 'when user has guest access only' do
      let_it_be(:guest_user) { create(:user) }
      let_it_be(:guest_group) { create(:group) }

      before_all do
        create(:knowledge_graph_enabled_namespace, namespace: guest_group)
        guest_group.add_guest(guest_user)
      end

      subject(:context) { described_class.new(guest_user) }

      it 'does not include guest-only groups' do
        result = context.reporter_plus_traversal_ids

        expect(result).to eq({ group_traversal_ids: [] })
      end
    end

    context 'with nil user' do
      subject(:context) { described_class.new(nil) }

      it 'returns hash with empty group_traversal_ids' do
        result = context.reporter_plus_traversal_ids

        expect(result).to eq({ group_traversal_ids: [] })
      end
    end
  end

  describe '#has_enabled_namespaces?' do
    context 'with admin user' do
      subject(:context) { described_class.new(admin) }

      before do
        allow(admin).to receive(:can_read_all_resources?).and_return(true)
      end

      it 'returns true regardless of enabled namespaces' do
        expect(context.has_enabled_namespaces?).to be(true)
      end
    end

    context 'with nil user' do
      subject(:context) { described_class.new(nil) }

      it 'returns false' do
        expect(context.has_enabled_namespaces?).to be(false)
      end
    end

    context 'with user who has groups in enabled namespaces' do
      subject(:context) { described_class.new(user) }

      before_all do
        root_group.add_reporter(user)
      end

      it 'returns true' do
        expect(context.has_enabled_namespaces?).to be(true)
      end

      context 'on SaaS with the Orbit promo access gate' do
        before do
          stub_saas_features(gitlab_com_subscriptions: true)
        end

        it 'returns false when the enabled group has no add-on or trial' do
          expect(context.has_enabled_namespaces?).to be(false)
        end
      end
    end

    context 'with user who has no groups in enabled namespaces' do
      let_it_be(:excluded_user) { create(:user) }
      let_it_be(:non_enabled_group) { create(:group) }

      before_all do
        non_enabled_group.add_reporter(excluded_user)
      end

      subject(:context) { described_class.new(excluded_user) }

      it 'returns false' do
        expect(context.has_enabled_namespaces?).to be(false)
      end
    end

    context 'with user who has no reporter+ group memberships' do
      let_it_be(:groupless_user) { create(:user) }

      subject(:context) { described_class.new(groupless_user) }

      it 'returns false without querying EnabledNamespace' do
        expect(Analytics::KnowledgeGraph::EnabledNamespace).not_to receive(:for_root_namespace_id)

        expect(context.has_enabled_namespaces?).to be(false)
      end
    end

    context 'with user who has reporter access only on a subgroup of an enabled root' do
      let_it_be(:enabled_root) { create(:group) }
      let_it_be(:child_group) { create(:group, parent: enabled_root) }
      let_it_be(:subgroup_user) { create(:user) }

      let_it_be(:enabled_root_ns) { create(:knowledge_graph_enabled_namespace, namespace: enabled_root) }

      before_all do
        child_group.add_reporter(subgroup_user)
      end

      subject(:context) { described_class.new(subgroup_user) }

      it 'returns true' do
        expect(context.has_enabled_namespaces?).to be(true)
      end
    end

    context 'with user whose only reporter+ access to an enabled namespace is via group_group_link' do
      let_it_be(:enabled_root) { create(:group) }
      let_it_be(:other_group) { create(:group) }
      let_it_be(:linked_user) { create(:user) }

      let_it_be(:enabled_ns) { create(:knowledge_graph_enabled_namespace, namespace: enabled_root) }

      before_all do
        create(:group_group_link, shared_group: enabled_root, shared_with_group: other_group,
          group_access: Gitlab::Access::REPORTER)
        other_group.add_reporter(linked_user)
      end

      subject(:context) { described_class.new(linked_user) }

      it 'returns true' do
        expect(context.has_enabled_namespaces?).to be(true)
      end
    end

    context 'when group_group_link grants only guest access to an enabled namespace' do
      let_it_be(:enabled_root) { create(:group) }
      let_it_be(:other_group) { create(:group) }
      let_it_be(:guest_link_user) { create(:user) }

      let_it_be(:enabled_ns) { create(:knowledge_graph_enabled_namespace, namespace: enabled_root) }

      before_all do
        create(:group_group_link, shared_group: enabled_root, shared_with_group: other_group,
          group_access: Gitlab::Access::GUEST)
        other_group.add_reporter(guest_link_user)
      end

      subject(:context) { described_class.new(guest_link_user) }

      it 'returns false' do
        expect(context.has_enabled_namespaces?).to be(false)
      end
    end
  end

  describe '.for' do
    context 'with a request store', :request_store do
      it 'returns the same context for the same user' do
        first_context = described_class.for(user)

        expect(described_class.for(user)).to be(first_context)
      end

      it 'returns a different context for a different user' do
        expect(described_class.for(user)).not_to be(described_class.for(admin))
      end

      it 'returns the same context for an anonymous user' do
        first_context = described_class.for(nil)

        expect(described_class.for(nil)).to be(first_context)
      end
    end

    it 'returns a new context without a request store' do
      first_context = described_class.for(user)

      expect(described_class.for(user)).not_to be(first_context)
    end
  end

  describe '#enabled_root_namespace?' do
    let_it_be(:reporter) { create(:user, reporter_of: subgroup) }
    let_it_be(:disabled_root) { create(:group) }

    it 'is true for a Reporter in a group under an enabled root' do
      expect(described_class.new(reporter).enabled_root_namespace?(root_group.id)).to be(true)
    end

    it 'is false for a Guest under that root' do
      guest = create(:user, guest_of: subgroup)

      expect(described_class.new(guest).enabled_root_namespace?(root_group.id)).to be(false)
    end

    it 'is false for a root where the member is a Reporter but Orbit is off' do
      member = create(:user, reporter_of: disabled_root)

      expect(described_class.new(member).enabled_root_namespace?(disabled_root.id)).to be(false)
    end

    context 'with an administrator who can read all resources' do
      subject(:context) { described_class.new(admin) }

      before do
        allow(admin).to receive(:can_read_all_resources?).and_return(true)
      end

      it 'is true for an enabled root without membership' do
        expect(context.enabled_root_namespace?(root_group.id)).to be(true)
      end

      it 'is false for a root where Orbit is off' do
        expect(context.enabled_root_namespace?(disabled_root.id)).to be(false)
      end

      it 'is false for an enabled root that the promo gate does not entitle' do
        stub_saas_features(gitlab_com_subscriptions: true)

        expect(context.enabled_root_namespace?(root_group.id)).to be(false)
      end
    end
  end

  describe '#traversal_paths_in_scope' do
    let_it_be(:other_group) { create(:group) }
    let_it_be(:reporter) { create(:user, reporter_of: root_group, guest_of: other_group) }

    let(:subgroup_path) { subgroup.traversal_path(with_organization: true) }
    let(:project_path) { project.project_namespace.traversal_path(with_organization: true) }
    let(:other_group_path) { other_group.traversal_path(with_organization: true) }
    let(:paths) { [subgroup_path, project_path, other_group_path] }

    it 'returns the paths under an enabled root where the user is a Reporter' do
      paths_in_scope = described_class.new(reporter).traversal_paths_in_scope(paths)

      expect(paths_in_scope).to match_array([subgroup_path, project_path])
    end

    it 'returns all paths for an admin' do
      allow(admin).to receive(:can_read_all_resources?).and_return(true)

      expect(described_class.new(admin).traversal_paths_in_scope(paths)).to eq(paths)
    end

    it 'returns no paths for an anonymous user' do
      expect(described_class.new(nil).traversal_paths_in_scope(paths)).to be_empty
    end
  end
end
