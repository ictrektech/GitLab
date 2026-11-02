# frozen_string_literal: true

require "json"
require "tmpdir"
require "fast_spec_helper"

require_relative "../../../../../tooling/lib/tooling/predictive_tests/file_based_selection_runner"

RSpec.describe Tooling::PredictiveTests::FileBasedSelectionRunner, feature_category: :tooling do
  include StubENV

  subject(:runner) { described_class.new(clickhouse_client: clickhouse_client) }

  let(:clickhouse_client) { instance_double(GitlabQuality::TestTooling::ClickHouse::Client, insert_json_data: nil) }

  let(:changed_files) { ['app/models/user.rb'] }
  let(:find_changes_double) { instance_double(Tooling::FindChanges, execute: changed_files) }
  let(:git_changes_double) { instance_double(Tooling::PredictiveTests::GitChanges, since_last_capture: []) }

  let(:selected_specs) { ['spec/models/user_spec.rb'] }
  let(:selector_result) do
    Tooling::PredictiveTests::FileBasedSelector::Result.new(
      specs: selected_specs,
      full_suite_reason: nil
    )
  end

  let(:selector_double) { instance_double(Tooling::PredictiveTests::FileBasedSelector, execute: selector_result) }

  let(:ci_env) do
    {
      'CI_PROJECT_PATH' => 'gitlab-org/gitlab',
      'CI_PIPELINE_ID' => '99',
      'CI_JOB_ID' => '42',
      'CI_MERGE_REQUEST_IID' => '7',
      'CI_COMMIT_SHA' => 'abc123',
      'CI_MERGE_REQUEST_DIFF_BASE_SHA' => 'base456',
      'CI_MERGE_REQUEST_SOURCE_BRANCH_SHA' => ''
    }
  end

  before do
    stub_env(ci_env)

    allow(Tooling::FindChanges).to receive(:new).with(from: :api).and_return(find_changes_double)
    allow(Tooling::PredictiveTests::GitChanges).to receive(:new).and_return(git_changes_double)
    allow(Tooling::PredictiveTests::FileBasedSelector).to receive(:new).and_return(selector_double)
  end

  around do |example|
    Dir.mktmpdir("fbs-runner") do |tmpdir|
      Dir.chdir(tmpdir) { example.run }
    end
  end

  describe '#execute' do
    context 'when a subset is selected' do
      it 'inserts one row with all columns' do
        runner.execute

        expect(clickhouse_client).to have_received(:insert_json_data).with(
          'file_based_selection_runs',
          [hash_including(
            ci_project_path: 'gitlab-org/gitlab',
            ci_pipeline_id: 99,
            ci_job_id: 42,
            ci_merge_request_iid: 7,
            head_sha: 'abc123',
            base_sha: 'base456',
            full_suite_reason: '',
            changed_files: changed_files,
            selected_specs: selected_specs
          )]
        )
      end

      it 'inserts a timestamp in microsecond format' do
        runner.execute

        expect(clickhouse_client).to have_received(:insert_json_data).with(
          'file_based_selection_runs',
          [hash_including(timestamp: match(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{6}\z/))]
        )
      end

      it 'writes the artifact file' do
        runner.execute

        # rubocop:disable Gitlab/Json -- no Rails environment in this spec
        artifact = JSON.parse(File.read('file_based_selection.json'))
        # rubocop:enable Gitlab/Json
        expect(artifact).to eq(
          'full_suite_reason' => nil,
          'specs' => selected_specs,
          'changed_files' => changed_files
        )
      end

      it 'prints the selected specs' do
        expect { runner.execute }.to output(
          include('Changed files: 1', 'Selected 1 rspec files:', 'spec/models/user_spec.rb', 'By test level: unit 1')
        ).to_stdout
      end
    end

    context 'when the full suite is required' do
      let(:selector_result) do
        Tooling::PredictiveTests::FileBasedSelector::Result.new(
          specs: [],
          full_suite_reason: "map is stale: 8 hours"
        )
      end

      it 'inserts a row with the reason and empty selected_specs' do
        runner.execute

        expect(clickhouse_client).to have_received(:insert_json_data).with(
          'file_based_selection_runs',
          [hash_including(full_suite_reason: 'map is stale: 8 hours', selected_specs: [])]
        )
      end

      it 'prints the full-suite reason' do
        expect { runner.execute }.to output(include('Would run the full suite: map is stale: 8 hours')).to_stdout
      end
    end

    context 'when the insert raises' do
      before do
        allow(clickhouse_client).to receive(:insert_json_data).and_raise(RuntimeError, 'CH error')
      end

      it 'warns to stderr instead of raising' do
        expect { runner.execute }.to output(include('Warning: failed to record run in ClickHouse: CH error')).to_stderr
      end

      it 'still writes the artifact and prints the selection' do
        expect { runner.execute }.to output(include('Selected 1 rspec files:')).to_stdout
        expect(File).to exist('file_based_selection.json')
      end
    end

    it 'passes CI_PROJECT_PATH and CI_MERGE_REQUEST_DIFF_BASE_SHA to GitChanges' do
      expect(Tooling::PredictiveTests::GitChanges).to receive(:new).with(
        hash_including(project_path: 'gitlab-org/gitlab', base_sha: 'base456')
      ).and_return(git_changes_double)

      runner.execute
    end

    it 'passes CI_PROJECT_PATH to FileBasedSelector' do
      expect(Tooling::PredictiveTests::FileBasedSelector).to receive(:new).with(
        hash_including(project_path: 'gitlab-org/gitlab')
      ).and_return(selector_double)

      runner.execute
    end

    context 'when CI_MERGE_REQUEST_SOURCE_BRANCH_SHA is set' do
      let(:ci_env) { super().merge('CI_MERGE_REQUEST_SOURCE_BRANCH_SHA' => 'source789') }

      it 'uses it as head_sha instead of CI_COMMIT_SHA' do
        runner.execute

        expect(clickhouse_client).to have_received(:insert_json_data).with(
          'file_based_selection_runs',
          [hash_including(head_sha: 'source789')]
        )
      end
    end

    context 'when CI_MERGE_REQUEST_SOURCE_BRANCH_SHA is absent' do
      it 'falls back to CI_COMMIT_SHA as head_sha' do
        runner.execute

        expect(clickhouse_client).to have_received(:insert_json_data).with(
          'file_based_selection_runs',
          [hash_including(head_sha: 'abc123')]
        )
      end
    end
  end
end
