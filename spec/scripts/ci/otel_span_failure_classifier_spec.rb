# frozen_string_literal: true

require 'fast_spec_helper'
require 'tmpdir'
require_relative '../../../scripts/ci/otel_span_exporter'

RSpec.describe OtelSpanFailureClassifier, feature_category: :tooling do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:report_path) { File.join(tmp_dir, 'rspec.json') }
  let(:start_time_ns) { Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond) - 1_000_000_000 }
  let(:exit_code) { 1 }
  let(:span) do
    OtelSpanExporter::Span.new(exit_code: exit_code, operation_kind: 'test',
      rspec_report: report_path, start_time_ns: start_time_ns)
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  def write_report(failures: 1, errors: 0)
    File.write(report_path, Gitlab::Json.dump(summary: {
      failure_count: failures, errors_outside_of_examples_count: errors
    }))
  end

  # Every category any scenario produces must be namespaced and must not claim the reserved `platform:`.
  def category
    value = described_class.attributes(span)['gitlab.cicd.failure.category']
    if value
      expect(value).to match(/\A[a-z0-9_]+(:[a-z0-9_]+)+\z/)
      expect(value).not_to start_with('platform:')
    end

    value
  end

  it 'classifies failed examples from the current attempt report' do
    write_report

    expect(described_class.attributes(span)).to eq(
      'gitlab.cicd.failure.category' => 'user:test:failure', 'gitlab.cicd.failure.source' => 'rspec_report'
    )
  end

  context 'with an outside-example error' do
    let(:exit_code) { 2 }

    it 'classifies framework errors including mixed example failures' do
      write_report(errors: 1)

      expect(category).to eq('user:test:framework_error')
    end

    it 'does not infer a framework error from the exit code alone' do
      write_report

      expect(category).to eq('user:unknown')
    end
  end

  it 'does not interpret an inconsistent failure exit code' do
    write_report(errors: 1)

    expect(category).to eq('user:unknown')
  end

  it 'does not classify successful recovery from an earlier failed report' do
    write_report
    span.exit_code = 0

    expect(described_class.attributes(span)).to be_empty
  end

  it 'does not claim an OOM kill for exit 137' do
    write_report
    span.exit_code = 137

    expect(category).to eq('user:unknown')
  end

  it 'does not classify reports for other operations' do
    write_report
    span.operation_kind = 'build'

    expect(category).to eq('user:unknown')
  end

  it 'omits stale reports from previous attempts' do
    write_report
    File.utime(Time.at(0), Time.at(0), report_path)

    expect(category).to eq('user:unknown')
  end

  it 'bounds report reading' do
    File.open(report_path, 'w') { |file| file.truncate(described_class::MAX_REPORT_BYTES + 1) }

    expect(category).to eq('user:unknown')
  end

  it 'does not block on named pipes' do
    system('mkfifo', report_path, exception: true)

    expect(category).to eq('user:unknown')
  end

  context 'when a report grows after its size is checked' do
    let(:report_file) do
      instance_double(File, stat: instance_double(File::Stat, file?: true, size: 10, mtime: Time.now),
        read: 'x' * (described_class::MAX_REPORT_BYTES + 1))
    end

    before do
      allow(File).to receive(:open).and_call_original
      allow(File).to receive(:open).with(report_path, File::RDONLY | File::NONBLOCK).and_yield(report_file)
    end

    it 'rejects the oversized content' do
      expect(category).to eq('user:unknown')
    end
  end

  it 'handles missing reports without changing status' do
    expect(category).to eq('user:unknown')
    expect(span.exit_code).to eq(1)
  end

  context 'without a configured report' do
    before do
      span.rspec_report = nil
    end

    it 'falls back to the command exit code' do
      expect(described_class.attributes(span)).to eq(
        'gitlab.cicd.failure.category' => 'user:unknown', 'gitlab.cicd.failure.source' => 'exit_code')
    end
  end

  context 'with malformed or incomplete reports' do
    where(:report) do
      ['invalid', '[]', '{}', '{"summary":{}}',
        '{"summary":{"failure_count":"1","errors_outside_of_examples_count":0}}',
        '{"summary":{"failure_count":-1,"errors_outside_of_examples_count":0}}']
    end

    with_them do
      it 'falls back to unknown without exposing report contents' do
        File.write(report_path, report)

        expect(described_class.attributes(span)).to eq(
          'gitlab.cicd.failure.category' => 'user:unknown', 'gitlab.cicd.failure.source' => 'exit_code'
        )
      end
    end
  end

  context 'with E2E worker reports' do
    let(:report_path) { File.join(tmp_dir, 'rspec-%{worker}.json') }
    let(:report_count) { '2' }
    let(:worker_failures) { 1 }
    let(:worker_errors) { 0 }
    let(:second_report) do
      Gitlab::Json.dump(summary: { failure_count: worker_failures, errors_outside_of_examples_count: worker_errors })
    end

    before do
      span.operation_name = 'e2e'
      span.rspec_report_count = report_count
      File.write(File.join(tmp_dir, 'rspec-1.json'), Gitlab::Json.dump(summary: {
        failure_count: 0, errors_outside_of_examples_count: 0
      }))
      File.write(File.join(tmp_dir, 'rspec-2.json'), second_report)
    end

    it 'combines all expected worker summaries' do
      expect(described_class.attributes(span)).to eq(
        'gitlab.cicd.failure.category' => 'user:test:failure', 'gitlab.cicd.failure.source' => 'rspec_report')
    end

    context 'when the QA runner collapses a framework error to exit 1' do
      let(:worker_errors) { 1 }

      it 'retains the framework error over example failures' do
        expect(category).to eq('user:test:framework_error')
      end
    end

    context 'when all reports passed despite a failing command' do
      let(:worker_failures) { 0 }

      it 'does not attribute the failure to tests' do
        expect(category).to eq('user:unknown')
      end
    end

    context 'with an invalid worker report' do
      where(:report_case) { %i[malformed missing_summary negative_failure_count oversized] }

      with_them do
        let(:second_report) do
          case report_case
          when :malformed then 'invalid'
          when :missing_summary then '{}'
          when :negative_failure_count
            Gitlab::Json.dump(summary: { failure_count: -1, errors_outside_of_examples_count: 0 })
          when :oversized then 'x' * ((described_class::MAX_REPORT_BYTES / 2) + 1)
          end
        end

        it 'rejects the entire report set' do
          expect(category).to eq('user:unknown')
        end
      end
    end

    context 'with missing workers or invalid counts' do
      where(:report_count) { ['3', '0', '-1', '65', 'invalid'] }

      with_them do
        it 'falls back to exit-code evidence' do
          expect(category).to eq('user:unknown')
        end
      end
    end

    context 'with a stale worker report' do
      before do
        File.utime(Time.at(0), Time.at(0), File.join(tmp_dir, 'rspec-1.json'))
      end

      it 'rejects the entire report set' do
        expect(category).to eq('user:unknown')
      end
    end

    context 'with no worker placeholder' do
      before do
        span.rspec_report = File.join(tmp_dir, 'rspec-2.json')
      end

      it 'does not count one report multiple times' do
        expect(category).to eq('user:unknown')
      end
    end

    context 'with one parallel worker' do
      let(:report_count) { '1' }

      before do
        File.write(File.join(tmp_dir, 'rspec-1.json'), second_report)
      end

      it 'expands the worker placeholder' do
        expect(category).to eq('user:test:failure')
      end
    end
  end
end
