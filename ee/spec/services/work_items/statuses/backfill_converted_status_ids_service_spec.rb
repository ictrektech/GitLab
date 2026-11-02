# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Statuses::BackfillConvertedStatusIdsService, feature_category: :team_planning do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:other_project) { create(:project, group: create(:group)) }

  let_it_be(:to_do_status) { create(:work_item_custom_status, :to_do, namespace: group) }
  let_it_be(:done_status) { create(:work_item_custom_status, :done, namespace: group) }

  let_it_be(:to_do_row) { create_status_row(project, system_defined_status_id: 1) }
  let_it_be(:done_row) { create_status_row(project, system_defined_status_id: 3) }
  let_it_be(:unconverted_row) { create_status_row(project, system_defined_status_id: 4) }
  let_it_be(:other_group_row) { create_status_row(other_project, system_defined_status_id: 1) }
  let_it_be(:custom_row) { create_status_row(project, custom_status_id: to_do_status.id) }

  let(:namespace_ids) { [project.project_namespace_id] }
  let(:limiter) { instance_double(Gitlab::Metrics::RuntimeLimiter, over_time?: false) }

  subject(:execute) { described_class.new(group).execute(namespace_ids, limiter) }

  it 'rewrites each row to the converted status matching its system-defined id' do
    expect(execute.payload).to eq(rewritten: 2, inserted: 0, completed: true, resume_at: nil)

    expect(to_do_row.reload).to have_attributes(custom_status_id: to_do_status.id, system_defined_status_id: nil)
    expect(done_row.reload).to have_attributes(custom_status_id: done_status.id, system_defined_status_id: nil)
  end

  it 'leaves unconverted, foreign and already custom rows untouched' do
    expect { execute }
      .not_to change { [unconverted_row, other_group_row, custom_row].map { |row| row.reload.attributes } }
  end

  it 'preserves updated_at' do
    expect { execute }.not_to change { to_do_row.reload.updated_at }
  end

  it 'walks the work items of each namespace in slices' do
    stub_const("#{described_class}::BATCH_SIZE", 1)

    expect(execute.payload).to eq(rewritten: 2, inserted: 0, completed: true, resume_at: nil)
    expect(to_do_row.reload.custom_status_id).to eq(to_do_status.id)
    expect(done_row.reload.custom_status_id).to eq(done_status.id)
  end

  context 'when a legacy row matches two converted statuses' do
    before do
      create(:work_item_custom_status, :to_do, namespace: group)
    end

    it 'still drains every row' do
      expect(execute.payload).to include(completed: true)

      expect([to_do_row, done_row].map { |row| row.reload.system_defined_status_id }).to all(be_nil)
    end
  end

  context 'when the limiter is over time' do
    let(:limiter) { instance_double(Gitlab::Metrics::RuntimeLimiter, over_time?: true) }

    it 'stops after one slice and reports where it stopped' do
      stub_const("#{described_class}::BATCH_SIZE", 1)

      expect(execute.payload).to eq(
        rewritten: 1,
        inserted: 0,
        completed: false,
        resume_at: { namespace_id: project.project_namespace_id, iid: to_do_row.work_item.iid }
      )
      expect(to_do_row.reload.custom_status_id).to eq(to_do_status.id)
      expect(done_row.reload.system_defined_status_id).to eq(3)
    end
  end

  context 'when resuming from a previous position' do
    let_it_be(:second_project) { create(:project, group: group) }
    let_it_be(:second_project_row) { create_status_row(second_project, system_defined_status_id: 1) }

    let(:namespace_ids) { [project.project_namespace_id, second_project.project_namespace_id] }

    subject(:execute) { described_class.new(group).execute(namespace_ids, limiter, resume_at: resume_at) }

    context 'when the namespace to resume from is in the batch' do
      let(:resume_at) { { namespace_id: project.project_namespace_id, iid: to_do_row.work_item.iid } }

      it 'skips the work items handled before and continues with the rest of the batch' do
        expect(execute.payload).to eq(rewritten: 2, inserted: 0, completed: true, resume_at: nil)

        expect(to_do_row.reload.system_defined_status_id).to eq(1)
        expect(done_row.reload.custom_status_id).to eq(done_status.id)
        expect(second_project_row.reload.custom_status_id).to eq(to_do_status.id)
      end
    end

    context 'when resuming from a later namespace in the batch' do
      let(:resume_at) { { namespace_id: second_project.project_namespace_id, iid: 0 } }

      it 'skips the namespaces before it' do
        expect(execute.payload).to eq(rewritten: 1, inserted: 0, completed: true, resume_at: nil)

        expect([to_do_row, done_row].map { |row| row.reload.system_defined_status_id }).to eq([1, 3])
        expect(second_project_row.reload.custom_status_id).to eq(to_do_status.id)
      end
    end

    context 'when the namespace to resume from is no longer in the batch' do
      let(:resume_at) { { namespace_id: other_project.project_namespace_id, iid: 0 } }

      it 'processes the whole batch' do
        expect(execute.payload).to eq(rewritten: 3, inserted: 0, completed: true, resume_at: nil)
      end
    end
  end

  context 'when a namespace in the batch belongs to another group' do
    let(:namespace_ids) { [project.project_namespace_id, other_project.project_namespace_id] }

    it 'skips it' do
      expect(execute.payload).to eq(rewritten: 2, inserted: 0, completed: true, resume_at: nil)
      expect(other_group_row.reload.system_defined_status_id).to eq(1)
    end
  end

  context 'when work items in the namespace have no status row' do
    let_it_be(:duplicate_status) { create(:work_item_custom_status, :duplicate, namespace: group) }
    let_it_be(:lifecycle) do
      create(:work_item_custom_lifecycle, namespace: group, default_open_status: to_do_status,
        default_closed_status: done_status, default_duplicate_status: duplicate_status).tap do |lifecycle|
        # Skips the license check, which cannot be stubbed in let_it_be.
        build(:work_item_type_custom_lifecycle, namespace: group, lifecycle: lifecycle,
          work_item_type: build(:work_item_system_defined_type, :issue)).save!(validate: false)
      end
    end

    let_it_be(:open_item) { create(:work_item, project: project, created_at: 3.days.ago) }
    let_it_be(:closed_item) { create(:work_item, :closed, project: project) }
    let_it_be(:duplicate_item) { create(:work_item, :closed, project: project, duplicated_to_id: open_item.id) }
    let_it_be(:incident) { create(:work_item, :incident, project: project) }

    def row_for(item)
      WorkItems::Statuses::CurrentStatus.find_by(work_item_id: item.id)
    end

    it 'inserts a row pointing at the lifecycle default for the item state' do
      expect(execute.payload).to include(rewritten: 2, inserted: 3, completed: true)

      expect(row_for(open_item))
        .to have_attributes(custom_status_id: to_do_status.id, updated_at: open_item.reload.created_at)
      expect(row_for(closed_item).custom_status_id).to eq(done_status.id)
      expect(row_for(duplicate_item).custom_status_id).to eq(duplicate_status.id)
    end

    it 'skips items whose type has no lifecycle in the group' do
      execute

      expect(row_for(incident)).to be_nil
    end

    it 'inserts nothing on a second run' do
      execute

      expect(described_class.new(group).execute(namespace_ids, limiter).payload).to include(inserted: 0)
    end
  end

  context 'with no namespace ids' do
    let(:namespace_ids) { [] }

    it 'does nothing' do
      expect(execute.payload).to eq(rewritten: 0, inserted: 0, completed: true, resume_at: nil)
      expect(to_do_row.reload.system_defined_status_id).to eq(1)
    end
  end

  def create_status_row(project, attrs)
    work_item = create(:work_item, project: project)

    build(:work_item_current_status, { work_item: work_item, system_defined_status_id: nil }.merge(attrs))
      .tap { |row| row.save!(validate: false) }
  end
end
