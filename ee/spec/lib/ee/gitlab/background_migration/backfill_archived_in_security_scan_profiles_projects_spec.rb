# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundMigration::BackfillArchivedInSecurityScanProfilesProjects,
  feature_category: :security_asset_inventories do
  let(:security_scan_profiles_table) { table(:security_scan_profiles, database: :sec) }
  let(:security_scan_profiles_projects_table) { table(:security_scan_profiles_projects, database: :sec) }
  let(:organizations_table) { table(:organizations) }
  let(:namespaces_table) { table(:namespaces) }
  let(:projects_table) { table(:projects) }
  let(:namespace_settings_table) { table(:namespace_settings) }

  let(:organization) { organizations_table.create!(name: 'organization', path: 'organization') }

  let(:migration_instance) do
    described_class.new(
      start_cursor: [security_scan_profiles_projects_table.minimum(:id)],
      end_cursor: [security_scan_profiles_projects_table.maximum(:id)],
      batch_table: :security_scan_profiles_projects,
      batch_column: :id,
      sub_batch_size: 100,
      pause_ms: 0,
      connection: SecApplicationRecord.connection
    )
  end

  subject(:perform_migration) { migration_instance.perform }

  def create_namespace(type:, name:, parent: nil)
    namespace = namespaces_table.create!(
      name: name, path: name, type: type, parent_id: parent&.id,
      organization_id: organization.id, traversal_ids: []
    )
    namespace.tap { |ns| ns.update!(traversal_ids: (parent&.traversal_ids || []) + [ns.id]) }
  end

  def create_group(name:, parent: nil, archived: false)
    group = create_namespace(type: 'Group', name: name, parent: parent)
    namespace_settings_table.create!(namespace_id: group.id, archived: archived, created_at: Time.current,
      updated_at: Time.current)
    group
  end

  def create_project(name:, namespace:, archived: false)
    project_namespace = create_namespace(type: 'Project', name: "#{name}-ns", parent: namespace)
    projects_table.create!(
      name: name, path: name, namespace_id: namespace.id,
      project_namespace_id: project_namespace.id, organization_id: organization.id, archived: archived
    )
  end

  def create_scan_profile(name:, namespace:)
    security_scan_profiles_table.create!(namespace_id: namespace.id, scan_type: 0, name: name)
  end

  def create_scan_profile_project(project_id:, scan_profile_id:, archived:)
    security_scan_profiles_projects_table.create!(
      project_id: project_id,
      security_scan_profile_id: scan_profile_id,
      archived: archived
    )
  end

  describe '#perform' do
    let(:group) { create_group(name: 'group') }
    let(:parent_group) { create_group(name: 'parent', archived: true) }
    let(:child_group) { create_group(name: 'child', parent: parent_group, archived: false) }

    let(:self_archived_project) { create_project(name: 'self-archived', namespace: group, archived: true) }
    let(:ancestor_archived_project) { create_project(name: 'ancestor-archived', namespace: child_group) }
    let(:drifted_project) { create_project(name: 'drifted', namespace: group) }
    let(:correct_project) { create_project(name: 'already-correct', namespace: group) }
    let(:divergent_project) { create_project(name: 'divergent', namespace: group) }

    let(:profile_a) { create_scan_profile(name: 'profile-a', namespace: group) }
    let(:profile_b) { create_scan_profile(name: 'profile-b', namespace: group) }

    context 'with rows that drifted from the project state' do
      let!(:self_archived_row) do
        create_scan_profile_project(project_id: self_archived_project.id, scan_profile_id: profile_a.id,
          archived: false)
      end

      let!(:ancestor_row) do
        create_scan_profile_project(project_id: ancestor_archived_project.id, scan_profile_id: profile_a.id,
          archived: false)
      end

      let!(:drifted_row) do
        create_scan_profile_project(project_id: drifted_project.id, scan_profile_id: profile_a.id, archived: true)
      end

      let!(:correct_row) do
        create_scan_profile_project(project_id: correct_project.id, scan_profile_id: profile_a.id, archived: false)
      end

      let!(:orphan_row) do
        create_scan_profile_project(project_id: non_existing_record_id, scan_profile_id: profile_a.id,
          archived: true)
      end

      # divergent current `archived` values on two rows for the same project
      let!(:divergent_row_true) do
        create_scan_profile_project(project_id: divergent_project.id, scan_profile_id: profile_a.id, archived: true)
      end

      let!(:divergent_row_false) do
        create_scan_profile_project(project_id: divergent_project.id, scan_profile_id: profile_b.id,
          archived: false)
      end

      it 'reconciles every row with the project archived state', :aggregate_failures do
        perform_migration

        expect(self_archived_row.reload.archived).to be(true)
        expect(ancestor_row.reload.archived).to be(true)
        expect(drifted_row.reload.archived).to be(false)
        expect(correct_row.reload.archived).to be(false)
        expect(orphan_row.reload.archived).to be(true)
        expect(divergent_row_true.reload.archived).to be(false)
        expect(divergent_row_false.reload.archived).to be(false)
      end
    end

    context 'when no row resolves to an archived project' do
      let!(:drifted_row) do
        create_scan_profile_project(project_id: drifted_project.id, scan_profile_id: profile_a.id, archived: true)
      end

      it 'skips the archived update and only clears the stale flag' do
        perform_migration

        expect(drifted_row.reload.archived).to be(false)
      end
    end

    context 'when every row already matches the project state' do
      let!(:self_archived_row) do
        create_scan_profile_project(project_id: self_archived_project.id, scan_profile_id: profile_a.id,
          archived: true)
      end

      let!(:correct_row) do
        create_scan_profile_project(project_id: correct_project.id, scan_profile_id: profile_a.id, archived: false)
      end

      it 'leaves all rows unchanged', :aggregate_failures do
        perform_migration

        expect(self_archived_row.reload.archived).to be(true)
        expect(correct_row.reload.archived).to be(false)
      end
    end
  end
end
