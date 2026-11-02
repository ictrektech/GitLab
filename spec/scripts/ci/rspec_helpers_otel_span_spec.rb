# frozen_string_literal: true

require 'fast_spec_helper'
require 'open3'
require 'tmpdir'
require 'yaml'

RSpec.describe 'RSpec helper span instrumentation', feature_category: :tooling do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:root) { File.expand_path('../../..', __dir__) }
  let(:exporter_log) { File.join(tmp_dir, 'spans.log') }
  let(:fake_exporter) do
    File.join(tmp_dir, 'exporter.rb').tap do |path|
      File.write(path, <<~RUBY)
        require '#{root}/scripts/ci/otel_span_exporter'
        if ARGV == ['--prepare-context']
          OtelSpanExporter.run(ARGV)
        else
          File.open(ENV.fetch('SPAN_LOG'), 'a') { |file| file.puts(ARGV.join(' ')) }
          span = OtelSpanExporter.parse(ARGV)
          File.open(ENV.fetch('SPAN_LOG') + '.jsonl', 'a') do |file|
            file.puts(JSON.generate(name: span.name, attributes: OtelSpanFailureClassifier.attributes(span)))
          end
        end
      RUBY
    end
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  def run_helper(script)
    Open3.capture3(
      {
        'GLCI_OTEL_ENDPOINT' => 'https://example.com',
        'GLCI_OTEL_SPAN_EXPORTER' => fake_exporter,
        'CI_TRACEPARENT' => '00-00000000000000000000000000000001-1234567890abcdef-01',
        'SPAN_LOG' => exporter_log
      },
      'bash', '-c', <<~SH, chdir: tmp_dir
        set -eo pipefail
        . '#{root}/scripts/utils.sh'
        . '#{root}/scripts/rspec_helpers.sh'
        echoinfo() { :; }
        echosuccess() { :; }
        echoerr() { :; }
        #{script}
      SH
    )
  end

  def spans
    File.readlines(exporter_log).map { |line| line.scan(/--([a-z-]+) (\S+)/).to_h }
  end

  context 'with a CI configuration validation job' do
    where(:job_suffix, :spec_file, :exit_code) do
      [
        ['branch-pipelines', 'branch_pipeline_spec.rb', 0],
        ['pipeline-labels', 'pipeline_labels_spec.rb', 1],
        ['mr-pipelines', 'merge_request_pipeline_spec.rb', 2]
      ]
    end

    with_them do
      let(:job_script) do
        config = YAML.parse_file(File.join(root, '.gitlab/ci/rails.gitlab-ci.yml')).root
        job = config.children.each_slice(2).find do |key, _|
          key.value == "rspec ci-config-validation #{job_suffix}"
        end.last
        script = job.children.each_slice(2).find { |key, _| key.value == 'script' }.last
        script.children.last.value
      end

      it 'exports the attempt and preserves the command arguments and exit status' do
        stdout, _, status = run_helper(<<~SH)
          CI_JOB_ID=2
          rspec_args() {
            printf '%s\\n' "$1" > arguments.txt
            echo '--tag example'
          }
          mkdir bin
          printf '#!/bin/sh\\nexit #{exit_code}\\n' > bin/rspec
          chmod +x bin/rspec
          #{job_script}
          echo completed
        SH

        expect(File.read(File.join(tmp_dir, 'arguments.txt')).strip).to eq(
          "--tag ci_config_validation -- spec/dot_gitlab_ci/ci_configuration_validation/#{spec_file}")
        expect(status.exitstatus).to eq(exit_code)
        expect(stdout.include?('completed')).to eq(exit_code == 0)
        expect(spans).to contain_exactly(a_hash_including('name' => 'rspec-initial',
          'exit-code' => exit_code.to_s, 'operation-kind' => 'test', 'operation-name' => 'rspec',
          'attempt' => '1', 'rspec-report' => 'rspec/rspec-2.json'))
      end
    end
  end

  it 'exports the initial RSpec attempt before retry handling exits the shell' do
    _, _, status = run_helper(<<~SH)
      CI_JOB_NAME='rspec unit'
      CI_PROJECT_ID=1
      CI_JOB_ID=2
      KNAPSACK_RSPEC_SUITE_REPORT_PATH=knapsack.json
      FLAKY_RSPEC_SUITE_REPORT_PATH=flaky.json
      ruby() {
        case "$*" in
          *tooling/quality/test_level.rb*) echo spec ;;
          *) command ruby "$@" ;;
        esac
      }
      rspec_args() { echo '--tag example'; }
      debug_rspec_variables() { :; }
      debug_shell_options() { :; }
      bundle() { return 3; }
      handle_retry_rspec_in_new_process() { exit "$1"; }
      rspec_parallelized_job
    SH

    expect(status.exitstatus).to eq(3)
    expect(spans).to contain_exactly(a_hash_including('name' => 'rspec-initial', 'exit-code' => '3',
      'operation-kind' => 'test', 'operation-name' => 'rspec', 'attempt' => '1',
      'rspec-report' => 'rspec/rspec-2.json'))
  end

  it 'keeps failed E2E attempts visible when the retry succeeds' do
    _, _, status = run_helper(<<~SH)
      CI_JOB_ID=2
      QA_RUN_IN_PARALLEL=false
      mkdir tmp
      touch tmp/rspec-2-retried-true.xml tmp/rspec-2-retried-false.xml
      is_rspec_last_run_results_file_missing() { return 1; }
      last_run_has_no_failures() { return 1; }
      bundle() {
        case "$*" in
          *junit_merge*|*--only-failures*) return 0 ;;
          *) return 3 ;;
        esac
      }
      run_e2e_specs https://example.com '' ''
    SH

    expect(status.exitstatus).to eq(0)
    expect(spans).to contain_exactly(
      a_hash_including('name' => 'e2e-initial', 'exit-code' => '3', 'operation-name' => 'e2e', 'attempt' => '1'),
      a_hash_including('name' => 'e2e-retry', 'exit-code' => '0', 'operation-name' => 'e2e', 'attempt' => '2')
    )
  end

  it 'exports a successful E2E attempt without retrying' do
    _, _, status = run_helper(<<~SH)
      bundle() { return 0; }
      retry_failed_e2e_rspec_examples() { exit 99; }
      run_e2e_specs https://example.com '' ''
    SH

    expect(status.exitstatus).to eq(0)
    expect(spans).to contain_exactly(a_hash_including('name' => 'e2e-initial', 'exit-code' => '0'))
  end

  context 'with structured E2E reports' do
    where(:parallel, :report_suffix, :report_count) do
      [['false', '', '1'], ['true', '-%{worker}', '2']]
    end

    with_them do
      it 'classifies the initial failure independently of a successful retry' do
        _, _, status = run_helper(<<~SH)
          CI_JOB_ID=2
          QA_RUN_IN_PARALLEL=#{parallel}
          QA_PARALLEL_PROCESSES=#{report_count}
          mkdir tmp
          is_rspec_last_run_results_file_missing() { return 1; }
          last_run_has_no_failures() { return 1; }
          bundle() {
            if [[ "$*" == *--only-failures* ]]; then
              ruby -rjson -e 'File.write("tmp/rspec-2-retried-true.json", JSON.generate(summary: { failure_count: 0, errors_outside_of_examples_count: 0 }))'
              return 0
            fi
            ruby -rjson -e '#{report_count}.times { |i| File.write("tmp/rspec-2-retried-false#{report_suffix}.json".gsub("%{worker}", (i + 1).to_s), JSON.generate(summary: { failure_count: i == 0 ? 1 : 0, errors_outside_of_examples_count: 0 })) }'
            return 1
          }
          run_e2e_specs https://example.com '' ''
        SH

        expect(status.exitstatus).to eq(0)
        expect(File.readlines("#{exporter_log}.jsonl").map { |line| Gitlab::Json::SafeParser.parse(line) }).to eq([
          { 'name' => 'e2e-initial', 'attributes' => {
            'gitlab.cicd.failure.category' => 'user:test:failure', 'gitlab.cicd.failure.source' => 'rspec_report'
          } },
          { 'name' => 'e2e-retry', 'attributes' => {} }
        ])
        expect(spans).to contain_exactly(
          a_hash_including('rspec-report' => "tmp/rspec-2-retried-false#{report_suffix}.json",
            'rspec-report-count' => report_count, 'exit-code' => '1'),
          a_hash_including('rspec-report' => 'tmp/rspec-2-retried-true.json',
            'rspec-report-count' => '1', 'exit-code' => '0')
        )
      end
    end
  end

  context 'with an RSpec retry' do
    where(:retry_exit_code) { [0, 4] }

    with_them do
      it 'exports the retry attempt and preserves its status' do
        _, _, status = run_helper(<<~SH)
          RETRY_FAILED_TESTS_IN_NEW_PROCESS=true
          RSPEC_LAST_RUN_RESULTS_FILE=examples.txt
          RSPEC_RETRIED_TESTS_REPORT_PATH=retried.txt
          CI_JOB_ID=2
          CI_JOB_URL=https://example.com/job/2
          echo 'example failed' > examples.txt
          is_rspec_last_run_results_file_missing() { return 1; }
          install_junit_merge_gem() { :; }
          rspec_simple_job() { return #{retry_exit_code}; }
          junit_merge() { :; }
          warn_on_successfully_retried_test() { :; }
          mkdir scripts
          printf '#!/bin/sh\nexit 0\n' > scripts/merge-reports
          chmod +x scripts/merge-reports
          retry_failed_rspec_examples 3
        SH

        expect(status.exitstatus).to eq(retry_exit_code)
        expect(spans).to contain_exactly(
          a_hash_including('name' => 'rspec-retry', 'exit-code' => retry_exit_code.to_s,
            'operation-name' => 'rspec', 'attempt' => '2', 'rspec-report' => 'rspec/rspec-retry-2.json')
        )
      end
    end
  end

  it 'preserves the terminal E2E retry failure' do
    _, _, status = run_helper(<<~SH)
      CI_JOB_ID=2
      QA_RUN_IN_PARALLEL=false
      mkdir tmp
      touch tmp/rspec-2-retried-true.xml tmp/rspec-2-retried-false.xml
      is_rspec_last_run_results_file_missing() { return 1; }
      last_run_has_no_failures() { return 1; }
      bundle() { case "$*" in *junit_merge*) return 0 ;; *) return 4 ;; esac; }
      run_e2e_specs https://example.com '' ''
    SH

    expect(status.exitstatus).to eq(4)
    expect(spans).to contain_exactly(
      a_hash_including('name' => 'e2e-initial', 'exit-code' => '4'),
      a_hash_including('name' => 'e2e-retry', 'exit-code' => '4')
    )
  end
end
