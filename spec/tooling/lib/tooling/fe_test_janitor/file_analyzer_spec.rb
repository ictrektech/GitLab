# frozen_string_literal: true

require 'tmpdir'
require_relative '../../../../../tooling/lib/tooling/fe_test_janitor/file_analyzer'

RSpec.describe Tooling::FeTestJanitor::FileAnalyzer, feature_category: :tooling do
  describe '#analyze' do
    it 'parses the file and classifies each example' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'foo_spec.rb')
        File.write(path, <<~RUBY)
          RSpec.describe 'Foo' do
            it 'reorders items' do
              find('.item').drag_to(find('.target'))
            end

            it_behaves_like 'work items title'
          end
        RUBY

        result = described_class.new(path).analyze

        expect(result.path).to eq(path)
        expect(result.example_results.map { |er| [er.example.description, er.classification.verdict] })
          .to contain_exactly(['reorders items', :keep], ['work items title', :shared])
      end
    end

    it 'names the file when it cannot parse it' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'broken_spec.rb')
        File.write(path, "RSpec.describe 'Foo' do\n")

        expect { described_class.new(path).analyze }.to raise_error(
          Tooling::FeTestJanitor::ExampleParser::ParseError, /could not parse #{Regexp.escape(path)}: line/
        )
      end
    end
  end
end
