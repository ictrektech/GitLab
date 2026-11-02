# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::MemberGroups, feature_category: :knowledge_graph do
  let_it_be(:user) { create(:user) }
  let_it_be(:root_group) { create(:group) }
  let_it_be(:enabled_namespace) { create(:knowledge_graph_enabled_namespace, namespace: root_group) }

  describe '.for' do
    context 'with a request store', :request_store do
      it 'returns the same member groups for the same user' do
        first_member_groups = described_class.for(user)

        expect(described_class.for(user)).to be(first_member_groups)
      end

      it 'returns different member groups for a different user' do
        expect(described_class.for(user)).not_to be(described_class.for(create(:user)))
      end

      it 'returns the same member groups for an anonymous user' do
        first_member_groups = described_class.for(nil)

        expect(described_class.for(nil)).to be(first_member_groups)
      end
    end

    it 'returns new member groups without a request store' do
      first_member_groups = described_class.for(user)

      expect(described_class.for(user)).not_to be(first_member_groups)
    end
  end

  describe '#entries' do
    let_it_be(:subgroup_root) { create(:group) }
    let_it_be(:subgroup) { create(:group, parent: subgroup_root) }
    let_it_be(:member) { create(:user, reporter_of: root_group, developer_of: subgroup) }

    before_all do
      create(:knowledge_graph_enabled_namespace, namespace: subgroup_root)
    end

    it 'returns the paths and roles of the groups with Orbit on' do
      expect(described_class.new(member).entries).to contain_exactly(
        described_class::Entry.new(
          organization_id: root_group.organization_id,
          traversal_ids: root_group.traversal_ids,
          access_levels: [Gitlab::Access::REPORTER]
        ),
        described_class::Entry.new(
          organization_id: subgroup.organization_id,
          traversal_ids: subgroup.traversal_ids,
          access_levels: [Gitlab::Access::DEVELOPER]
        )
      )
    end

    context 'when the entries exceed the limit' do
      subject(:member_groups) { described_class.new(user) }

      let(:large_rows) do
        (1..600).map do |i|
          { organization_id: 1, traversal_ids: [i], access_levels: [Gitlab::Access::REPORTER] }
        end
      end

      let(:metrics) { Gitlab::Metrics::KnowledgeGraph::TraversalIds }

      before do
        allow(member_groups).to receive_messages(rows: large_rows, on_root_ids: (1..600).to_a)
        allow(metrics).to receive_messages(
          observe_traversal_ids_count: nil,
          observe_compaction_ratio: nil,
          increment_threshold_exceeded: nil
        )
      end

      it 'increments the threshold exceeded counter' do
        expect(metrics).to receive(:increment_threshold_exceeded)

        member_groups.entries
      end

      it 'logs a warning with structured data' do
        expect_next_instance_of(Gitlab::KnowledgeGraph::Logger) do |logger|
          expect(logger).to receive(:warn).with(hash_including(
            message: 'Traversal ID count exceeds threshold',
            Labkit::Fields::GL_USER_ID => user.id,
            traversal_ids_count: 600,
            threshold: described_class::MAX_ENTRIES
          ))
        end

        member_groups.entries
      end

      it 'returns the first entries up to the limit' do
        expect(member_groups.entries.size).to eq(described_class::MAX_ENTRIES)
      end
    end

    context 'when the entries exceed the limit across multiple access levels' do
      subject(:member_groups) { described_class.new(user) }

      let(:large_rows) do
        (1..400).map do |i|
          { organization_id: 1, traversal_ids: [i], access_levels: [Gitlab::Access::REPORTER] }
        end + (401..800).map do |i|
          { organization_id: 1, traversal_ids: [i], access_levels: [Gitlab::Access::DEVELOPER] }
        end
      end

      let(:metrics) { Gitlab::Metrics::KnowledgeGraph::TraversalIds }

      before do
        allow(member_groups).to receive_messages(rows: large_rows, on_root_ids: (1..800).to_a)
        allow(metrics).to receive_messages(
          observe_traversal_ids_count: nil,
          observe_compaction_ratio: nil,
          increment_threshold_exceeded: nil
        )
      end

      it 'applies the limit once to all access levels' do
        expect(member_groups.entries.size).to eq(described_class::MAX_ENTRIES)
        expect(metrics).to have_received(:increment_threshold_exceeded).once
      end
    end

    context 'when an access level has no rows' do
      it 'records no compaction metrics' do
        metrics = Gitlab::Metrics::KnowledgeGraph::TraversalIds

        expect(metrics).not_to receive(:observe_traversal_ids_count)
        expect(metrics).not_to receive(:observe_compaction_ratio)

        expect(described_class.new(user).send(:compact, [])).to eq([])
      end
    end

    context 'when the original count is zero' do
      it 'skips the compaction ratio' do
        expect(Gitlab::Metrics::KnowledgeGraph::TraversalIds).not_to receive(:observe_compaction_ratio)

        described_class.new(user).send(:observe_compaction_ratio, 0, 0)
      end
    end
  end

  describe '#group_ids' do
    let_it_be(:other_root_group) { create(:group) }
    let_it_be(:other_enabled_namespace) do
      create(:knowledge_graph_enabled_namespace, namespace: other_root_group)
    end

    let_it_be(:first_root_group) do
      [root_group, other_root_group].min_by { |group| group.traversal_path(with_organization: true) }
    end

    let_it_be(:first_root_subgroup) { create(:group, parent: first_root_group) }
    let_it_be(:off_subgroup) { create(:group, parent: create(:group)) }
    let_it_be(:guest_group) { create(:group) }
    let_it_be(:project_member_group) { create(:group) }
    let_it_be(:member) do
      create(:user, reporter_of: [root_group, other_root_group, off_subgroup], maintainer_of: first_root_subgroup,
        guest_of: guest_group)
    end

    before_all do
      create(:knowledge_graph_enabled_namespace, namespace: project_member_group)
      create(:project, group: project_member_group, developers: member)
    end

    subject(:member_groups) { described_class.new(member) }

    it 'returns the highest Reporter+ group of each group tree, with Orbit on or off' do
      expect(member_groups.group_ids(enabled: false))
        .to contain_exactly(root_group.id, other_root_group.id, off_subgroup.id)
    end

    it 'returns only the groups with Orbit on when enabled is true' do
      expect(member_groups.group_ids(enabled: true)).to contain_exactly(root_group.id, other_root_group.id)
    end

    context 'when the entries exceed the limit' do
      before do
        stub_const("#{described_class}::MAX_ENTRIES", 2)
      end

      it 'returns only the groups of the entries that the limit keeps' do
        expect(member_groups.group_ids(enabled: true)).to contain_exactly(first_root_group.id)
      end
    end

    context 'when the groups with Orbit off exceed the limit' do
      let_it_be(:off_roots) { create_list(:group, 3) }
      let_it_be(:off_member) { create(:user, reporter_of: off_roots) }

      before do
        stub_const("#{described_class}::MAX_ENTRIES", 2)
      end

      it 'returns only as many groups with Orbit off as the limit' do
        group_ids = described_class.new(off_member).group_ids(enabled: false)

        expect(group_ids.size).to eq(2)
        expect(off_roots.map(&:id)).to include(*group_ids)
      end
    end

    context 'when the top-level groups with Orbit on are gated without access' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'returns them only with Orbit on or off' do
        expect(member_groups.group_ids(enabled: true)).to be_empty
        expect(member_groups.group_ids(enabled: false))
          .to contain_exactly(root_group.id, other_root_group.id, off_subgroup.id)
      end
    end
  end

  describe '#root_ids' do
    let_it_be(:subgroup) { create(:group, parent: root_group) }

    it 'returns no groups for an anonymous user' do
      expect(described_class.new(nil)).to have_attributes(root_ids: [], on_root_ids: [], entries: [])
    end

    it 'returns no groups for a user without Reporter+ group memberships' do
      expect(described_class.new(user).root_ids).to eq([])
    end

    context 'with the Reporter role in a top-level group' do
      before_all do
        root_group.add_reporter(user)
      end

      it 'returns the top-level group' do
        expect(described_class.new(user).root_ids).to contain_exactly(root_group.id)
      end
    end

    context 'with the Reporter role only in a subgroup' do
      before_all do
        subgroup.add_reporter(user)
      end

      it 'returns the top-level group of the subgroup' do
        expect(described_class.new(user).root_ids).to contain_exactly(root_group.id)
      end
    end
  end

  describe '#on_root_ids' do
    let_it_be(:off_root) { create(:group) }
    let_it_be(:member) { create(:user, reporter_of: off_root, developer_of: create(:group, parent: root_group)) }

    it 'returns the top-level groups with Orbit on' do
      expect(described_class.new(member)).to have_attributes(
        root_ids: contain_exactly(root_group.id, off_root.id),
        on_root_ids: contain_exactly(root_group.id)
      )
    end
  end
end
