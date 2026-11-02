# frozen_string_literal: true

module Analytics
  module Orbit
    class JobFailure
      SCAN_LINES = 2000
      LOG_LINES = 60
      MAX_TESTS = 20
      OUTPUT_LINES = 10
      # Runner sections around the job script. Lines in any other section are script output, and so are
      # lines in none when the scanned window starts mid-log, because their section start was cut off.
      RUNNER_SECTIONS = %w[
        prepare-executor prepare-script resolve-secrets get-sources clear-worktree restore-cache
        download-artifacts archive-cache archive-cache-on-failure upload-artifacts-on-success
        upload-artifacts-on-failure cleanup-file-variables
      ].freeze

      def initialize(job, user, read_log: true, read_tests: true)
        @job = job
        @user = user
        @read_log = read_log
        @read_tests = read_tests
      end

      def execute
        truncated = []
        { failed_tests: failed_tests(truncated), log: log_tail, truncated: truncated.presence }.compact
      end

      private

      attr_reader :job, :user, :read_log, :read_tests

      def failed_tests(truncated)
        return unless read_tests && job.has_test_reports? && job.test_report_readable_by?(user)

        report = job.collect_test_reports!(::Gitlab::Ci::Reports::TestReport.new)
        tests = report.test_suites.values.flat_map { |suite| suite.failed.values + suite.error.values }
        truncated << :failed_tests if tests.size > MAX_TESTS
        tests.first(MAX_TESTS).map { |test| test_summary(test) }.presence
      end

      def test_summary(test)
        {
          name: test.name,
          classname: test.classname,
          file: test.file,
          output: test.system_output.to_s.strip.lines.first(OUTPUT_LINES).join.rstrip.presence
        }.compact
      end

      def log_tail
        return unless read_log && job.has_trace? && Ability.allowed?(user, :read_build_trace, job)

        raw = job.trace.raw(last_lines: SCAN_LINES).to_s
        cut = raw.lines.size >= SCAN_LINES
        lines = ::Gitlab::Ci::Ansi2json.convert(StringIO.new(raw)).lines.reject { |line| line[:section_header] }
        script = lines.select { |line| script_output?(line[:section], cut) }
        script = lines if script.empty?
        text = script.map { |line| line[:content].sum('') { |segment| segment[:text] }.rstrip }.reject(&:blank?)
        text.last(LOG_LINES).join("\n").presence
      end

      def script_output?(section, cut)
        section ? RUNNER_SECTIONS.exclude?(section) : cut
      end
    end
  end
end
