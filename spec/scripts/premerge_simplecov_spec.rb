# frozen_string_literal: true

require 'fast_spec_helper'
require 'simplecov'
require 'tmpdir'

load File.expand_path('../../scripts/premerge-simplecov', __dir__)

RSpec.describe PremergeSimplecov, feature_category: :tooling do
  # rubocop:disable Gitlab/Json -- The script runs without the bundle, so it uses JSON
  let(:root) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(root)
  end

  def write_resultset(job, entry)
    dir = File.join(root, 'coverage', job)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, '.resultset.json'), JSON.dump(job => entry))
  end

  def coverage(lines, branches = {})
    { 'coverage' => { '/builds/gitlab-org/gitlab/app/a.rb' => { 'lines' => lines, 'branches' => branches } },
      'timestamp' => 1_700_000_000 }
  end

  def resultset_dirs
    Dir.glob(File.join(root, 'coverage', '*')).map { |dir| File.basename(dir) }
  end

  subject(:run) { described_class.run('premerged-collector', root: root) }

  before do
    allow(described_class).to receive(:puts)
  end

  context 'with several resultsets' do
    before do
      write_resultset('rspec-unit-1', coverage([2, 1, nil]))
      write_resultset('rspec-unit-2', coverage([3, 4, nil]))
    end

    it 'replaces them with one resultset that adds up their coverage' do
      run

      expect(resultset_dirs).to eq(['premerged-collector'])

      merged = JSON.parse(File.read(File.join(root, 'coverage', 'premerged-collector', '.resultset.json')))
      command_name, entry = merged.first

      expect(command_name).to eq('rspec-unit-1, rspec-unit-2')
      expect(entry['coverage']['/builds/gitlab-org/gitlab/app/a.rb']['lines']).to eq([5, 5, nil])
    end

    it 'keeps files that are not on this filesystem' do
      run

      merged = JSON.parse(File.read(File.join(root, 'coverage', 'premerged-collector', '.resultset.json')))

      expect(merged.first.last['coverage'].keys).to eq(['/builds/gitlab-org/gitlab/app/a.rb'])
    end
  end

  context 'with branch coverage' do
    def branches(then_hits, else_hits)
      {
        '[:if, 0, 2, 4, 2, 30]' => {
          '[:then, 1, 2, 4, 2, 20]' => then_hits,
          '[:else, 2, 2, 4, 2, 30]' => else_hits
        }
      }
    end

    before do
      write_resultset('rspec-unit-1', coverage([1, 1, nil], branches(2, 1)))
      write_resultset('rspec-unit-2', coverage([1, 1, nil], branches(3, 4)))
    end

    it 'adds up the hits of each branch' do
      run

      merged = JSON.parse(File.read(File.join(root, 'coverage', 'premerged-collector', '.resultset.json')))

      expect(merged.first.last['coverage']['/builds/gitlab-org/gitlab/app/a.rb']['branches']).to eq(branches(5, 5))
    end
  end

  context 'with a single resultset' do
    before do
      write_resultset('rspec-unit-1', coverage([1, 0, nil]))
    end

    it 'leaves it as it is' do
      run

      expect(resultset_dirs).to eq(['rspec-unit-1'])
    end
  end

  # rubocop:enable Gitlab/Json
end
