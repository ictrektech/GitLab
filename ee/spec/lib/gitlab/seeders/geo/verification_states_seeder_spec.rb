# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Seeders::Geo::VerificationStatesSeeder, feature_category: :geo_replication do
  subject(:seeder) { described_class.new }

  before do
    allow(seeder).to receive(:print)
    allow(seeder).to receive(:warn)

    allow_next_instance_of(Gitlab::Seeders::Geo::UploadPartitions) do |upload_seeder|
      allow(upload_seeder).to receive(:log)
    end
  end

  def stub_models(models)
    allow(Gitlab::Geo::ModelMapper).to receive(:available_models).and_return(models)
  end

  def state_value(name)
    Geo::VerificationState::VERIFICATION_STATE_VALUES[name]
  end

  describe '#seed!' do
    context 'with the real replicable models' do
      it 'derives every state table and skips them all when no parent records exist', :aggregate_failures do
        expect { seeder.seed! }.not_to raise_error

        expect(Geo::ProjectUploadState.count).to eq(0)
        expect(Geo::ContainerRepositoryState.count).to eq(0)
        expect(Geo::JobArtifactState.count).to eq(0)
        expect(seeder).to have_received(:warn)
          .with(a_string_including('Skipped Geo verification state tables'))
        expect(seeder).to have_received(:warn).with(a_string_including('project_upload_states'))
      end
    end

    context 'when parent records exist' do
      before do
        stub_models([Geo::ProjectUpload, ContainerRepository, Ci::JobArtifact, Ci::PipelineArtifact,
          MergeRequestDiff])
      end

      let_it_be(:project_uploads) { create_list(:geo_project_upload, 3) }
      let_it_be(:container_repositories) { create_list(:container_repository, 3) }
      let_it_be(:job_artifacts) { create_list(:ci_job_artifact, 3) }
      let_it_be(:pipeline_artifacts) { create_list(:ci_pipeline_artifact, 3) }
      let_it_be(:merge_request) { create(:merge_request) }
      let_it_be(:merge_request_diffs) { create_list(:merge_request_diff, 3, merge_request: merge_request) }

      it 'seeds one pending, one succeeded and one failed row per table', :aggregate_failures do
        seeder.seed!

        [Geo::ProjectUploadState, Geo::ContainerRepositoryState, Geo::JobArtifactState,
          Geo::PipelineArtifactState, MergeRequestDiffDetail].each do |state_class|
          expect(state_class.count).to eq(3)
          expect(state_class.pluck(:verification_state)).to contain_exactly(
            state_value(:verification_pending),
            state_value(:verification_succeeded),
            state_value(:verification_failed)
          )
        end

        succeeded = Geo::ProjectUploadState.find_by(verification_state: state_value(:verification_succeeded))
        expect(succeeded.verification_checksum).to be_present
        expect(succeeded.verified_at).to be_present

        failed = Geo::ProjectUploadState.find_by(verification_state: state_value(:verification_failed))
        expect(failed.verification_failure.length).to eq(255)
        expect(failed.verification_retry_count).to eq(1)

        pending = Geo::ProjectUploadState.find_by(verification_state: state_value(:verification_pending))
        expect(pending.verification_checksum).to be_nil
        expect(pending.verified_at).to be_nil
        expect(pending.verification_failure).to be_nil
      end

      it 'populates sharding keys and partition values from the parent row', :aggregate_failures do
        seeder.seed!

        Geo::ProjectUploadState.find_each do |state|
          expect(state.project_id).to eq(Geo::ProjectUpload.find(state.project_upload_id).project_id)
        end

        Geo::JobArtifactState.find_each do |state|
          expect(state.partition_id).to eq(Ci::JobArtifact.find(state.job_artifact_id).partition_id)
        end

        Geo::PipelineArtifactState.find_each do |state|
          expect(state.partition_id).to eq(Ci::PipelineArtifact.find(state.pipeline_artifact_id).partition_id)
        end
      end

      it 'does not copy the parent id into the state id column' do
        allow(Geo::ProjectUploadState).to receive(:insert_all).and_call_original

        seeder.seed!

        expect(Geo::ProjectUploadState).to have_received(:insert_all) do |rows, **_options|
          expect(rows.flat_map(&:keys).map(&:to_s)).not_to include('id')
        end
      end

      it 'changes nothing when run twice' do
        seeder.seed!

        second_run = described_class.new
        allow(second_run).to receive_messages(print: nil, warn: nil)

        expect { second_run.seed! }
          .to not_change { Geo::ProjectUploadState.count }
          .and not_change { Geo::ContainerRepositoryState.count }
          .and not_change { Geo::JobArtifactState.count }
          .and not_change { Geo::PipelineArtifactState.count }
          .and not_change { MergeRequestDiffDetail.count }
          .and not_change { Upload.count }
      end

      it 'seeds only the first parents up to the per-table limit' do
        create(:geo_project_upload)

        seeder.seed!

        expect(Geo::ProjectUploadState.pluck(:project_upload_id)).to match_array(project_uploads.map(&:id))
      end

      it 'fails fast when a table cannot be seeded', :aggregate_failures do
        allow(Geo::ProjectUploadState).to receive(:insert_all)
          .and_raise(ActiveRecord::StatementInvalid.new('boom'))

        expect { seeder.seed! }.to raise_error(ActiveRecord::StatementInvalid, /boom/)

        expect(Geo::ContainerRepositoryState.count).to eq(0)
        expect(Geo::JobArtifactState.count).to eq(0)
      end
    end

    context 'when an upload partition is empty and its model has no records' do
      let_it_be(:project) { create(:project) }

      before do
        stub_models([Geo::AchievementUpload])
      end

      it 'creates the attach-target and its uploads through UploadPartitions', :aggregate_failures do
        expect { seeder.seed! }.to change { Achievements::Achievement.count }.from(0)

        expect(Geo::AchievementUpload.count).to eq(3)
        expect(Geo::AchievementUploadState.count).to eq(3)
      end
    end

    context 'when an upload partition has fewer rows than needed' do
      let_it_be(:project_upload) { create(:geo_project_upload) }

      before do
        stub_models([Geo::ProjectUpload])
      end

      it 'tops up the partition through the uploads parent table', :aggregate_failures do
        seeder.seed!

        expect(Geo::ProjectUpload.count).to eq(3)
        expect(Geo::ProjectUploadState.count).to eq(3)
      end

      it 'changes nothing when run twice' do
        seeder.seed!

        second_run = described_class.new
        allow(second_run).to receive_messages(print: nil, warn: nil)

        expect { second_run.seed! }
          .to not_change { Upload.count }
          .and not_change { Geo::ProjectUploadState.count }
      end
    end
  end
end
