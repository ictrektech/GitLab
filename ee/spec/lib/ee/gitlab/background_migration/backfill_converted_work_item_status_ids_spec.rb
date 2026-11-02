# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundMigration::BackfillConvertedWorkItemStatusIds, feature_category: :team_planning do
  let(:to_do_status_id) { 1 }
  let(:done_status_id) { 3 }
  let(:frozen_time) { Time.zone.parse('2026-01-01 12:00:00') }

  let!(:organization) { organizations_table.create!(name: 'org', path: 'org') }

  let!(:converted_group) { create_group('converted') }
  let!(:plain_group) { create_group('plain') }
  let!(:multi_group) { create_group('multi') }
  let!(:converted_subgroup) { create_subgroup(converted_group, 'converted-sub') }
  let!(:plain_subgroup) { create_subgroup(plain_group, 'plain-sub') }

  let!(:converted_status) { create_converted_status(converted_group, 'New', to_do_status_id) }
  let!(:multi_to_do_status) { create_converted_status(multi_group, 'To do', to_do_status_id) }
  let!(:multi_done_status) { create_converted_status(multi_group, 'Done', done_status_id) }

  let!(:to_do_row_in_multi_group) do
    create_status_row(multi_group, 'to-do', system_defined_status_id: to_do_status_id)
  end

  let!(:done_row_in_multi_group) do
    create_status_row(multi_group, 'done', system_defined_status_id: done_status_id)
  end

  let!(:legacy_row_in_converted_group) do
    create_status_row(converted_group, 'legacy', system_defined_status_id: to_do_status_id)
  end

  let!(:unmatched_legacy_row_in_converted_group) do
    create_status_row(converted_group, 'unmatched', system_defined_status_id: done_status_id)
  end

  let!(:legacy_row_in_plain_group) do
    create_status_row(plain_group, 'legacy', system_defined_status_id: to_do_status_id)
  end

  let!(:legacy_row_in_converted_subgroup) do
    create_status_row(converted_subgroup, 'legacy', system_defined_status_id: to_do_status_id)
  end

  let!(:legacy_row_in_plain_subgroup) do
    create_status_row(plain_subgroup, 'legacy', system_defined_status_id: to_do_status_id)
  end

  let!(:custom_row) { create_status_row(converted_group, 'custom', custom_status_id: converted_status.id) }

  it 'rewrites legacy rows whose namespace converted the matching status' do
    perform_migration

    expect(legacy_row_in_converted_group.reload).to have_attributes(
      custom_status_id: converted_status.id,
      system_defined_status_id: nil
    )
  end

  it 'matches each legacy row to its own converted status when a namespace converted several' do
    perform_migration

    expect(to_do_row_in_multi_group.reload.custom_status_id).to eq(multi_to_do_status.id)
    expect(done_row_in_multi_group.reload.custom_status_id).to eq(multi_done_status.id)
  end

  it 'preserves updated_at on rewritten rows' do
    expect { perform_migration }.not_to change { legacy_row_in_converted_group.reload.updated_at }
  end

  it 'leaves legacy rows alone when no converted status matches' do
    expect { perform_migration }
      .not_to change { unmatched_legacy_row_in_converted_group.reload.attributes }
  end

  it 'leaves legacy rows in namespaces that never converted alone' do
    expect { perform_migration }.not_to change { legacy_row_in_plain_group.reload.attributes }
  end

  it 'resolves the converted status through the top-level group for projects under a subgroup' do
    perform_migration

    expect(legacy_row_in_converted_subgroup.reload).to have_attributes(
      custom_status_id: converted_status.id,
      system_defined_status_id: nil
    )
  end

  it 'leaves legacy rows under a subgroup alone when the top-level group never converted' do
    expect { perform_migration }.not_to change { legacy_row_in_plain_subgroup.reload.attributes }
  end

  it 'leaves rows that already use a custom status alone' do
    expect { perform_migration }.not_to change { custom_row.reload.attributes }
  end

  it 'is idempotent' do
    perform_migration

    expect { perform_migration }
      .not_to change { current_statuses_table.order(:id).pluck(:custom_status_id, :system_defined_status_id) }
  end

  def organizations_table
    table(:organizations)
  end

  def namespaces_table
    table(:namespaces)
  end

  def projects_table
    table(:projects)
  end

  def issues_table
    table(:issues)
  end

  def custom_statuses_table
    table(:work_item_custom_statuses)
  end

  def current_statuses_table
    table(:work_item_current_statuses)
  end

  def perform_migration
    described_class.new(
      start_cursor: [current_statuses_table.minimum(:id)],
      end_cursor: [current_statuses_table.maximum(:id)],
      batch_table: :work_item_current_statuses,
      batch_column: :id,
      sub_batch_size: 2,
      pause_ms: 0,
      connection: ApplicationRecord.connection
    ).perform
  end

  def create_group(path)
    group = namespaces_table.create!(name: path, path: path, type: 'Group', organization_id: organization.id)
    group.update!(traversal_ids: [group.id])
    group
  end

  def create_subgroup(parent, path)
    subgroup = namespaces_table.create!(
      name: path, path: path, type: 'Group', parent_id: parent.id, organization_id: organization.id
    )
    subgroup.update!(traversal_ids: parent.traversal_ids + [subgroup.id])
    subgroup
  end

  def create_converted_status(group, name, system_defined_status_id)
    custom_statuses_table.create!(
      namespace_id: group.id, name: name, color: '#000000',
      converted_from_system_defined_status_identifier: system_defined_status_id,
      created_at: frozen_time, updated_at: frozen_time
    )
  end

  def create_status_row(parent, key, attrs)
    name = "#{parent.path}-#{key}"
    project_namespace = namespaces_table.create!(
      name: name, path: name, type: 'Project', parent_id: parent.id, organization_id: organization.id
    )
    project_namespace.update!(traversal_ids: parent.traversal_ids + [project_namespace.id])
    project = projects_table.create!(
      namespace_id: parent.id, project_namespace_id: project_namespace.id, organization_id: organization.id
    )
    issue = issues_table.create!(
      title: 'issue', project_id: project.id, namespace_id: project_namespace.id, work_item_type_id: 1
    )

    current_statuses_table.create!(
      { work_item_id: issue.id, namespace_id: project_namespace.id, updated_at: frozen_time }.merge(attrs)
    )
  end
end
