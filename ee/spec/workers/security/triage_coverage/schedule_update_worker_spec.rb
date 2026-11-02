# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::TriageCoverage::ScheduleUpdateWorker, feature_category: :security_asset_inventories do
  let(:worker) { described_class.new }
  let(:update_worker) { Security::TriageCoverage::UpdateWorker }

  before do
    allow(update_worker).to receive(:perform_in)
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [[non_existing_record_id]] }
  end

  describe '#perform' do
    context 'when scheduling by project_ids' do
      context 'when project_ids is empty' do
        it 'does not schedule any UpdateWorker jobs' do
          worker.perform([])

          expect(update_worker).not_to have_received(:perform_in)
        end
      end

      context 'when project_ids is nil' do
        it 'does not schedule any UpdateWorker jobs' do
          worker.perform(nil)

          expect(update_worker).not_to have_received(:perform_in)
        end
      end

      context 'when project_ids count is greater than batch size' do
        let(:project_ids) { [1, 2, 3, 4, 5] }

        before do
          stub_const("#{described_class}::BATCH_SIZE", 2)
        end

        it 'schedules multiple UpdateWorker jobs with correct batches and delays' do
          worker.perform(project_ids)

          expect(update_worker).to have_received(:perform_in).exactly(3).times
          expect(update_worker).to have_received(:perform_in).with(described_class::DELAY * 0, [1, 2])
          expect(update_worker).to have_received(:perform_in).with(described_class::DELAY * 1, [3, 4])
          expect(update_worker).to have_received(:perform_in).with(described_class::DELAY * 2, [5])
        end
      end
    end

    context 'when scheduling by scan_profile_id' do
      let_it_be(:profile) { create(:security_scan_profile) }

      context 'when no projects are attached to the profile' do
        it 'does not schedule any UpdateWorker jobs' do
          worker.perform(nil, profile.id)

          expect(update_worker).not_to have_received(:perform_in)
        end
      end

      context 'when projects are attached to the profile' do
        let_it_be(:project1) { create(:project) }
        let_it_be(:project2) { create(:project) }

        before do
          create(:security_scan_profile_project, scan_profile: profile, project: project1)
          create(:security_scan_profile_project, scan_profile: profile, project: project2)
        end

        it 'schedules an UpdateWorker job for the attached projects' do
          worker.perform(nil, profile.id)

          expect(update_worker).to have_received(:perform_in)
            .with(described_class::DELAY * 0, contain_exactly(project1.id, project2.id))
        end

        context 'when there is more than one batch' do
          before do
            stub_const("#{described_class}::BATCH_SIZE", 1)
          end

          it 'schedules one UpdateWorker job per batch with increasing delays and disjoint project ids' do
            worker.perform(nil, profile.id)

            expect(update_worker).to have_received(:perform_in).exactly(2).times
            expect(update_worker).to have_received(:perform_in).with(described_class::DELAY * 0, [project1.id])
            expect(update_worker).to have_received(:perform_in).with(described_class::DELAY * 1, [project2.id])
          end
        end
      end
    end
  end
end
