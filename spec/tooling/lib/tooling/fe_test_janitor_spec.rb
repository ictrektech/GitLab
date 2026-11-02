# frozen_string_literal: true

require 'tmpdir'
require 'stringio'
require_relative '../../../../tooling/lib/tooling/fe_test_janitor'

RSpec.describe Tooling::FeTestJanitor, feature_category: :tooling do
  describe '.run' do
    let(:output) { StringIO.new }

    context 'when the directory has no spec files' do
      it 'says that no spec files were found' do
        Dir.mktmpdir do |dir|
          described_class.run(dir, output: output)

          expect(output.string).to eq("No *_spec.rb files found under: #{dir}\n")
        end
      end
    end

    context 'when the directory has spec files' do
      it 'prints a report for them' do
        Dir.mktmpdir do |dir|
          File.write(File.join(dir, 'foo_spec.rb'), <<~RUBY)
            RSpec.describe 'Foo' do
              it 'shows the widget' do
                expect(page).to have_css('[data-testid="widget"]')
              end
            end
          RUBY

          described_class.run(dir, output: output)

          expect(output.string).to include('[migrate] shows the widget (line 2)', 'Examples found: 1')
        end
      end
    end

    context 'when the path is a file that is not a spec file' do
      it 'raises an ArgumentError' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'helper.rb')
          File.write(path, '')

          expect { described_class.run(path, output: output) }.to raise_error(ArgumentError, /Not a spec file/)
        end
      end
    end
  end
end
