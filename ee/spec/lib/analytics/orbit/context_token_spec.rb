# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Analytics::Orbit::ContextToken, feature_category: :knowledge_graph do
  before do
    stub_config_setting(url: 'https://gitlab.example.com', relative_url_root: '')
  end

  def parse(token)
    described_class.parse(token)
  end

  describe '.parse' do
    it 'parses Type[id] case-insensitively and maps the Issue alias' do
      expect(parse('issue[12]')).to have_attributes(type: 'WorkItem', id: 12, iid: nil, error: nil)
      expect(parse('MergeRequest[3]')).to have_attributes(type: 'MergeRequest', id: 3)
    end

    it 'parses GIDs' do
      expect(parse('gid://gitlab/WorkItem/9')).to have_attributes(type: 'WorkItem', id: 9)
    end

    it 'parses path!iid as a project merge request and path#iid as any work item container' do
      expect(parse('a/b!4')).to have_attributes(type: 'MergeRequest', iid: 4, path: 'a/b', container: :project)
      expect(parse('a/b#5')).to have_attributes(type: 'WorkItem', iid: 5, path: 'a/b', container: :any)
    end

    it 'parses instance URLs and ignores trailing path segments' do
      expect(parse('https://gitlab.example.com/a/b/-/merge_requests/4/diffs'))
        .to have_attributes(type: 'MergeRequest', iid: 4, path: 'a/b', container: :project)
      expect(parse('https://gitlab.example.com/groups/a/-/work_items/6'))
        .to have_attributes(type: 'WorkItem', iid: 6, path: 'a', container: :group)
    end

    it 'parses epic tokens as work items flagged as epics', :aggregate_failures do
      expect(parse('Epic[12]')).to have_attributes(type: 'WorkItem', id: 12, epic: true, error: nil)
      expect(parse('gid://gitlab/Epic/9')).to have_attributes(type: 'WorkItem', id: 9, epic: true)
      expect(parse('a/b&5')).to have_attributes(type: 'WorkItem', iid: 5, path: 'a/b', container: :group, epic: true)
      expect(parse('https://gitlab.example.com/groups/a/b/-/epics/6/designs'))
        .to have_attributes(type: 'WorkItem', iid: 6, path: 'a/b', container: :group, epic: true)
      expect(parse('Issue[1]')).to have_attributes(epic: false)
    end

    it 'honours a relative URL root for epic URLs' do
      stub_config_setting(url: 'https://gitlab.example.com/gl', relative_url_root: '/gl')

      expect(parse('https://gitlab.example.com/gl/groups/a/-/epics/2')).to have_attributes(path: 'a', iid: 2,
        epic: true)
    end

    it 'honours a relative URL root' do
      stub_config_setting(url: 'https://gitlab.example.com/gl', relative_url_root: '/gl')

      expect(parse('https://gitlab.example.com/gl/a/b/-/issues/2')).to have_attributes(path: 'a/b', iid: 2)
    end

    it 'rejects unparseable and foreign tokens before any lookup' do
      [
        '', 'nope', 'Type[0]', 'Issue[01]', 'a/b#0', 'https://other.example.com/a/b/-/issues/1', 'http://gitlab.example.com/a/b/-/issues/1',
        'http://gitlab.example.com:443/a/b/-/issues/1',
        'https://gitlab.example.com/a/b', 'https://gitlab.example.com/a b/-/issues/1', 'Issue[9223372036854775808]',
        'a/b#2147483648',
        'Epic[0]', 'Epic[9223372036854775808]', 'a/b&0', 'a/b&2147483648', '&5', 'https://gitlab.example.com/a/b/-/epics/1',
        'https://gitlab.example.com/groups/a/-/epics/0', 'https://other.example.com/groups/a/-/epics/1'
      ].each do |token|
        expect(parse(token)).to have_attributes(error: 'invalid_token'), "expected #{token.inspect} to be invalid"
      end
    end

    it 'rejects numbers beyond the id range in every token form', :aggregate_failures do
      ['9223372036854775808', '1' * 20, '1' * 5000].each do |number|
        [
          "MergeRequest[#{number}]", "gid://gitlab/Issue/#{number}", "group/project!#{number}",
          "https://gitlab.example.com/a/b/-/issues/#{number}"
        ].each do |token|
          expect(parse(token)).to have_attributes(error: 'invalid_token'),
            "expected #{token[0, 60].inspect} to be invalid"
        end
      end
    end

    it 'rejects a URL whose iid is out of range' do
      expect(parse('https://gitlab.example.com/a/b/-/issues/2147483648')).to have_attributes(error: 'invalid_token')
    end

    it 'rejects a URL that cannot be parsed' do
      expect(parse('http://gitlab.example.com:bad/a/b/-/issues/1')).to have_attributes(error: 'invalid_token')
    end

    it 'parses job tokens by id' do
      ['Job[5]', 'gid://gitlab/Ci::Build/5', 'https://gitlab.example.com/a/b/-/jobs/5'].each do |token|
        expect(parse(token)).to have_attributes(type: 'Job', id: 5, error: nil), "expected #{token.inspect} to parse"
      end
      expect(parse('https://gitlab.example.com/a/b/-/jobs/5')).to have_attributes(path: 'a/b', container: :project)
    end

    it 'rejects a job URL whose id is out of range' do
      expect(parse('https://gitlab.example.com/a/b/-/jobs/9223372036854775808'))
        .to have_attributes(error: 'invalid_token')
    end

    it 'reports unsupported types' do
      ['Project[1]', 'gid://gitlab/Project/1', 'https://gitlab.example.com/a/b/-/milestones/1'].each do |token|
        expect(parse(token)).to have_attributes(error: 'unsupported_type'), "expected #{token.inspect} unsupported"
      end
    end

    it 'parses pipeline tokens by id', :aggregate_failures do
      ['Pipeline[5]', 'gid://gitlab/Ci::Pipeline/5', 'https://gitlab.example.com/a/b/-/pipelines/5'].each do |token|
        expect(parse(token)).to have_attributes(type: 'Pipeline', id: 5, error: nil),
          "expected #{token.inspect} to parse"
      end
      expect(parse('https://gitlab.example.com/a/b/-/pipelines/5')).to have_attributes(path: 'a/b', container: :project)
    end

    it 'parses path@ref as a branch lookup with the ref kept for the service', :aggregate_failures do
      expect(parse('a/b@main')).to have_attributes(type: 'Branch', ref: 'main', path: 'a/b', container: :project)
      expect(parse('a/b@feature/x-1')).to have_attributes(type: 'Branch', ref: 'feature/x-1', path: 'a/b')
      expect(parse('a/b@1a2b3c4')).to have_attributes(type: 'Branch', ref: '1a2b3c4')
      expect(parse('a/b@main')).to be_ref_lookup
      expect(parse('Job[5]')).not_to be_ref_lookup
    end

    it 'parses commit URLs by SHA' do
      expect(parse('https://gitlab.example.com/a/b/-/commit/1a2b3c4d5e'))
        .to have_attributes(type: 'Commit', ref: '1a2b3c4d5e', path: 'a/b', error: nil)
    end

    it 'rejects refs that git does not allow, before any lookup' do
      [
        'a/b@', 'a/b@a..b', 'a/b@x y', 'a/b@x~1', 'a/b@HEAD', 'a/b@refs/heads/main', 'a/b@x@{1}', "a/b@#{'x' * 256}",
        '@main', 'https://gitlab.example.com/a/b/-/commit/main', 'https://gitlab.example.com/a/b/-/commit/1a2b3c'
      ].each do |token|
        expect(parse(token)).to have_attributes(error: 'invalid_token'),
          "expected #{token[0, 60].inspect} to be invalid"
      end
    end
  end

  describe '.commit_sha?' do
    it 'accepts 7 to 64 hexadecimal characters only', :aggregate_failures do
      expect(described_class.commit_sha?('1a2b3c4')).to be(true)
      expect(described_class.commit_sha?('a' * 64)).to be(true)
      expect(described_class.commit_sha?('1a2b3c')).to be(false)
      expect(described_class.commit_sha?('a' * 65)).to be(false)
      expect(described_class.commit_sha?('main')).to be(false)
    end
  end
end
