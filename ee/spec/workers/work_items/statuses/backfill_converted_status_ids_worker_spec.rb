# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Statuses::BackfillConvertedStatusIdsWorker, feature_category: :team_planning do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:nested_project) { create(:project, group: subgroup) }
  let_it_be(:other_project) { create(:project, group: create(:group)) }
  let_it_be(:lifecycle) { create(:work_item_custom_lifecycle, namespace: group) }

  let_it_be_with_reload(:row_in_project) { create_status_row(project) }
  let_it_be_with_reload(:row_in_nested_project) { create_status_row(nested_project) }
  let_it_be_with_reload(:row_in_other_group) { create_status_row(other_project) }

  let(:worker) { described_class.new }
  let(:limiter) { instance_double(Gitlab::Metrics::RuntimeLimiter, over_time?: false, was_over_time?: false) }

  before do
    allow(Gitlab::Metrics::RuntimeLimiter).to receive(:new).and_return(limiter)
  end

  it 'resumes after more deploy interruptions than the default allows' do
    expect(described_class.sidekiq_options['max_retries_after_interruption']).to eq(20)
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [group.id] }

    it 'rewrites the rows of every namespace under the root' do
      perform_idempotent_work

      expect(row_in_project.custom_status_id).to eq(lifecycle.default_open_status.id)
      expect(row_in_nested_project.custom_status_id).to eq(lifecycle.default_open_status.id)
      expect(row_in_other_group.system_defined_status_id).to eq(1)
    end
  end

  describe '#perform' do
    subject(:perform) { worker.perform(group.id, cursor) }

    let(:cursor) { nil }

    it 'logs what it did' do
      expect(worker).to receive(:log_extra_metadata_on_done)
        .with(:result, { rewritten: 2, inserted: 0, over_time: false, cursor: nil })

      perform
    end

    context 'when the group does not exist' do
      it 'does nothing' do
        expect(WorkItems::Statuses::BackfillConvertedStatusIdsService).not_to receive(:new)

        worker.perform(non_existing_record_id)
      end
    end

    context 'when the group has no custom lifecycle' do
      it 'does nothing' do
        expect(WorkItems::Statuses::BackfillConvertedStatusIdsService).not_to receive(:new)

        worker.perform(other_project.group.id)

        expect(row_in_other_group.system_defined_status_id).to eq(1)
      end
    end

    context 'with a cursor' do
      let(:cursor) { { current_id: project.project_namespace_id, depth: [group.id, project.project_namespace_id] } }

      it 'resumes from the cursor' do
        perform

        expect(row_in_project.custom_status_id).to eq(lifecycle.default_open_status.id)
        expect(row_in_nested_project.system_defined_status_id).to eq(1)
      end
    end

    context 'when the cursor namespace was deleted' do
      let(:cursor) { { current_id: non_existing_record_id, depth: [group.id, non_existing_record_id] } }

      it 'starts over from the root' do
        perform

        expect(row_in_project.custom_status_id).to eq(lifecycle.default_open_status.id)
        expect(row_in_nested_project.custom_status_id).to eq(lifecycle.default_open_status.id)
      end
    end

    context 'when the cursor namespace moved to another group' do
      let(:cursor) do
        {
          current_id: other_project.project_namespace_id,
          depth: [group.id, other_project.project_namespace_id],
          namespace_id: other_project.project_namespace_id,
          iid: 0
        }
      end

      it 'starts over from the root and leaves the other group alone' do
        perform

        expect(row_in_project.custom_status_id).to eq(lifecycle.default_open_status.id)
        expect(row_in_nested_project.custom_status_id).to eq(lifecycle.default_open_status.id)
        expect(row_in_other_group.system_defined_status_id).to eq(1)
      end
    end

    context 'when over time' do
      let(:limiter) { instance_double(Gitlab::Metrics::RuntimeLimiter, over_time?: true, was_over_time?: true) }

      before do
        stub_const("#{described_class}::NAMESPACE_BATCH_SIZE", 1)
      end

      it 'stops after the batch and reschedules itself from there' do
        resume_cursor = nil
        expect(described_class).to receive(:perform_in)
          .with(described_class::RETRY_DELAY, group.id, kind_of(Hash)) { |_, _, cursor| resume_cursor = cursor }

        perform

        expect(row_in_project.system_defined_status_id).to eq(1)
        expect(row_in_nested_project.system_defined_status_id).to eq(1)

        allow(limiter).to receive_messages(over_time?: false, was_over_time?: false)
        described_class.new.perform(group.id, resume_cursor)

        expect(row_in_project.reload.custom_status_id).to eq(lifecycle.default_open_status.id)
        expect(row_in_nested_project.reload.custom_status_id).to eq(lifecycle.default_open_status.id)
      end
    end

    context 'when a namespace batch could not be drained in time' do
      let(:cursor) { { current_id: project.project_namespace_id, depth: [group.id, project.project_namespace_id] } }
      let(:resume_at) { { namespace_id: project.project_namespace_id, iid: 1 } }

      before do
        stub_const("#{described_class}::NAMESPACE_BATCH_SIZE", 1)

        allow_next_instance_of(WorkItems::Statuses::BackfillConvertedStatusIdsService) do |service|
          allow(service).to receive(:execute).and_return(
            ServiceResponse.success(payload: { rewritten: 1, inserted: 0, completed: false, resume_at: resume_at })
          )
        end
      end

      it 'reschedules itself from the same batch and the position it stopped at' do
        expect(described_class).to receive(:perform_in)
          .with(described_class::RETRY_DELAY, group.id, cursor.merge(resume_at).stringify_keys)

        perform
      end
    end

    context 'when time runs out partway through a namespace' do
      let_it_be_with_reload(:second_row_in_project) { create_status_row(project) }

      let(:cursor) { { current_id: project.project_namespace_id, depth: [group.id, project.project_namespace_id] } }
      let(:limiter) { instance_double(Gitlab::Metrics::RuntimeLimiter, over_time?: true, was_over_time?: true) }
      let(:position) { { namespace_id: project.project_namespace_id, iid: row_in_project.work_item.iid } }

      before do
        stub_const("#{described_class}::NAMESPACE_BATCH_SIZE", 1)
        stub_const("WorkItems::Statuses::BackfillConvertedStatusIdsService::BATCH_SIZE", 1)
      end

      it 'reschedules itself with the position it stopped at' do
        expect(described_class).to receive(:perform_in)
          .with(described_class::RETRY_DELAY, group.id, cursor.merge(position).stringify_keys) do |_, _, resume_cursor|
            expect([resume_cursor]).to param_containing_valid_native_json_types
          end

        perform

        expect(row_in_project.reload.custom_status_id).to eq(lifecycle.default_open_status.id)
        expect(second_row_in_project.reload.system_defined_status_id).to eq(1)
      end

      context 'when resuming from that position' do
        let(:limiter) { instance_double(Gitlab::Metrics::RuntimeLimiter, over_time?: false, was_over_time?: false) }

        it 'continues after the work items handled before' do
          expect_next_instance_of(WorkItems::Statuses::BackfillConvertedStatusIdsService) do |service|
            allow(service).to receive(:execute).and_call_original
            expect(service).to receive(:execute)
              .with([project.project_namespace_id], limiter, resume_at: position).and_call_original
          end

          worker.perform(group.id, cursor.merge(position).deep_stringify_keys)

          expect(row_in_project.reload.system_defined_status_id).to eq(1)
          expect(second_row_in_project.reload.custom_status_id).to eq(lifecycle.default_open_status.id)
        end

        context 'when the job goes past the batch it resumed in' do
          let(:cursor) { { current_id: group.id, depth: [group.id] } }
          let(:position) { { namespace_id: group.id, iid: 0 } }

          it 'only applies the position to that batch' do
            expect_next_instance_of(WorkItems::Statuses::BackfillConvertedStatusIdsService) do |service|
              expect(service).to receive(:execute).with(anything, limiter, resume_at: position).ordered
                .and_call_original
              expect(service).to receive(:execute).with(anything, limiter, resume_at: nil).at_least(:once).ordered
                .and_call_original
            end

            worker.perform(group.id, cursor.merge(position).deep_stringify_keys)

            expect(row_in_project.reload.custom_status_id).to eq(lifecycle.default_open_status.id)
            expect(row_in_nested_project.reload.custom_status_id).to eq(lifecycle.default_open_status.id)
          end
        end

        context 'when the cursor has only part of the position' do
          it 'processes the whole batch' do
            expect_next_instance_of(WorkItems::Statuses::BackfillConvertedStatusIdsService) do |service|
              expect(service).to receive(:execute)
                .with([project.project_namespace_id], limiter, resume_at: nil).and_call_original
              allow(service).to receive(:execute).and_call_original
            end

            worker.perform(group.id, cursor.merge(namespace_id: project.project_namespace_id).deep_stringify_keys)

            expect(row_in_project.reload.custom_status_id).to eq(lifecycle.default_open_status.id)
          end
        end
      end
    end
  end

  def create_status_row(project)
    work_item = create(:work_item, project: project)

    build(:work_item_current_status, work_item: work_item, system_defined_status_id: 1)
      .tap { |row| row.save!(validate: false) }
  end
end
