# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require_relative '../../../../../tooling/lib/tooling/fe_test_janitor/directory_walker'

RSpec.describe Tooling::FeTestJanitor::DirectoryWalker, feature_category: :tooling do
  describe '#spec_files' do
    context 'with a directory' do
      it 'returns all *_spec.rb files recursively' do
        Dir.mktmpdir do |dir|
          FileUtils.mkdir_p(File.join(dir, 'sub'))
          File.write(File.join(dir, 'foo_spec.rb'), '')
          File.write(File.join(dir, 'sub', 'bar_spec.rb'), '')
          File.write(File.join(dir, 'support_helper.rb'), '')

          files = described_class.new(dir).spec_files
          expect(files.map { |f| File.basename(f) }).to contain_exactly('foo_spec.rb', 'bar_spec.rb')
        end
      end

      it 'returns an empty array when no spec files exist' do
        Dir.mktmpdir do |dir|
          expect(described_class.new(dir).spec_files).to eq([])
        end
      end
    end

    context 'with a single spec file' do
      it 'returns that file in an array' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'my_spec.rb')
          File.write(path, '')

          expect(described_class.new(path).spec_files).to eq([path])
        end
      end
    end

    context 'with a non-spec file path' do
      it 'raises ArgumentError' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'helper.rb')
          File.write(path, '')

          expect { described_class.new(path).spec_files }.to raise_error(ArgumentError, /Not a spec file/)
        end
      end
    end

    context 'with a non-existent path' do
      it 'raises ArgumentError' do
        expect { described_class.new('/no/such/path').spec_files }.to raise_error(ArgumentError, /does not exist/)
      end
    end
  end
end
