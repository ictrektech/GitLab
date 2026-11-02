# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ComplianceManagement::FrameworkEvaluationSchedulerWorker, feature_category: :compliance_management do
  describe '#perform' do
    let(:worker) { described_class.new }

    it_behaves_like 'an idempotent worker'

    context 'when frameworks exist', :clean_gitlab_redis_queues_metadata do
      let_it_be(:framework_1) { create(:compliance_framework) }
      let_it_be(:framework_2) { create(:compliance_framework) }
      let_it_be(:framework_without_projects) { create(:compliance_framework) }

      let_it_be(:projects) { create_list(:project, 7) }

      let(:expected_args) do
        [
          [framework_1.id, projects[0..1].map(&:id)],
          [framework_1.id, projects[2..3].map(&:id)],
          [framework_2.id, projects[4..5].map(&:id)],
          [framework_2.id, [projects[6].id]]
        ]
      end

      before do
        [framework_1, framework_2, framework_without_projects].each do |framework|
          create(:compliance_requirement, framework: framework).tap do |req|
            create(:compliance_requirements_control, compliance_requirement: req)
          end
        end

        projects[0..3].each do |project|
          create(:compliance_framework_project_setting,
            project: project,
            compliance_management_framework: framework_1)
        end

        projects[4..6].each do |project|
          create(:compliance_framework_project_setting,
            project: project,
            compliance_management_framework: framework_2)
        end

        stub_const("#{described_class}::PROJECT_BATCH_SIZE", 2)
        stub_const("#{described_class}::FRAMEWORK_BATCH_SIZE", 1)
      end

      it 'schedules evaluations in waves spread across the cron window' do
        expect(ComplianceManagement::ProjectComplianceEvaluatorWorker).to receive(:bulk_perform_in)
          .with(1.second, match_array(expected_args), batch_size: described_class::WAVE_SIZE, batch_delay: 5.minutes)

        worker.perform
      end

      it 'does not enqueue evaluations immediately' do
        expect(ComplianceManagement::ProjectComplianceEvaluatorWorker).not_to receive(:perform_async)

        worker.perform
      end

      it 'schedules each wave after the previous one' do
        stub_const("#{described_class}::WAVE_SIZE", 2)

        Sidekiq::Testing.fake! do
          freeze_time do
            worker.perform

            scheduled_at = ComplianceManagement::ProjectComplianceEvaluatorWorker.jobs.map { |job| job['at'].to_i }

            expect(scheduled_at.size).to eq(4)
            expect(scheduled_at.tally.values).to all(eq(2))
            expect(scheduled_at.uniq.sort).to eq([1.second.from_now.to_i, (1.second + 5.minutes).from_now.to_i])
          end
        end
      end

      context 'when the waves do not fit in the spread window at the maximum delay' do
        before do
          stub_const("#{described_class}::WAVE_SIZE", 1)
          stub_const("#{described_class}::SPREAD_WINDOW", 10.minutes)
        end

        it 'shortens the delay between waves to fit the window' do
          expect(ComplianceManagement::ProjectComplianceEvaluatorWorker).to receive(:bulk_perform_in)
            .with(1.second, match_array(expected_args), batch_size: 1, batch_delay: 150)

          worker.perform
        end
      end
    end

    context 'when no frameworks exist' do
      before do
        allow(ComplianceManagement::Framework)
          .to receive(:with_active_controls)
                .and_return(ComplianceManagement::Framework.none)
      end

      it 'does not schedule any jobs' do
        expect(ComplianceManagement::ProjectComplianceEvaluatorWorker)
          .not_to receive(:bulk_perform_in)

        worker.perform
      end
    end

    context 'when active frameworks have no project mappings' do
      before do
        allow(ComplianceManagement::Framework)
          .to receive(:active_framework_ids).and_return([non_existing_record_id])
      end

      it 'does not schedule any jobs' do
        expect(ComplianceManagement::ProjectComplianceEvaluatorWorker).not_to receive(:bulk_perform_in)

        worker.perform
      end
    end
  end
end
