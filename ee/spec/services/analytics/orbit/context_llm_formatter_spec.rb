# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::ContextLlmFormatter, feature_category: :knowledge_graph do
  let(:link) { { type: 'MergeRequest', token: 'MergeRequest[2]', project_path: 'g/p', iid: 7, title: 'Linked' } }
  let(:user) { { id: 1, username: 'alex', name: 'Alex & Co' } }
  let(:expansion) { nil }
  let(:entity) do
    {
      token: 'g/p#3', resolved_token: 'WorkItem[9]', type: 'WorkItem', id: 9, found: true, expansion: expansion,
      summary: {
        title: 'A & <b>', state: 'opened', iid: 3, namespace_path: 'g', project_path: 'g/p', labels: %w[a b],
        assignees: [user], milestone: { id: 4, title: 'M1' }, linked_merge_requests: [link], reviewers: nil,
        description: "First\nSecond", discussions: [{ author: 'alex', created_at: '2026-10-01', body: 'Looks good' }]
      }
    }
  end

  subject(:text) { described_class.new({ version: '1.2.0', entities: [entity] }).execute }

  it 'renders the summary lines without HTML escaping', :aggregate_failures do
    expect(text).to start_with("orbit_context version=1.2.0 entities=1\n- g/p#3 id=9 found=true\n")
    expect(text).to include(
      '  title="A & <b>"', '  labels="a, b"', '  assignees="alex (Alex & Co, id=1)"',
      '  milestone="M1 (id=4)"', '  linked_merge_requests="g/p!7 Linked"',
      "  description:\n    First\n    Second\n", "  discussions[1]:\n    @alex 2026-10-01:\n      Looks good\n"
    )
  end

  it 'emits references that the context endpoint accepts as tokens' do
    references = [text[/^- (\S+)/, 1], text[/linked_merge_requests="(\S+)/, 1]]

    expect(references).to eq(%w[g/p#3 g/p!7])
    expect(references.map { |ref| Analytics::Orbit::ContextToken.parse(ref).error }).to all(be_nil)
  end

  context 'with a job' do
    let(:entity) do
      {
        token: 'Job[5]', resolved_token: 'Job[5]', type: 'Job', id: 5, found: true, expansion: nil,
        summary: {
          id: 5, name: 'rspec', status: 'failed', failure_reason: 'script_failure', namespace_path: 'g',
          project_path: 'g/p', merge_request: link, log: "boom\nexit 1",
          failed_tests: [
            { classname: 'PopenSpec', name: 'runs', file: 'spec/popen_spec.rb', output: 'expected 1' }
          ]
        }
      }
    end

    it 'renders the job reference, its merge request, failed tests, and the log', :aggregate_failures do
      expect(text).to include("- Job[5] id=5 found=true\n", '  name="rspec"', '  failure_reason="script_failure"')
      expect(text).to include('  merge_request="g/p!7 Linked"', "  log:\n    boom\n    exit 1\n")
      expect(text).to include("  failed_tests[1]:\n    PopenSpec runs spec/popen_spec.rb\n      expected 1\n")
    end
  end

  context 'with pipelines, branches, and commits' do
    let(:sha) { '1a2b3c4d5e6f' }
    let(:entities) do
      [
        { token: 'Pipeline[8]', resolved_token: 'Pipeline[8]', type: 'Pipeline', id: '8', found: true,
          expansion: nil,
          summary: { id: 8, status: 'failed', source: 'push', project_path: 'g/p', merge_request: link,
                     jobs: [{ name: 'rspec', stage: 'test', status: 'failed', allow_failure: true }] } },
        { token: 'g/p@main', resolved_token: 'g/p@main', type: 'Branch', id: 'main', found: true, expansion: nil,
          summary: { name: 'main', sha: sha, default_branch: true, project_path: 'g/p', pipeline_status: 'success' } },
        { token: "g/p@#{sha}", resolved_token: "g/p@#{sha}", type: 'Commit', id: sha, found: true, expansion: nil,
          summary: { sha: sha, title: 'Fix', author_name: 'Alex', project_path: 'g/p', merge_requests: [link] } }
      ]
    end

    subject(:text) { described_class.new({ version: '1.3.0', entities: entities }).execute }

    it 'renders references that the context endpoint accepts as tokens', :aggregate_failures do
      references = text.scan(/^- (\S+)/).flatten

      expect(references).to match_array(['Pipeline[8]', 'g/p@main', "g/p@#{sha}"])
      expect(references.map { |ref| Analytics::Orbit::ContextToken.parse(ref).error }).to all(be_nil)
      expect(text).to include('  source="push"', '  default_branch="true"', '  author_name="Alex"')
      expect(text).to include('  merge_request="g/p!7 Linked"', '  merge_requests="g/p!7 Linked"')
      expect(text).to include("  jobs[1]:\n    rspec (test, failed, allowed to fail)\n")
    end
  end

  context 'with a job that has no stage or failure flags' do
    let(:entity) do
      { token: 'Pipeline[9]', resolved_token: 'Pipeline[9]', type: 'Pipeline', id: '9', found: true, expansion: nil,
        summary: { id: 9, project_path: 'g/p',
                   jobs: [{ name: 'build', status: 'success', allow_failure: false }] } }
    end

    it 'lists the job with only the flags it has' do
      text = described_class.new({ version: '1.3.0', entities: [entity] }).execute

      expect(text).to include("  jobs[1]:\n    build (success)\n")
    end
  end

  context 'with changed files, failed jobs, and unlinkable references' do
    let(:link) { { type: 'MergeRequest', token: 'MergeRequest[2]', title: 'No path' } }
    let(:entity) do
      {
        token: 'MergeRequest[2]', resolved_token: 'MergeRequest[2]', type: 'MergeRequest', id: 2, found: true,
        expansion: nil,
        summary: {
          title: 'MR', linked_issues: [link],
          changed_files: [
            { path: 'a.rb', status: 'M', lines: %w[1-2 7] },
            { path: 'b.rb', old_path: 'old.rb', status: 'R' }
          ],
          failed_jobs: [
            {
              name: 'rspec', stage: 'test', failure_reason: 'script_failure', allow_failure: true,
              web_url: 'http://x/jobs/1', log: 'boom', truncated: [:failed_tests],
              failed_tests: [{ classname: 'ASpec', name: 'runs', output: 'expected 1' }]
            },
            { name: 'lint', web_url: 'http://x/jobs/2' }
          ],
          discussions: [{ author: 'alex', created_at: '2026-10-01', resolved: true, path: 'a.rb', line: 3, body: 'x' }]
        }
      }
    end

    it 'renders each section', :aggregate_failures do
      expect(text).to include('  linked_issues="MergeRequest[2] No path"')
      expect(text).to include("  changed_files[2]:\n    M a.rb @ 1-2, 7\n    R b.rb (from old.rb)\n")
      expect(text).to include("  failed_jobs[2]:\n    rspec (test, script_failure, allowed to fail) http://x/jobs/1\n")
      expect(text).to include("jobs/1\n      truncated=failed_tests\n      failed_tests[1]:\n")
      expect(text).to include("      failed_tests[1]:\n        ASpec runs\n          expected 1\n      | boom\n")
      expect(text).to include("    lint () http://x/jobs/2\n")
      expect(text).to include('    @alex 2026-10-01', ' a.rb:3:')
    end
  end

  context 'with a graph result' do
    let(:expansion) { { result: "nodes[1]:\n  a\n" } }

    it 'appends the graph section' do
      expect(text).to end_with("graph:\nnodes[1]:\n  a\n")
    end
  end

  context 'with truncated lists' do
    before do
      entity[:summary][:truncated] = %i[reviewers labels changed_files failed_jobs discussions]
    end

    it 'names the incomplete lists on one line right after the scalar fields' do
      expect(text).to include(
        "  project_path=\"g/p\"\n  truncated=reviewers,labels,changed_files,failed_jobs,discussions\n"
      )
    end
  end

  context 'without truncated lists' do
    before do
      entity[:summary][:truncated] = []
    end

    it 'omits the truncated line' do
      expect(text).not_to include('truncated=')
    end
  end

  context 'with an expansion error' do
    let(:expansion) { { error: { code: 'timeout' } } }

    it 'appends a one-line error' do
      expect(text).to end_with("error timeout\n")
    end
  end

  context 'with an unfound token' do
    let(:entity) { { token: 'x/y#1', found: false, error: { code: 'not_found' }, expansion: nil } }

    it 'renders the error code only' do
      expect(text).to end_with("- \"x/y#1\" found=false error=not_found\n")
    end
  end
end
