# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanResultPolicies::ProcessPipelineCompletionWorker, feature_category: :security_policy_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
  let_it_be(:pipeline_finished_event) do
    Ci::PipelineFinishedEvent.new(
      data: {
        pipeline_id: pipeline.id,
        status: 'success',
        source: 'push',
        partition_id: pipeline.partition_id
      }
    )
  end

  let_it_be(:reports_ingested_event) do
    Security::ReportsIngestedEvent.new(data: { pipeline_id: pipeline.id })
  end

  let(:feature_licensed) { true }
  let(:can_store_security_reports) { true }

  subject(:perform) { consume_event(subscriber: described_class, event: event) }

  shared_examples 'syncs findings to approval rules' do
    it 'executes SyncFindingsToApprovalRulesService without the concurrency-limited worker' do
      expect_next_instance_of(Security::ScanResultPolicies::SyncFindingsToApprovalRulesService, pipeline) do |service|
        expect(service).to receive(:execute)
      end
      expect(Security::ScanResultPolicies::SyncFindingsToApprovalRulesWorker).not_to receive(:perform_async)

      perform
    end
  end

  shared_examples 'does not sync findings to approval rules' do
    it 'does not sync findings to approval rules' do
      expect(Security::ScanResultPolicies::SyncFindingsToApprovalRulesService).not_to receive(:new)
      expect(Security::ScanResultPolicies::SyncFindingsToApprovalRulesWorker).not_to receive(:perform_async)

      perform
    end
  end

  before do
    stub_licensed_features(security_orchestration_policies: feature_licensed)
    allow_next_found_instance_of(Project) do |record|
      allow(record).to receive(:can_store_security_reports?).and_return(can_store_security_reports)
    end
  end

  describe 'subscriptions' do
    it_behaves_like 'subscribes to event' do
      let(:event) { pipeline_finished_event }

      it 'receives the event' do
        expect(described_class).to receive(:perform_async).with('Ci::PipelineFinishedEvent',
          pipeline_finished_event.data.deep_stringify_keys)
        ::Gitlab::EventStore.publish(event)
      end
    end

    it_behaves_like 'subscribes to event' do
      let(:event) { reports_ingested_event }

      it 'receives the event' do
        expect(described_class).to receive(:perform_async).with('Security::ReportsIngestedEvent',
          reports_ingested_event.data.deep_stringify_keys)
        ::Gitlab::EventStore.publish(event)
      end
    end
  end

  describe '#handle_event' do
    it_behaves_like 'an idempotent worker' do
      let(:event) { pipeline_finished_event }
    end

    context 'when triggered by PipelineFinishedEvent' do
      let(:event) { pipeline_finished_event }

      context 'when pipeline exists' do
        context 'when security orchestration policies feature is licensed' do
          context 'when project can store security reports' do
            context 'when scan results are ready' do
              before do
                allow(Security::Scan).to receive(:results_ready?).with(pipeline).and_return(true)
              end

              it_behaves_like 'syncs findings to approval rules'

              # results_ready? is true before StoreScansWorker creates any scan; ReportsIngestedEvent follows.
              context 'when security reports are not ingested yet' do
                before do
                  allow(Security::Scan).to receive(:ingestion_pending?).with(pipeline).and_return(true)
                end

                it_behaves_like 'does not sync findings to approval rules'
              end
            end

            context 'when scan results are not ready' do
              before do
                allow(Security::Scan).to receive(:results_ready?).with(pipeline).and_return(false)
              end

              it_behaves_like 'does not sync findings to approval rules'
            end
          end

          context 'when project cannot store security reports' do
            let(:can_store_security_reports) { false }

            it_behaves_like 'does not sync findings to approval rules'
          end
        end

        context 'when security orchestration policies feature is not licensed' do
          let(:feature_licensed) { false }

          it_behaves_like 'does not sync findings to approval rules'
        end
      end

      context 'when pipeline does not exist' do
        let(:event) do
          Ci::PipelineFinishedEvent.new(
            data: {
              pipeline_id: non_existing_record_id,
              status: 'success',
              source: 'push',
              partition_id: pipeline.partition_id
            }
          )
        end

        it_behaves_like 'does not sync findings to approval rules'
      end
    end

    context 'when triggered by ReportsIngestedEvent' do
      let(:event) { reports_ingested_event }

      it_behaves_like 'syncs findings to approval rules'

      context 'when project cannot store security reports' do
        let(:can_store_security_reports) { false }

        it_behaves_like 'does not sync findings to approval rules'
      end

      context 'when security orchestration policies feature is not licensed' do
        let(:feature_licensed) { false }

        it_behaves_like 'does not sync findings to approval rules'
      end

      context 'when pipeline does not exist' do
        let(:event) do
          Security::ReportsIngestedEvent.new(data: { pipeline_id: non_existing_record_id })
        end

        it_behaves_like 'does not sync findings to approval rules'
      end
    end
  end
end
