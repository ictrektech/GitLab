# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DependencyManagement::SecurityUpdate::CommitConvention, feature_category: :dependency_management do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:project) { create(:project, :repository) }

  let(:bot_email) { 'bot@example.com' }

  subject(:style) { described_class.detect(project, exclude_email: bot_email) }

  def commits_with(*titles, author_email: 'dev@example.com')
    titles.map do |title|
      git_commit = RepoHelpers.sample_commit.tap do |commit|
        commit.message = title
        commit.safe_message = title
        commit.author_email = author_email
      end

      build(:commit, project: project, git_commit: git_commit)
    end
  end

  def stub_commits(commits)
    allow(project.repository).to receive(:commits)
      .with(project.default_branch, limit: 50, skip_merges: true)
      .and_return(commits)
  end

  def stub_history(*titles, author_email: 'dev@example.com')
    stub_commits(commits_with(*titles, author_email: author_email))
  end

  context 'when the history uses Conventional Commits' do
    before do
      stub_history('feat(api): add endpoint', 'fix: handle nil', 'build(deps): update rack', 'docs: typo')
    end

    it { is_expected.to have_attributes(type: 'build', capitalize: false) }
  end

  context 'when the history uses chore and never build' do
    before do
      stub_history('chore(deps): update rack', 'feat: add endpoint')
    end

    it { is_expected.to have_attributes(type: 'chore') }
  end

  context 'when the history uses both chore and build' do
    before do
      stub_history('chore(release): 4.42.0', 'build(deps): update rack')
    end

    it { is_expected.to have_attributes(type: 'build') }
  end

  context 'when most conventional subjects are capitalised' do
    before do
      stub_history('feat: Add endpoint', 'fix(api)!: Handle nil', 'docs: typo')
    end

    it { is_expected.to have_attributes(capitalize: true) }
  end

  context 'when most conventional types are capitalised' do
    before do
      stub_history('Fix: handle nil', 'Docs: Update README', 'feat: add endpoint')
    end

    it 'capitalises the type' do
      expect(style).to have_attributes(type: 'Build')
    end
  end

  context 'when the history uses a custom prefix' do
    before do
      stub_history('deps: bump rack', 'security: patch xss', 'api: handle nil')
    end

    it { is_expected.to be_nil }
  end

  context 'when reading the history fails' do
    before do
      allow(project.repository).to receive(:commits).and_raise(Gitlab::Git::CommandError, 'boom')
    end

    it 'reports the error and falls back to the plain format' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(instance_of(Gitlab::Git::CommandError), project_id: project.id)

      expect(style).to be_nil
    end
  end

  context 'when at least 30% of the history is conventional' do
    before do
      stub_history('feat: add endpoint', 'fix: handle nil', 'docs: typo', *Array.new(7) { 'Plain commit' })
    end

    it { is_expected.to be_present }
  end

  context 'when less than 30% of the history is conventional' do
    before do
      stub_history('feat: add endpoint', 'fix: handle nil', *Array.new(8) { 'Plain commit' })
    end

    it { is_expected.to be_nil }
  end

  context 'when the history does not use Conventional Commits' do
    before do
      stub_history('Add endpoint', 'Handle nil in feature: x', 'Update rack')
    end

    it { is_expected.to be_nil }
  end

  context 'when every recent commit is by the service account' do
    before do
      stub_history('feat: add endpoint', author_email: bot_email)
    end

    it { is_expected.to be_nil }
  end

  context 'when the service account made the latest 20 commits' do
    before do
      stub_commits(
        commits_with(*Array.new(20) { 'Update rack' }, author_email: bot_email) +
        commits_with('feat: add endpoint', 'fix: handle nil')
      )
    end

    it 'decides from the older human commits' do
      expect(style).to have_attributes(type: 'build')
    end
  end

  context 'when more than 20 human commits are available' do
    before do
      stub_history(*Array.new(20) { 'Plain commit' }, *Array.new(10) { 'feat: add endpoint' })
    end

    it 'only samples the latest 20' do
      expect(style).to be_nil
    end
  end

  context 'with a real repository' do
    let_it_be(:project) { create(:project, :repository) }

    before_all do
      7.times do |i|
        project.repository.create_file(
          project.creator, "conventional-#{i}.txt", 'content',
          message: "feat: add file #{i}", branch_name: project.default_branch
        )
      end
    end

    it 'reads the default branch history' do
      expect(style).to have_attributes(type: 'build')
    end
  end

  describe '.from_title' do
    where(:title, :type, :capitalize) do
      'build(deps): [security] update rack from 2.0.9 to 2.2.0' | 'build' | false
      'Chore(deps): [Security] Update rack to 2.2.0'            | 'Chore' | true
    end

    with_them do
      it 'reads the style back from our own title' do
        expect(described_class.from_title(title)).to have_attributes(type: type, capitalize: capitalize)
      end
    end

    it 'ignores a plain title' do
      expect(described_class.from_title('Security: Update rack from 2.0.9 to 2.2.0')).to be_nil
    end

    it 'ignores a missing title' do
      expect(described_class.from_title(nil)).to be_nil
    end
  end

  context 'when the repository is empty' do
    let_it_be(:project) { create(:project, :empty_repo) }

    it { is_expected.to be_nil }
  end
end
