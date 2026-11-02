# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::Workloads::Workload, feature_category: :continuous_integration do
  subject(:workload) { create(:ci_workload) }

  it { is_expected.to belong_to(:project) }
  it { is_expected.to belong_to(:pipeline) }

  it { is_expected.to validate_presence_of(:partition_id) }
  it { is_expected.to validate_presence_of(:pipeline) }
  it { is_expected.to validate_presence_of(:project) }

  describe 'partitioning' do
    context 'with pipeline' do
      let(:pipeline) { build(:ci_pipeline, partition_id: 123) }
      let(:workload) { build(:ci_workload, pipeline: pipeline) }

      it 'copies the partition_id from pipeline' do
        expect { workload.valid? }.to change { workload.partition_id }.to(123)
      end

      context 'when it is already set' do
        let(:workload) { build(:ci_workload, pipeline: pipeline, partition_id: 125) }

        it 'does not change the partition_id value' do
          expect { workload.valid? }.not_to change { workload.partition_id }
        end
      end
    end

    context 'without pipeline' do
      subject(:workload) { build(:ci_workload, pipeline: nil, project: build_stubbed(:project)) }

      it { is_expected.to validate_presence_of(:partition_id) }

      it 'does not change the partition_id value' do
        expect { workload.valid? }.not_to change { workload.partition_id }
      end
    end
  end

  describe '#pipeline' do
    let(:pipeline_queries) do
      ids = workloads.map(&:id)

      ActiveRecord::QueryRecorder.new { described_class.id_in(ids).preload(:pipeline).to_a }
        .log.grep(/FROM "p_ci_pipelines"/)
    end

    context 'with workloads in one partition' do
      let(:workloads) { create_list(:ci_workload, 2) }

      it 'preloads the pipelines with one query bounded by partition_id' do
        expect(pipeline_queries.size).to eq(1)
        expect(pipeline_queries.first).to include(%("partition_id" = #{workloads.first.partition_id}))
      end
    end

    context 'with workloads in different partitions' do
      let(:other_pipeline) { create(:ci_pipeline, partition_id: workload.partition_id + 1) }
      let(:workloads) { [workload, create(:ci_workload, pipeline: other_pipeline)] }

      it 'preloads one query per partition and returns each workload its own pipeline' do
        loaded = described_class.id_in(workloads).preload(:pipeline).index_by(&:id)

        expect(pipeline_queries.size).to eq(2)
        expect(loaded.transform_values { |w| w.pipeline.id }).to eq(
          workloads[0].id => workload.pipeline.id, workloads[1].id => other_pipeline.id
        )
      end
    end
  end

  context 'with loose foreign key on ci_stages.project_id' do
    it_behaves_like 'cleanup by a loose foreign key' do
      let!(:parent) { create(:project) }
      let!(:model) { create(:ci_workload, project: parent) }
    end
  end

  describe '#logs_url' do
    context 'when pipeline has logs' do
      let!(:log) { create(:ci_build, pipeline: workload.pipeline) }

      it 'returns the log url' do
        allow(Gitlab::Routing).to receive_message_chain(:url_helpers, :project_job_url)
          .with(workload.project, log).and_return('log-url')

        expect(workload.logs_url).to eq('log-url')
      end
    end

    context 'when pipeline has no logs' do
      it 'returns nil' do
        expect(workload.logs_url).to be_nil
      end
    end

    context 'when pipeline has multiple logs' do
      let!(:second_job) { create(:ci_build, pipeline: workload.pipeline) }
      let!(:first_job) { create(:ci_build, pipeline: workload.pipeline) }

      it 'returns the url of the first job by id' do
        allow(Gitlab::Routing).to receive_message_chain(:url_helpers, :project_job_url)
          .with(workload.project, second_job).and_return('logs-url')

        expect(workload.logs_url).to eq('logs-url')
      end
    end

    context 'when the earliest job was retried' do
      let!(:retried_job) { create(:ci_build, :retried, pipeline: workload.pipeline) }
      let!(:latest_job) { create(:ci_build, pipeline: workload.pipeline) }

      it 'returns the url of the non-retried job' do
        allow(Gitlab::Routing).to receive_message_chain(:url_helpers, :project_job_url)
          .with(workload.project, latest_job).and_return('logs-url')

        expect(workload.logs_url).to eq('logs-url')
      end
    end
  end

  describe 'state transitions' do
    let(:workload_for_aasm) { build(:ci_workload) }

    using RSpec::Parameterized::TableSyntax
    where(:status, :can_finish, :can_drop) do
      0 | true  | true
      3 | false | true
      4 | true  | false
    end

    with_them do
      it 'adheres to state machine rules', :aggregate_failures do
        workload_for_aasm.status = status

        expect(workload_for_aasm.can_finish?).to eq(can_finish)
        expect(workload_for_aasm.can_drop?).to eq(can_drop)
      end
    end

    describe 'cleanup refs after transition to finished or failed' do
      let_it_be(:project) { create(:project, :small_repo) }
      let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
      let_it_be(:ref_path) { 'refs/workloads/7db' }
      # `freeze: false` is required in this spec: one or more `let_it_be` subjects
      # cannot be frozen by default (deep_freeze traversal failure, a non-AR
      # subject, or an in-memory mutation that survives reload/refind). Do not
      # drop these opt-outs or convert them to `let_it_be_with_reload`/`refind`
      # (see gitlab-org/gitlab#602925).
      let_it_be(:workload, freeze: false) do
        create(:ci_workload, project: project, pipeline: pipeline, branch_name: ref_path)
      end

      before do
        project.repository.create_ref(project.commit.id, ref_path)
      end

      context 'when workload finishes' do
        it 'cleans up the workload ref' do
          expect(project.repository).to receive(:delete_refs).with(workload.ref_path)

          workload.finish!
        end
      end

      context 'when workload fails' do
        it 'cleans up the workload ref' do
          expect(project.repository).to receive(:delete_refs).with(workload.ref_path)

          workload.drop!
        end
      end
    end
  end

  describe '.workload_ref?' do
    it 'returns true for workload refs' do
      expect(described_class.workload_ref?("refs/#{Repository::REF_WORKLOADS}/123")).to be true
    end

    it 'returns false for non-workload refs' do
      expect(described_class.workload_ref?('refs/heads/main')).to be false
      expect(described_class.workload_ref?('refs/tags/v1.0')).to be false
      expect(described_class.workload_ref?('refs/merge-requests/1/head')).to be false
    end
  end

  describe '#cleanup_refs' do
    let_it_be(:project) { create(:project, :small_repo) }
    let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
    let(:ref_path) { 'refs/workloads/test123' }
    let(:workload) { create(:ci_workload, project: project, pipeline: pipeline, branch_name: ref_path) }

    context 'when ref exists' do
      before do
        project.repository.create_ref(project.commit.id, ref_path)
      end

      it 'deletes the ref' do
        expect(project.repository).to receive(:delete_refs).with(ref_path)

        workload.send(:cleanup_refs)
      end
    end

    context 'when ref does not exist' do
      let(:ref_path) { 'refs/workloads/non-existent-ref' }

      it 'returns early without attempting to delete' do
        expect(project.repository).not_to receive(:delete_refs)

        workload.send(:cleanup_refs)
      end
    end

    context 'when ref is a branch' do
      let(:ref_path) { 'workloads/123' }

      before do
        project.repository.create_branch(ref_path, project.default_branch)
      end

      it 'does not delete the branch' do
        expect(project.repository).not_to receive(:delete_refs).with(ref_path)

        workload.send(:cleanup_refs)
      end
    end

    context 'when deletion raises an error' do
      before do
        project.repository.create_ref(project.commit.id, ref_path)
        allow(project.repository).to receive(:delete_refs).and_raise(StandardError, 'Deletion failed')
      end

      it 'logs the error' do
        expect(Gitlab::AppLogger).to receive(:error).with("Failed to cleanup workload ref #{ref_path}: Deletion failed")

        workload.send(:cleanup_refs)
      end
    end
  end
end
