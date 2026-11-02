# frozen_string_literal: true

require 'stringio'
require_relative '../../../../../tooling/lib/tooling/fe_test_janitor/file_analyzer'
require_relative '../../../../../tooling/lib/tooling/fe_test_janitor/reporter'

RSpec.describe Tooling::FeTestJanitor::Reporter, feature_category: :tooling do
  let(:reporter) { described_class.new }
  let(:output) { StringIO.new }
  let(:example_struct) { Tooling::FeTestJanitor::ExampleParser::Example }
  let(:classification_struct) { Tooling::FeTestJanitor::Classifier::Result }
  let(:file_result_struct) { Tooling::FeTestJanitor::FileAnalyzer::FileResult }
  let(:example_result_struct) { Tooling::FeTestJanitor::FileAnalyzer::ExampleResult }

  def example_result(description, line_number, verdict, reasons)
    example_result_struct.new(
      example: example_struct.new(description: description, line_number: line_number, body: ''),
      classification: classification_struct.new(verdict: verdict, reasons: reasons)
    )
  end

  describe '#report' do
    subject(:report) { reporter.report(file_results, output: output) }

    context 'with classified examples' do
      let(:file_results) do
        [
          file_result_struct.new(
            path: 'spec/features/foo_spec.rb',
            example_results: [
              example_result('shows the widget', 3, :migrate, ['quarantine tag detected']),
              example_result('reorders items', 8, :keep, []),
              example_result('work items title', 12, :shared, ['shared example call, not analyzed'])
            ]
          ),
          file_result_struct.new(path: 'spec/features/empty_spec.rb', example_results: [])
        ]
      end

      it 'returns the output stream' do
        expect(report).to be(output)
      end

      it 'prints each example with its padded verdict and reason' do
        expect(report.string).to include(
          "FILE: spec/features/foo_spec.rb\n",
          "  [migrate] shows the widget (line 3)\n    Reason: quarantine tag detected\n",
          "  [keep   ] reorders items (line 8)\n    Reason: no signals detected (defaulting to keep)\n",
          "  [shared ] work items title (line 12)\n"
        )
      end

      it 'says when a file has no examples' do
        expect(report.string).to include("FILE: spec/features/empty_spec.rb\n  (no examples found)\n")
      end

      it 'prints totals that leave shared example calls out of the example count' do
        expect(report.string).to end_with(<<~TEXT)
          === Summary ===
          Files scanned : 2
          Examples found: 2
            migrate     : 1
            reframe     : 0
            partial     : 0
            keep        : 1
          Shared example calls (not analyzed): 1
        TEXT
      end
    end

    context 'with a long description' do
      let(:file_results) do
        [
          file_result_struct.new(
            path: 'spec/features/foo_spec.rb',
            example_results: [example_result('a' * 80, 1, :keep, [])]
          )
        ]
      end

      it 'truncates it to 70 characters' do
        expect(report.string).to include("[keep   ] #{'a' * 67}... (line 1)")
      end
    end
  end
end
