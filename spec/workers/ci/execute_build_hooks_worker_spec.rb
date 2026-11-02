# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::ExecuteBuildHooksWorker, feature_category: :pipeline_composition do
  let_it_be(:project, refind: true) { create(:project) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
  let_it_be(:build) { create(:ci_build, pipeline: pipeline) }

  let(:started_at) { 3.minutes.ago }

  let(:build_state) do
    {
      'build_status' => 'running',
      'build_started_at' => started_at,
      'build_finished_at' => nil,
      'build_duration' => nil
    }
  end

  describe '#perform' do
    subject(:perform) { described_class.new.perform(project.id, build.id, build_state) }

    context 'when the project exists' do
      before do
        allow(Project).to receive(:find_by_id).with(project.id).and_return(project)
      end

      context 'with project hooks' do
        let!(:hook) { create(:project_hook, project: project, job_events: true) }

        it 'executes hooks with the build payload' do
          expect(project).to receive(:execute_hooks)
            .with(hash_including('object_kind' => 'build', 'build_id' => build.id), :job_hooks)

          perform
        end
      end

      context 'with project integrations' do
        let!(:integration) { create(:integration, active: true, job_events: true, project: project) }

        it 'executes integrations with the build payload' do
          expect(project).to receive(:execute_integrations)
            .with(hash_including('object_kind' => 'build', 'build_id' => build.id), :job_hooks)

          perform
        end
      end

      context 'without hooks or integrations' do
        it 'does not execute hooks or integrations' do
          expect(project).not_to receive(:execute_hooks)
          expect(project).not_to receive(:execute_integrations)

          perform
        end
      end

      it 'builds the payload in the worker and pins the snapshot fields' do
        allow(project).to receive(:has_active_hooks?).and_return(true)

        expect(project).to receive(:execute_hooks) do |data, _hook_type|
          expect(data[:object_kind]).to eq('build')
          expect(data[:build_id]).to eq(build.id)
          expect(data[:build_status]).to eq('running')
          expect(data[:build_started_at]).to eq(started_at)
          expect(data[:build_started_at_iso]).to eq(started_at.iso8601)
          expect(data[:build_finished_at]).to be_nil
          expect(data[:build_finished_at_iso]).to be_nil
          expect(data[:build_duration]).to be_nil
        end

        perform
      end

      it 'derives the ISO timestamps when the values arrive as strings' do
        serialized = build_state.merge('build_started_at' => '2026-09-10T15:04:05Z')

        allow(project).to receive(:has_active_hooks?).and_return(true)

        expect(project).to receive(:execute_hooks) do |data, _hook_type|
          expect(data[:build_started_at_iso]).to eq('2026-09-10T15:04:05Z')
        end

        described_class.new.perform(project.id, build.id, serialized)
      end

      it 'keeps the whole webhook payload, not just the pinned fields', :aggregate_failures do
        allow(project).to receive(:has_active_hooks?).and_return(true)

        expect(project).to receive(:execute_hooks) do |data, _hook_type|
          expect(data.keys).to include(
            'commit', 'repository', 'project', 'runner', 'user', 'environment'
          )
          expect(data['commit']['sha']).to eq(pipeline.sha)
          expect(data['repository']['name']).to eq(project.name)
        end

        perform
      end

      it 'does nothing when the build no longer exists' do
        allow(project).to receive(:has_active_hooks?).and_return(true)

        expect(project).not_to receive(:execute_hooks)
        expect(project).not_to receive(:execute_integrations)

        described_class.new.perform(project.id, non_existing_record_id, build_state)
      end

      it 'ignores a job enqueued with a build payload hash' do
        allow(project).to receive(:has_active_hooks?).and_return(true)

        expect(Ci::Build).not_to receive(:find_by_id)
        expect(project).not_to receive(:execute_hooks)
        expect(project).not_to receive(:execute_integrations)

        described_class.new.perform(project.id, { 'build_id' => build.id, 'build_status' => 'running' })
      end

      it 'logs the pinned build status' do
        worker = described_class.new

        expect(worker).to receive(:log_extra_metadata_on_done).with(:build_status, 'running')

        worker.perform(project.id, build.id, build_state)
      end
    end

    context 'with Datadog integration' do
      let!(:datadog) do
        integration = create(:datadog_integration,
          project: project,
          active: true,
          datadog_site: 'datadoghq.com',
          api_key: 'test_api_key',
          datadog_ci_visibility: true)

        integration.update!(job_events: true)
        integration
      end

      it 'executes the Datadog integration with the build payload' do
        expect(Integrations::ExecuteWorker).to receive(:perform_async)
          .with(datadog.id, hash_including('object_kind' => 'build'))

        perform
      end
    end

    context 'when the project does not exist' do
      it 'does not look up the build' do
        expect(Ci::Build).not_to receive(:find_by_id)

        described_class.new.perform(non_existing_record_id, build.id, build_state)
      end
    end
  end
end
