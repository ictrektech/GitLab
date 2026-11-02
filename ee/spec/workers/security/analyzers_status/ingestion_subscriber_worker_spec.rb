# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::AnalyzersStatus::IngestionSubscriberWorker, feature_category: :security_asset_inventories do
  let_it_be(:project) { create(:project, :small_repo) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project, ref: project.default_branch) }

  let(:event) { ::Security::ReportsIngestedEvent.new(data: { pipeline_id: pipeline.id }) }

  it_behaves_like 'worker with data consistency', described_class, data_consistency: :sticky
  it_behaves_like 'subscribes to event'
  it_behaves_like 'an idempotent worker'

  describe '#handle_event' do
    subject(:use_event) { consume_event(subscriber: described_class, event: event) }

    context 'when the pipeline exists' do
      it 'enqueues PipelineAnalyzersStatusUpdateWorker with the pipeline id' do
        expect(::Security::PipelineAnalyzersStatusUpdateWorker).to receive(:perform_async).with(pipeline.id)

        use_event
      end

      context 'when the pipeline is not on the default branch' do
        let_it_be(:feature_branch_pipeline) { create(:ci_pipeline, project: project, ref: 'feature') }
        let(:event) { ::Security::ReportsIngestedEvent.new(data: { pipeline_id: feature_branch_pipeline.id }) }

        it 'does not enqueue PipelineAnalyzersStatusUpdateWorker' do
          expect(::Security::PipelineAnalyzersStatusUpdateWorker).not_to receive(:perform_async)

          use_event
        end
      end
    end

    context 'when the pipeline is a business logic security scan of the default branch' do
      let_it_be(:agentic_scan_pipeline) do
        create(:ci_pipeline, project: project, ref: 'refs/workloads/abc123', source: :duo_workflow,
          sha: project.commit(project.default_branch).id)
      end

      let(:event) { ::Security::ReportsIngestedEvent.new(data: { pipeline_id: agentic_scan_pipeline.id }) }

      it 'enqueues PipelineAnalyzersStatusUpdateWorker' do
        expect(::Security::PipelineAnalyzersStatusUpdateWorker).to receive(:perform_async)
          .with(agentic_scan_pipeline.id)

        use_event
      end

      context 'when agentic_analyzer_security_ingestion is disabled' do
        before do
          stub_feature_flags(agentic_analyzer_security_ingestion: false)
        end

        it 'does not enqueue PipelineAnalyzersStatusUpdateWorker' do
          expect(::Security::PipelineAnalyzersStatusUpdateWorker).not_to receive(:perform_async)

          use_event
        end
      end
    end

    context 'when the pipeline does not exist' do
      let(:event) { ::Security::ReportsIngestedEvent.new(data: { pipeline_id: non_existing_record_id }) }

      it 'does not enqueue PipelineAnalyzersStatusUpdateWorker' do
        expect(::Security::PipelineAnalyzersStatusUpdateWorker).not_to receive(:perform_async)

        use_event
      end
    end
  end
end
