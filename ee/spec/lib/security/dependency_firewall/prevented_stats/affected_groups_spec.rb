# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::DependencyFirewall::PreventedStats::AffectedGroups, feature_category: :dependency_firewall do
  let_it_be(:root) { create(:group) }
  let_it_be(:sub) { create(:group, parent: root) }
  let_it_be(:project) { create(:project, group: sub) }

  describe '.for_projects' do
    it 'returns the root and sub group of a project' do
      expect(described_class.for_projects([project.id])).to contain_exactly(root.id, sub.id)
    end

    it 'returns nothing for a project in a personal namespace' do
      personal_project = create(:project, namespace: create(:user, :with_namespace).namespace)

      expect(described_class.for_projects([personal_project.id])).to eq([])
    end

    it 'returns nothing when given no project ids' do
      expect(described_class.for_projects([])).to eq([])
    end

    it 'returns nothing for unknown project ids' do
      expect(described_class.for_projects([non_existing_record_id])).to eq([])
    end

    it 'returns each group once across projects in the same hierarchy' do
      other_project = create(:project, group: sub)

      expect(described_class.for_projects([project.id, other_project.id])).to contain_exactly(root.id, sub.id)
    end

    it 'returns nothing when the flag is disabled for the root group' do
      stub_feature_flags(dependency_firewall_group_prevented_stats: false)

      expect(described_class.for_projects([project.id])).to eq([])
    end

    it 'returns only groups whose root has the flag enabled' do
      other_project = create(:project, group: create(:group))
      stub_feature_flags(dependency_firewall_group_prevented_stats: root)

      expect(described_class.for_projects([project.id, other_project.id])).to contain_exactly(root.id, sub.id)
    end

    it 'resolves the groups with a single query' do
      other_project = create(:project, group: create(:group))

      recorder = ActiveRecord::QueryRecorder.new { described_class.for_projects([project.id, other_project.id]) }

      expect(recorder.count).to eq(1)
    end

    it 'does not look up projects while the flag has never been set',
      :clean_gitlab_redis_feature_flag, stub_feature_flags: false do
      recorder = ActiveRecord::QueryRecorder.new { described_class.for_projects([project.id]) }

      expect(recorder.log.grep(/FROM "projects"/)).to be_empty
    end
  end

  describe '.for_namespaces' do
    it 'returns the group and its ancestors' do
      expect(described_class.for_namespaces([sub.id])).to contain_exactly(root.id, sub.id)
    end

    it 'returns each group once across namespaces in the same hierarchy' do
      expect(described_class.for_namespaces([sub.id, root.id])).to contain_exactly(root.id, sub.id)
    end

    it 'returns nothing when given no namespace ids' do
      expect(described_class.for_namespaces([])).to eq([])
    end

    it 'returns nothing for a personal namespace' do
      expect(described_class.for_namespaces([create(:user, :with_namespace).namespace.id])).to eq([])
    end

    it 'returns nothing for an unknown namespace id' do
      expect(described_class.for_namespaces([non_existing_record_id])).to eq([])
    end

    it 'returns nothing when the flag is disabled for the root group' do
      stub_feature_flags(dependency_firewall_group_prevented_stats: false)

      expect(described_class.for_namespaces([sub.id])).to eq([])
    end
  end
end
