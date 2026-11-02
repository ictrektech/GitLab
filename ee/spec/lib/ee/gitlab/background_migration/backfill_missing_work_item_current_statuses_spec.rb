# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundMigration::BackfillMissingWorkItemCurrentStatuses, feature_category: :team_planning do
  let(:issue_type_id) { 1 }
  let(:incident_type_id) { 2 }
  let(:task_type_id) { 5 }
  let(:frozen_time) { Time.zone.parse('2026-01-01 12:00:00') }
  let(:mapping_starts_at) { Time.zone.parse('2026-02-01 00:00:00') }

  let!(:organization) { organizations_table.create!(name: 'org', path: 'org') }

  let!(:converted_group) { create_group('converted') }
  let!(:plain_group) { create_group('plain') }
  let!(:converted_subgroup) { create_subgroup(converted_group, 'converted-sub') }

  let!(:open_status) { create_status(converted_group, 'New') }
  let!(:closed_status) { create_status(converted_group, 'Complete') }
  let!(:duplicate_status) { create_status(converted_group, 'Duplicate') }
  let!(:lifecycle) { create_lifecycle(converted_group, open_status, closed_status, duplicate_status, issue_type_id) }

  let!(:task_open_status) { create_status(converted_group, 'Task new') }
  let!(:task_lifecycle) do
    create_lifecycle(converted_group, task_open_status, closed_status, duplicate_status, task_type_id, name: 'Tasks')
  end

  let!(:open_item) { create_item(converted_group, 'open') }
  let!(:closed_item) { create_item(converted_group, 'closed', state_id: 2) }
  let!(:duplicate_item) { create_item(converted_group, 'duplicate', state_id: 2, duplicated_to_id: open_item.id) }
  let!(:item_in_subgroup) { create_item(converted_subgroup, 'nested') }
  let!(:task_item) { create_item(converted_group, 'task', work_item_type_id: task_type_id) }
  let!(:item_with_row) { create_item(converted_group, 'has-row') }
  let!(:item_of_unmanaged_type) { create_item(converted_group, 'incident', work_item_type_id: incident_type_id) }
  let!(:item_in_plain_group) { create_item(plain_group, 'plain') }

  let!(:existing_row) do
    current_statuses_table.create!(
      work_item_id: item_with_row.id, namespace_id: item_with_row.namespace_id,
      custom_status_id: closed_status.id, updated_at: frozen_time
    )
  end

  it 'creates a row pointing at the lifecycle default for the item state' do
    perform_migration

    expect(status_row_for(open_item))
      .to have_attributes(custom_status_id: open_status.id, system_defined_status_id: nil)
    expect(status_row_for(closed_item).custom_status_id).to eq(closed_status.id)
    expect(status_row_for(duplicate_item).custom_status_id).to eq(duplicate_status.id)
  end

  it 'resolves the lifecycle through the top-level group for items under a subgroup' do
    perform_migration

    expect(status_row_for(item_in_subgroup).custom_status_id).to eq(open_status.id)
  end

  it 'sets updated_at to the item creation time, as the read-time fallback does' do
    perform_migration

    expect(status_row_for(open_item).updated_at).to eq(open_item.created_at)
  end

  it 'uses the lifecycle of the item type, not another type in the same namespace' do
    perform_migration

    expect(status_row_for(task_item).custom_status_id).to eq(task_open_status.id)
    expect(status_row_for(open_item).custom_status_id).to eq(open_status.id)
  end

  it 'stores the raw default so time-bound mappings resolve from each item age' do
    remapped_status = create_status(converted_group, 'Better New')
    table(:work_item_custom_status_mappings).create!(
      namespace_id: converted_group.id, old_status_id: open_status.id, new_status_id: remapped_status.id,
      work_item_type_id: issue_type_id, valid_from: mapping_starts_at, created_at: frozen_time, updated_at: frozen_time
    )
    newer_item = create_item(converted_group, 'newer', created_at: mapping_starts_at + 1.day)

    perform_migration

    expect(status_row_for(open_item)).to have_attributes(custom_status_id: open_status.id, updated_at: frozen_time)
    expect(status_row_for(newer_item))
      .to have_attributes(custom_status_id: open_status.id, updated_at: newer_item.created_at)

    expect(resolved_status_name(open_item)).to eq('New')
    expect(resolved_status_name(newer_item)).to eq('Better New')
  end

  it 'leaves items that already have a row alone' do
    expect { perform_migration }.not_to change { existing_row.reload.attributes }
  end

  it 'leaves items that already have a system-defined row alone' do
    item = create_item(converted_group, 'has-system-row')
    row = current_statuses_table.create!(
      work_item_id: item.id, namespace_id: item.namespace_id, system_defined_status_id: 2, updated_at: frozen_time
    )

    expect { perform_migration }.not_to change { row.reload.attributes }
    expect(current_statuses_table.where(work_item_id: item.id).count).to eq(1)
  end

  it 'skips items whose type has no custom lifecycle in the namespace' do
    perform_migration

    expect(status_row_for(item_of_unmanaged_type)).to be_nil
  end

  it 'skips items in namespaces without a custom lifecycle' do
    perform_migration

    expect(status_row_for(item_in_plain_group)).to be_nil
  end

  it 'is idempotent' do
    perform_migration

    expect { perform_migration }
      .not_to change { current_statuses_table.order(:id).pluck(:work_item_id, :custom_status_id) }
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

  def lifecycles_table
    table(:work_item_custom_lifecycles)
  end

  def type_lifecycles_table
    table(:work_item_type_custom_lifecycles)
  end

  def current_statuses_table
    table(:work_item_current_statuses)
  end

  def perform_migration
    described_class.new(
      start_cursor: [issues_table.minimum(:id)],
      end_cursor: [issues_table.maximum(:id)],
      batch_table: :issues,
      batch_column: :id,
      sub_batch_size: 2,
      pause_ms: 0,
      connection: ApplicationRecord.connection
    ).perform
  end

  def status_row_for(item)
    current_statuses_table.find_by(work_item_id: item.id)
  end

  def resolved_status_name(item)
    ::WorkItems::Statuses::CurrentStatus.find(status_row_for(item).id).status.name
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

  def create_status(group, name)
    custom_statuses_table.create!(
      namespace_id: group.id, name: name, color: '#000000', created_at: frozen_time, updated_at: frozen_time
    )
  end

  def create_lifecycle(group, open, closed, duplicate, work_item_type_id, name: 'Default')
    lifecycle = lifecycles_table.create!(
      namespace_id: group.id, name: name, default_open_status_id: open.id,
      default_closed_status_id: closed.id, default_duplicate_status_id: duplicate.id,
      created_at: frozen_time, updated_at: frozen_time
    )
    type_lifecycles_table.create!(
      namespace_id: group.id, work_item_type_id: work_item_type_id, lifecycle_id: lifecycle.id,
      created_at: frozen_time, updated_at: frozen_time
    )
    lifecycle
  end

  def create_item(parent, key, attrs = {})
    name = "#{parent.path}-#{key}"
    project_namespace = namespaces_table.create!(
      name: name, path: name, type: 'Project', parent_id: parent.id, organization_id: organization.id
    )
    project_namespace.update!(traversal_ids: parent.traversal_ids + [project_namespace.id])
    project = projects_table.create!(
      namespace_id: parent.id, project_namespace_id: project_namespace.id, organization_id: organization.id
    )

    issues_table.create!(
      { title: 'issue', project_id: project.id, namespace_id: project_namespace.id,
        work_item_type_id: issue_type_id, state_id: 1, created_at: frozen_time }.merge(attrs)
    )
  end
end
