# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'projects/commits/show.html.haml', feature_category: :source_code_management do
  let_it_be(:project) { create(:project, :small_repo) }

  let(:commits) { [commit] }
  let(:commit) { project.commit }
  let(:path) { 'path/to/doc.md' }
  let(:ref) { "master" }

  before do
    assign(:project, project)
    assign(:path, path)
    assign(:id, path)
    assign(:ref, ref)
    assign(:repository, project.repository)
    assign(:repo, project.repository)
    assign(:commits, commits)
    assign(:hidden_commit_count, 0)

    controller.params[:controller] = 'projects/commits'
    controller.params[:action] = 'show'
    controller.params[:namespace_id] = project.namespace.to_param
    controller.params[:project_id] = project.to_param

    allow(view).to receive_messages(current_user: nil, commit_blob: true)

    render
  end

  it 'renders the Vue commit list mount element' do
    expect(rendered).to have_selector('#js-commit-list')
  end

  it 'passes browse files path as data attribute' do
    expect(rendered).to have_selector("#js-commit-list[data-browse-files-path]")
  end

  it 'passes commits feed path as data attribute' do
    expect(rendered).to have_selector("#js-commit-list[data-commits-feed-path]")
  end

  it 'passes project full path as data attribute' do
    expect(rendered).to have_selector("#js-commit-list[data-project-full-path='#{project.full_path}']")
  end
end
