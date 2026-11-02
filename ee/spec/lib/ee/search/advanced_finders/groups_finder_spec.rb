# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::AdvancedFinders::GroupsFinder, :elastic, :sidekiq_inline,
  feature_category: :global_search do
  let_it_be(:user) { create(:user) }
  let_it_be(:parent_group) { create(:group, :public, name: 'test-parent') }
  let_it_be(:subgroup) { create(:group, :public, parent: parent_group, name: 'test-child') }
  let_it_be(:other_group) { create(:group, :public, name: 'test-other') }

  let(:params) { { search: 'test' } }

  subject(:finder) { described_class.new(user, params) }

  before do
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
    ::Elastic::ProcessInitialBookkeepingService.track!(parent_group, subgroup, other_group)
    ensure_elasticsearch_index!
  end

  describe '#use_elasticsearch_finder?' do
    it 'is true when every precondition holds' do
      expect(finder.use_elasticsearch_finder?).to be(true)
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(advanced_groups_finder_elasticsearch: false)
      end

      it 'is false' do
        expect(finder.use_elasticsearch_finder?).to be(false)
      end
    end

    context 'when advanced search is disabled' do
      before do
        stub_ee_application_setting(elasticsearch_search: false)
      end

      it 'is false' do
        expect(finder.use_elasticsearch_finder?).to be(false)
      end
    end

    context 'when indexing is paused' do
      before do
        stub_ee_application_setting(elasticsearch_pause_indexing: true)
      end

      it 'is false' do
        expect(finder.use_elasticsearch_finder?).to be(false)
      end
    end

    context 'when the backfill migration has not finished' do
      before do
        set_elasticsearch_migration_to(:backfill_groups_to_elasticsearch, including: false)
      end

      it 'is false' do
        expect(finder.use_elasticsearch_finder?).to be(false)
      end
    end

    describe 'filter allowlist' do
      where(:params, :supported) do
        [
          [{ search: 'test' }, true],
          # The index stores the group's own archived flag; GroupsFinder is ancestor-aware.
          [{ search: 'test', archived: true }, false],
          [{ search: 'test', active: true }, true],
          [{ search: 'test', active: false }, true],
          [{ search: 'test', archived: false }, false],
          [{ search: 'test', include_parent_descendants: true }, true],
          [{ search: 'test', ids: [1] }, true],
          [{ search: 'test', exclude_group_ids: [1] }, true],
          [{ search: 'test', filter_group_ids: [1] }, true],
          [{ search: 'test', sort: 'created_desc' }, true],
          [{ search: 'test', visibility: 'public' }, true],
          [{ search: 'test', min_access_level: Gitlab::Access::DEVELOPER }, false],
          [{ search: 'test', all_available: false }, true],
          [{ search: 'test', include_parent_shared_groups: true }, false],
          [{ search: 'test', custom_attributes: { foo: 'bar' } }, false]
        ]
      end

      with_them do
        it 'only claims the query when every filter is expressible in Elasticsearch' do
          expect(described_class.new(user, params).use_elasticsearch_finder?).to be(supported)
        end
      end
    end

    # An unfiltered listing always exceeds RESULT_LIMIT on a real instance, so #execute
    # would discard the hits. Declining up front avoids the wasted round trip.
    describe 'without a search term' do
      where(:params) { [{}, { search: '' }, { search: nil }, { include_parent_descendants: true }] }

      with_them do
        it 'is false' do
          expect(described_class.new(user, params).use_elasticsearch_finder?).to be(false)
        end
      end
    end

    it 'declines the parent: [nil] shape the REST API sends for top_level_only' do
      finder = described_class.new(user, search: 'test', parent: [nil])

      expect(finder.use_elasticsearch_finder?).to be(false)
    end

    context 'with active, before its backfill has finished' do
      before do
        set_elasticsearch_migration_to(:backfill_active_on_groups, including: false)
      end

      it 'declines, because documents written before the backfill carry no active field' do
        expect(described_class.new(user, search: 'test', active: true).use_elasticsearch_finder?).to be(false)
      end

      it 'stays eligible when active is not requested' do
        expect(described_class.new(user, search: 'test').use_elasticsearch_finder?).to be(true)
      end
    end

    # GET /groups and the GraphQL resolver reach this finder behind a flag that is already
    # at 100%, so without this check they would start filtering active on Elasticsearch the
    # moment the backfill finished.
    context 'when group_children_advanced_finder is disabled' do
      before do
        stub_feature_flags(group_children_advanced_finder: false)
      end

      it 'declines active, leaving those surfaces on PostgreSQL' do
        expect(described_class.new(user, search: 'test', active: true).use_elasticsearch_finder?).to be(false)
      end

      it 'stays eligible when active is not requested' do
        expect(described_class.new(user, search: 'test').use_elasticsearch_finder?).to be(true)
      end
    end

    describe 'params that do not narrow the query' do
      where(:params, :supported) do
        [
          [{ search: 'test', with_statistics: true }, false],
          [{ search: 'test', owned: false }, true],
          [{ search: 'test', owned: true }, false],
          [{ search: 'test', top_level_only: false }, true],
          [{ search: 'test', top_level_only: true }, true],
          [{ search: 'test', include_parent_shared_groups: false }, true],
          [{ search: 'test', include_parent_shared_groups: true }, false],
          [{ search: 'test', filter_expired_saml_session_groups: false }, true],
          [{ search: 'test', filter_expired_saml_session_groups: true }, false],
          [{ search: 'test', with_knowledge_graph_enabled: false }, true],
          [{ search: 'test', with_knowledge_graph_enabled: true }, false],
          [{ search: 'test', with_duo_agent_platform_enabled: false }, true],
          [{ search: 'test', with_duo_agent_platform_enabled: true }, false],
          # GroupsFinder skips a filter whose value is nil, so nil does not narrow.
          [{ search: 'test', active: nil }, true],
          [{ search: 'test', archived: nil }, true],
          # Except where GroupsFinder reads the param with a truthy-default fetch, which
          # makes an explicit nil behave like false rather than like an absent key.
          [{ search: 'test', all_available: nil }, true],
          [{ search: 'test', include_ancestors: nil }, false],
          # A GraphQL request with every default applied.
          [{ search: 'test', with_statistics: false, all_available: true, owned: false,
             top_level_only: false, active: nil, sort: 'name_asc', allow_similarity_sort: true }, true]
        ]
      end

      with_them do
        it 'ignores no-op values and honours real ones' do
          expect(described_class.new(user, params).use_elasticsearch_finder?).to be(supported)
        end
      end
    end

    # Namespaces::GroupsFinder passes ActionController::Parameters through untouched, so
    # the allowlist check has to cope with a non-Enumerable params object.
    describe 'with ActionController::Parameters' do
      it 'reads the params without raising' do
        params = ActionController::Parameters.new(search: 'test')

        expect(described_class.new(user, params).use_elasticsearch_finder?).to be(true)
      end

      it 'still rejects an unsupported filter' do
        params = ActionController::Parameters.new(search: 'test', owned: true)

        expect(described_class.new(user, params).use_elasticsearch_finder?).to be(false)
      end
    end

    describe 'sorting' do
      # Sorting runs in PostgreSQL on the re-hydrated relation, so no sort disqualifies
      # Elasticsearch, including name_asc which the groups index cannot sort on.
      where(:sort) { %w[name_asc name_desc path_asc created_asc updated_desc similarity id_desc] }

      with_them do
        it 'still uses Elasticsearch' do
          expect(described_class.new(user, search: 'test', sort: sort).use_elasticsearch_finder?)
            .to be(true)
        end
      end
    end
  end

  describe '#execute' do
    it 'returns an ActiveRecord::Relation so callers can paginate and chain scopes' do
      expect(finder.execute).to be_a(ActiveRecord::Relation)
      expect(finder.execute.page(1).per(2).size).to eq(2)
    end

    it 'returns the matching groups' do
      expect(finder.execute).to contain_exactly(parent_group, subgroup, other_group)
    end

    it 'preloads routes so rendering full_path does not N+1' do
      expect(finder.execute.first.association(:route)).to be_loaded
    end

    describe 'ordering' do
      let(:params) { { search: 'test', sort: 'name_asc', allow_similarity_sort: true } }

      it 'orders by name even though the index cannot sort on it' do
        expect(finder.execute.map(&:name)).to eq(%w[test-child test-other test-parent])
      end

      it 'matches the order PostgreSQL would have produced' do
        expected = GroupsFinder.new(user, params).execute.map(&:id)

        expect(finder.execute.map(&:id)).to eq(expected)
      end

      context 'with a descending sort' do
        let(:params) { { search: 'test', sort: 'name_desc' } }

        it 'reverses the order' do
          expect(finder.execute.map(&:name)).to eq(%w[test-parent test-other test-child])
        end
      end
    end

    describe 'filtering by visibility' do
      let_it_be(:internal_group) { create(:group, :internal, name: 'test-internal') }
      let_it_be(:private_group) { create(:group, :private, name: 'test-private') }

      before_all do
        private_group.add_developer(user)
      end

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(internal_group, private_group)
        ensure_elasticsearch_index!
      end

      context 'with a single level' do
        let(:params) { { search: 'test', visibility: 'internal' } }

        it 'returns only groups at that level' do
          expect(finder.execute).to contain_exactly(internal_group)
        end
      end

      context 'with several levels' do
        let(:params) { { search: 'test', visibility: %w[internal private] } }

        it 'returns groups at any of them' do
          expect(finder.execute).to contain_exactly(internal_group, private_group)
        end
      end

      context 'without the filter' do
        let(:params) { { search: 'test' } }

        it 'returns every visible group' do
          expect(finder.execute).to include(internal_group, private_group, parent_group)
        end
      end

      it 'matches what PostgreSQL returns' do
        %w[public internal private].each do |level|
          params = { search: 'test', visibility: level }
          expected = GroupsFinder.new(user, params).execute

          expect(described_class.new(user, params).execute).to match_array(expected)
        end
      end

      # An anonymous user can only ever see public groups, so intersecting that with a
      # request for private levels leaves nothing. The filter must return no results
      # rather than being skipped, which is the case an `if levels.blank?` guard in the
      # Elasticsearch filter would get wrong.
      context 'when the user cannot access any of the requested levels' do
        let(:params) { { search: 'test', visibility: 'private' } }

        it 'matches nothing in Elasticsearch rather than ignoring the filter' do
          finder = described_class.new(nil, params)

          expect(finder.use_elasticsearch_finder?).to be(true)
          expect(finder.execute).to be_nil
        end

        it 'matches what PostgreSQL returns' do
          expect(::Namespaces::GroupsFinder.new(nil, params).execute)
            .to match_array(GroupsFinder.new(nil, params).execute)
        end
      end
    end

    # Asserting on use_elasticsearch_finder? alone is not enough: an allowed filter that
    # search_options never maps is ignored by Elasticsearch, which returns a wider set
    # than PostgreSQL without any error. Every entry in ALLOWED_ES_FILTERS needs a case
    # here comparing actual results.
    describe 'parity with GroupsFinder for every allowed filter' do
      let_it_be(:grandchild) { create(:group, :public, parent: subgroup, name: 'test-grandchild') }
      let_it_be(:archived_group) { create(:group, :public, :archived, name: 'test-archived') }

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(grandchild, archived_group)
        ensure_elasticsearch_index!
      end

      # Built inside the example because the params reference let_it_be records.
      def params_for(case_name)
        case case_name
        when :search_only then {}
        when :ids then { ids: [other_group.id] }
        when :exclude_group_ids then { exclude_group_ids: [other_group.id] }
        when :organization then { organization: parent_group.organization }
        # GroupsFinder accepts an id here, and dropping the filter would widen the query.
        when :organization_id then { organization: parent_group.organization.id }
        when :parent_children then { parent: parent_group }
        when :parent_descendants then { parent: parent_group, include_parent_descendants: true }
        when :visibility then { visibility: 'public' }
        when :top_level_only then { top_level_only: true }
        when :filter_group_ids then { filter_group_ids: [other_group.id] }
        when :ids_and_filter_group_ids then { ids: [other_group.id, parent_group.id],
                                              filter_group_ids: [other_group.id] }
        end
      end

      where(:case_name) do
        %i[search_only ids exclude_group_ids organization organization_id parent_children
          parent_descendants visibility top_level_only filter_group_ids
          ids_and_filter_group_ids]
      end

      with_them do
        it 'returns the same groups as GroupsFinder' do
          params = { search: 'test' }.merge(params_for(case_name))
          expected = GroupsFinder.new(user, params).execute

          finder = ::Search::AdvancedFinders::GroupsFinder.new(user, params)

          expect(finder.use_elasticsearch_finder?).to be(true), "#{case_name} unexpectedly fell back"
          expect(finder.execute).to match_array(expected), "#{case_name} diverged"
        end
      end

      it 'is eligible for the subgroup autocomplete param set' do
        finder = described_class.new(user,
          parent: parent_group,
          include_parent_descendants: true,
          include_parent_shared_groups: false,
          search: 'test')

        expect(finder.use_elasticsearch_finder?).to be(true)
        expect(finder.execute).to match_array(
          GroupsFinder.new(user,
            parent: parent_group,
            include_parent_descendants: true,
            include_parent_shared_groups: false,
            search: 'test',
            allow_similarity_sort: true).execute
        )
      end
    end

    context 'with all_available: false' do
      let_it_be(:member_group) { create(:group, :private, name: 'test-member') }
      let_it_be(:member_subgroup) { create(:group, :private, parent: member_group, name: 'test-member-child') }
      let_it_be(:member_membership) { member_group.add_developer(user) }

      let(:params) { { search: 'test', all_available: false } }

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(member_group, member_subgroup)
        ensure_elasticsearch_index!
      end

      it 'is eligible for Elasticsearch' do
        expect(finder.use_elasticsearch_finder?).to be(true)
      end

      it 'returns the same groups as GroupsFinder' do
        expect(finder.execute).to match_array(GroupsFinder.new(user, params).execute)
      end

      it 'excludes public groups the user is not a member of' do
        expect(finder.execute).not_to include(other_group)
      end

      it 'includes descendants of a member group' do
        expect(finder.execute).to include(member_subgroup)
      end

      context 'with a private ancestor of a member group' do
        let_it_be(:private_parent) { create(:group, :private, name: 'test-private-parent') }
        let_it_be(:private_child) do
          create(:group, :private, parent: private_parent, name: 'test-private-child')
        end

        let_it_be(:child_membership) { private_child.add_developer(user) }

        before do
          ::Elastic::ProcessInitialBookkeepingService.track!(private_parent, private_child)
          ensure_elasticsearch_index!
        end

        it 'returns the ancestor the user is not directly a member of' do
          expect(finder.execute).to include(private_parent)
        end

        it 'returns the same groups as GroupsFinder' do
          expect(finder.execute).to match_array(GroupsFinder.new(user, params).execute)
        end
      end

      context 'with a group shared with a member group' do
        let_it_be(:shared_group) { create(:group, :private, name: 'test-shared') }
        let_it_be(:group_link) do
          create(:group_group_link, shared_group: shared_group, shared_with_group: member_group)
        end

        before do
          ::Elastic::ProcessInitialBookkeepingService.track!(shared_group)
          ensure_elasticsearch_index!
        end

        it 'returns the shared group' do
          expect(finder.execute).to include(shared_group)
        end

        it 'returns the same groups as GroupsFinder' do
          expect(finder.execute).to match_array(GroupsFinder.new(user, params).execute)
        end
      end

      # Accepted divergence, pinned rather than guarded. User#authorized_groups builds
      # groups_from_shares without .not_expired, while Search::GroupsFinder applies it, so
      # Elasticsearch returns a strict subset until the daily cleanup removes the link.
      context 'with a group shared at developer access whose share has expired' do
        let_it_be(:expired_shared_group) { create(:group, :private, name: 'test-shared-expired') }
        let_it_be(:expired_link) do
          create(:group_group_link, shared_group: expired_shared_group, shared_with_group: member_group,
            group_access: ::Gitlab::Access::DEVELOPER, expires_at: 1.day.ago)
        end

        before do
          ::Elastic::ProcessInitialBookkeepingService.track!(expired_shared_group)
          ensure_elasticsearch_index!
        end

        it 'stays eligible and omits the group that GroupsFinder still returns' do
          expect(finder.use_elasticsearch_finder?).to be(true)
          expect(finder.execute).not_to include(expired_shared_group)
          expect(GroupsFinder.new(user, params).execute).to include(expired_shared_group)
        end
      end

      context 'with access through a project only' do
        let_it_be(:project_group) { create(:group, :private, name: 'test-project-parent') }
        let_it_be(:project) { create(:project, :private, group: project_group) }
        let_it_be(:project_membership) { project.add_developer(user) }

        before do
          ::Elastic::ProcessInitialBookkeepingService.track!(project_group)
          ensure_elasticsearch_index!
        end

        it 'returns the same groups as GroupsFinder' do
          expect(finder.execute).to match_array(GroupsFinder.new(user, params).execute)
        end
      end

      context 'with a minimal-access membership' do
        let_it_be(:minimal_group) { create(:group, :private, name: 'test-minimal') }
        let_it_be(:minimal_membership) do
          create(:group_member, :minimal_access, group: minimal_group, user: user)
        end

        before do
          stub_licensed_features(minimal_access_role: true)
          ::Elastic::ProcessInitialBookkeepingService.track!(minimal_group)
          ensure_elasticsearch_index!
        end

        it 'falls back rather than returning fewer groups than GroupsFinder' do
          expect(finder.use_elasticsearch_finder?).to be(false)
          expect(GroupsFinder.new(user, params).execute).to include(minimal_group)
        end

        context 'when the licence does not include minimal access' do
          before do
            stub_licensed_features(minimal_access_role: false)
          end

          it 'remains eligible and matches GroupsFinder' do
            expect(finder.use_elasticsearch_finder?).to be(true)
            expect(finder.execute).to match_array(GroupsFinder.new(user, params).execute)
          end
        end
      end

      context 'with a group shared with a member group at minimal access' do
        let_it_be(:shared_at_minimal) { create(:group, :private, name: 'test-shared-minimal') }

        let(:minimal_share) do
          create(:group_group_link, shared_group: shared_at_minimal, shared_with_group: member_group,
            group_access: ::Gitlab::Access::MINIMAL_ACCESS)
        end

        before do
          stub_licensed_features(minimal_access_role: true)
        end

        it 'holds no direct minimal-access membership, so the share is what decides' do
          minimal_share

          expect(user.minimal_access_groups).to be_empty
        end

        it 'falls back rather than dropping the shared group' do
          minimal_share

          expect(finder.use_elasticsearch_finder?).to be(false)
          expect(GroupsFinder.new(user, params).execute).to include(shared_at_minimal)
        end

        context 'when the share has expired' do
          let(:minimal_share) do
            create(:group_group_link, shared_group: shared_at_minimal, shared_with_group: member_group,
              group_access: ::Gitlab::Access::MINIMAL_ACCESS, expires_at: 1.day.ago)
          end

          it 'still falls back while the expired link exists' do
            minimal_share

            expect(finder.use_elasticsearch_finder?).to be(false)
            expect(GroupsFinder.new(user, params).execute).to include(shared_at_minimal)
          end
        end
      end

      context 'with the request store active', :request_store do
        it 'resolves the project ancestry once per request' do
          expect(::Search::ProjectsFinder).to receive(:new).once.and_call_original

          finder.execute
        end
      end

      context 'when there is no current user' do
        subject(:finder) { described_class.new(nil, params) }

        it 'stays eligible, since anonymous requests get public groups either way' do
          expect(finder.use_elasticsearch_finder?).to be(true)
        end
      end

      context 'when the user is a member of nothing' do
        let_it_be(:stranger) { create(:user) }

        subject(:finder) { described_class.new(stranger, params) }

        it 'returns nothing, like GroupsFinder' do
          # nil means Elasticsearch matched nothing, so no group leaks past the filter.
          expect(finder.execute).to be_nil
          expect(::Namespaces::GroupsFinder.new(stranger, params).execute)
            .to match_array(GroupsFinder.new(stranger, params).execute)
        end
      end
    end

    context 'with active' do
      let_it_be(:archived_parent) { create(:group, :public, :archived, name: 'test-archived-root') }
      let_it_be(:child_of_archived) { create(:group, :public, parent: archived_parent, name: 'test-under-archived') }

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(archived_parent, child_of_archived)
        ensure_elasticsearch_index!
      end

      where(:active) { [true, false] }

      with_them do
        it 'returns the same groups as GroupsFinder' do
          params = { search: 'test', active: active }

          expect(described_class.new(user, params).execute)
            .to match_array(GroupsFinder.new(user, params).execute)
        end
      end

      it 'treats a subgroup under an archived parent as inactive, like GroupsFinder' do
        params = { search: 'test', active: false }

        expect(described_class.new(user, params).execute).to include(child_of_archived)
      end
    end

    # Regressions the match_array parity cases could not see.

    # The index stores each group's own archived flag, while GroupsFinder is
    # ancestor-aware, so a subgroup under an archived parent would diverge.
    context 'with an archived ancestor' do
      let_it_be(:archived_parent) { create(:group, :public, :archived, name: 'test-archived-parent') }
      let_it_be(:child_of_archived) { create(:group, :public, parent: archived_parent, name: 'test-under-archived') }

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(archived_parent, child_of_archived)
        ensure_elasticsearch_index!
      end

      where(:archived) { [true, false] }

      with_them do
        it 'falls back rather than diverging on inherited archived state' do
          finder = ::Search::AdvancedFinders::GroupsFinder.new(user, search: 'test', archived: archived)

          expect(finder.use_elasticsearch_finder?).to be(false)
        end
      end
    end

    # GroupQueryBuilder matches description by default; Group.search does not.
    context 'when the term only appears in a description' do
      let_it_be(:described) do
        create(:group, :public, name: 'unrelated-name', description: 'test-only-in-description')
      end

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(described)
        ensure_elasticsearch_index!
      end

      it 'does not return the group, matching GroupsFinder' do
        params = { search: 'test-only-in-description' }

        # nil means Elasticsearch matched nothing, so description is not in the field set.
        expect(::Search::AdvancedFinders::GroupsFinder.new(user, params).execute).to be_nil
        expect(::Namespaces::GroupsFinder.new(user, params).execute)
          .to match_array(GroupsFinder.new(user, params).execute)
      end
    end

    # GroupsFinder's in_organization accepts either shape, and a dropped filter would
    # widen across every organization instead of erroring.
    context 'with an organization filter' do
      let_it_be(:other_organization) { create(:organization) }
      let_it_be(:foreign_group) do
        create(:group, :public, organization: other_organization, name: 'test-foreign')
      end

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(foreign_group)
        ensure_elasticsearch_index!
      end

      where(:organization) { [ref(:other_organization), lazy { other_organization.id }] }

      with_them do
        it 'scopes to the organization for a record and for an id' do
          finder = described_class.new(user, search: 'test', organization: organization)

          expect(finder.execute).to contain_exactly(foreign_group)
        end
      end
    end

    # match_array hides ordering, so similarity needs an ordered comparison.
    it 'orders identically to GroupsFinder for similarity' do
      params = { search: 'test', sort: 'similarity', allow_similarity_sort: true }
      expected = GroupsFinder.new(user, params).execute.map(&:id)

      expect(::Search::AdvancedFinders::GroupsFinder.new(user, params).execute.map(&:id)).to eq(expected)
    end

    context 'with a membership-bounded similarity sort' do
      let_it_be(:similarity_group) { create(:group, :private, name: 'test-similarity') }
      let_it_be(:similarity_sibling) { create(:group, :private, name: 'testing-similarity-sibling') }
      let_it_be(:similarity_membership) do
        [similarity_group.add_developer(user), similarity_sibling.add_developer(user)]
      end

      let(:params) do
        { search: 'test', sort: 'similarity', allow_similarity_sort: true, all_available: false }
      end

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(similarity_group, similarity_sibling)
        ensure_elasticsearch_index!
      end

      it 'orders identically to GroupsFinder' do
        expected = GroupsFinder.new(user, params).execute.map(&:id)

        expect(described_class.new(user, params).execute.map(&:id)).to eq(expected)
      end
    end

    context 'with a visibility-restricted similarity sort' do
      let(:params) do
        { search: 'test', sort: 'similarity', allow_similarity_sort: true, visibility: 'public' }
      end

      it 'orders identically to GroupsFinder' do
        expected = GroupsFinder.new(user, params).execute.map(&:id)

        expect(described_class.new(user, params).execute.map(&:id)).to eq(expected)
      end
    end

    it 'preloads namespace_details like GroupsFinder, so description_html does not N+1' do
      expect(finder.execute.first.association(:namespace_details)).to be_loaded
    end

    context 'when Elasticsearch truncated the match set' do
      before do
        stub_const('EE::Search::AdvancedFinders::GroupsFinder::RESULT_LIMIT', 1)
      end

      it 'returns nil rather than sorting an incomplete set' do
        expect(finder.execute).to be_nil
      end
    end

    context 'when scoped to a parent' do
      let(:params) { { search: 'test', parent: parent_group } }

      it 'returns descendants and excludes the parent itself' do
        expect(finder.execute).to contain_exactly(subgroup)
      end

      it 'routes the query to the shard holding the hierarchy' do
        expect(::Gitlab::Search::Client).to receive(:execute_search)
          .with(query: anything, options: hash_including(root_ancestor_ids: [parent_group.id]))
          .and_call_original

        finder.execute
      end
    end

    context 'when nothing matches' do
      let(:params) { { search: 'no-such-group-anywhere' } }

      it 'declines to answer so the caller falls back to PostgreSQL' do
        expect(finder.execute).to be_nil
      end

      it 'returns nothing overall rather than every group' do
        expect(::Namespaces::GroupsFinder.new(user, params).execute).to be_empty
      end
    end

    # A group absent from the index is indistinguishable from one that has no match, so
    # an empty result must not be reported as authoritative.
    context 'when a matching group is missing from the index' do
      let_it_be(:unindexed_group) { create(:group, :public, name: 'test-unindexed') }

      let(:params) { { search: 'test-unindexed' } }

      it 'declines to answer so the caller falls back to PostgreSQL' do
        expect(finder.execute).to be_nil
      end

      it 'is still found through Namespaces::GroupsFinder' do
        expect(::Namespaces::GroupsFinder.new(user, params).execute).to include(unindexed_group)
      end
    end

    context 'with a private group the user cannot see' do
      let_it_be(:private_group) { create(:group, :private, name: 'test-private') }

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(private_group)
        ensure_elasticsearch_index!
      end

      it 'does not return it' do
        expect(finder.execute).not_to include(private_group)
      end

      context 'when the user is a member' do
        before_all do
          private_group.add_developer(user)
        end

        it 'returns it' do
          expect(finder.execute).to include(private_group)
        end
      end
    end

    # Group.search reads the routes table when no parent is given, so a term that only
    # hits an ancestor's name still returns the descendant on PostgreSQL.
    context 'when the term only matches an ancestor name' do
      let_it_be(:unrelated_child) { create(:group, :public, parent: parent_group, name: 'unrelated') }

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(unrelated_child)
        ensure_elasticsearch_index!
      end

      it 'returns the descendant, matching GroupsFinder' do
        params = { search: 'test' }

        expect(described_class.new(user, params).execute)
          .to match_array(GroupsFinder.new(user, params).execute)
        expect(described_class.new(user, params).execute).to include(unrelated_child)
      end

      context 'when a parent is given' do
        it 'stops matching the route, matching GroupsFinder' do
          params = { search: 'test', parent: parent_group }

          expect(described_class.new(user, params).execute)
            .to match_array(GroupsFinder.new(user, params).execute)
          expect(described_class.new(user, params).execute).not_to include(unrelated_child)
        end
      end
    end

    # GroupsFinder authorizes through `authorized_groups.self_and_ancestors`, so
    # membership on a subgroup also reveals its private parents.
    context 'with membership on a private subgroup only' do
      let_it_be(:private_parent) { create(:group, :private, name: 'test-private-parent') }
      let_it_be(:private_child) { create(:group, :private, parent: private_parent, name: 'test-private-child') }

      before_all do
        private_child.add_developer(user)
      end

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(private_parent, private_child)
        ensure_elasticsearch_index!
      end

      it 'returns the private ancestor too, matching GroupsFinder' do
        expect(finder.execute).to include(private_parent, private_child)
        expect(finder.execute).to match_array(GroupsFinder.new(user, params).execute)
      end

      context 'when the user is not a member' do
        let_it_be(:other_user) { create(:user) }

        it 'returns neither' do
          expect(described_class.new(other_user, params).execute)
            .not_to include(private_parent, private_child)
        end
      end
    end

    # `authorized_groups` also covers groups reached only through project membership.
    context 'with access derived from a project membership' do
      let_it_be(:private_parent) { create(:group, :private, name: 'test-project-parent') }
      let_it_be(:private_child) { create(:group, :private, parent: private_parent, name: 'test-project-child') }
      let_it_be(:project) { create(:project, :private, group: private_child) }

      before_all do
        project.add_developer(user)
      end

      before do
        ::Elastic::ProcessInitialBookkeepingService.track!(private_parent, private_child)
        ensure_elasticsearch_index!
      end

      it 'returns the group hierarchy above the project, matching GroupsFinder' do
        expect(finder.execute).to include(private_parent, private_child)
        expect(finder.execute).to match_array(GroupsFinder.new(user, params).execute)
      end
    end

    context 'when Elasticsearch fails' do
      it 'falls back rather than raising on an error response' do
        allow(::Gitlab::Search::Client).to receive(:execute_search).and_yield({ 'error' => { 'type' => 'timeout' } })

        expect(finder.execute).to be_nil
      end

      it 'falls back rather than raising on a transport error' do
        allow(::Gitlab::Search::Client).to receive(:execute_search)
          .and_raise(::Elasticsearch::Transport::Transport::Errors::GatewayTimeout)
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)

        expect(finder.execute).to be_nil
      end
    end
  end
end
