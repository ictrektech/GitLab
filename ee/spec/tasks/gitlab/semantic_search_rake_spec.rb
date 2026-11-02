# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'gitlab:semantic_search namespace rake tasks', :silence_stdout, feature_category: :global_search do
  before do
    Rake.application.rake_require 'tasks/gitlab/semantic_search'
  end

  describe 'gitlab:semantic_search:code:info' do
    it 'calls Search::RakeTask::SemanticSearch.info with task name and watch_interval' do
      expect(Search::RakeTask::SemanticSearch).to receive(:info).with(
        name: 'gitlab:semantic_search:code:info',
        watch_interval: nil
      )

      run_rake_task('gitlab:semantic_search:code:info')
    end

    it 'passes watch_interval argument when provided' do
      expect(Search::RakeTask::SemanticSearch).to receive(:info).with(
        name: 'gitlab:semantic_search:code:info',
        watch_interval: '10'
      )

      run_rake_task('gitlab:semantic_search:code:info', '10')
    end
  end

  describe 'gitlab:semantic_search:setup' do
    it 'calls Search::RakeTask::SemanticSearchDevSetup.setup' do
      expect(Search::RakeTask::SemanticSearchDevSetup).to receive(:setup)

      run_rake_task('gitlab:semantic_search:setup')
    end
  end

  describe 'gitlab:semantic_search:setup:index_project' do
    it 'calls Search::RakeTask::SemanticSearchDevSetup.index_project without a project path by default' do
      expect(Search::RakeTask::SemanticSearchDevSetup).to receive(:index_project).with(project_path: nil)

      run_rake_task('gitlab:semantic_search:setup:index_project')
    end

    it 'passes the project_path argument when provided' do
      expect(Search::RakeTask::SemanticSearchDevSetup).to receive(:index_project).with(project_path: 'group/project')

      run_rake_task('gitlab:semantic_search:setup:index_project', 'group/project')
    end
  end
end
