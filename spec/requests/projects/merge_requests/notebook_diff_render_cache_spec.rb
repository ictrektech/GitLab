# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Notebook diff render cache on diff endpoints', :use_clean_rails_redis_caching,
  feature_category: :code_review_workflow do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public, :repository, maintainers: user) }
  let_it_be(:notebook_paths) { %w[notebooks/first.ipynb notebooks/second.ipynb] }

  let_it_be(:merge_request) do
    project.repository.commit_files(
      user, branch_name: 'notebooks-base', start_branch_name: 'master', message: 'Add notebooks',
      actions: notebook_paths.map { |path| { action: :create, file_path: path, content: notebook("# #{path}") } }
    )
    project.repository.commit_files(
      user, branch_name: 'notebooks-change', start_branch_name: 'notebooks-base', message: 'Change notebooks',
      actions: notebook_paths.map { |path| { action: :update, file_path: path, content: notebook("#{path} = 2") } }
    )

    create(:merge_request, source_project: project, target_project: project,
      source_branch: 'notebooks-change', target_branch: 'notebooks-base')
  end

  let(:renders) { [] }

  def notebook(source)
    Gitlab::Json.pretty_generate(
      cells: [{ cell_type: 'code', execution_count: 1, metadata: {}, outputs: [], source: [source] }],
      metadata: {}, nbformat: 4, nbformat_minor: 5
    )
  end

  # Each render runs the notebook transform and one `diff` process.
  def renders_per_request
    Array.new(2) do
      renders.clear

      get path

      expect(response).to have_gitlab_http_status(:ok)
      renders.size
    end
  end

  before do
    allow(IpynbDiff).to receive(:diff).and_wrap_original do |method, *args, **kwargs|
      renders << args
      method.call(*args, **kwargs)
    end
  end

  shared_examples 'renders each notebook once' do
    it 'renders each notebook on the first request only' do
      expect(renders_per_request).to eq([notebook_paths.size, 0])
    end
  end

  shared_examples 'renders the notebooks on every request' do
    it 'renders the same notebooks on the second request' do
      first, second = renders_per_request

      expect(first).to be >= notebook_paths.size
      expect(second).to eq(first)
    end
  end

  describe 'GET diffs_batch' do
    let(:path) do
      diffs_batch_namespace_project_json_merge_request_path(
        namespace_id: project.namespace, project_id: project, id: merge_request.iid, page: 0, per_page: 30,
        format: :json
      )
    end

    context 'when anonymous' do
      it_behaves_like 'renders each notebook once'

      context 'when cache_notebook_diffs is disabled' do
        before do
          stub_feature_flags(cache_notebook_diffs: false)
        end

        it_behaves_like 'renders the notebooks on every request'
      end
    end

    context 'when signed in' do
      before do
        sign_in(user)
      end

      it_behaves_like 'renders each notebook once'

      context 'when cache_notebook_diffs is disabled' do
        before do
          stub_feature_flags(cache_notebook_diffs: false)
        end

        it_behaves_like 'renders the notebooks on every request'
      end
    end
  end

  describe 'GET diffs_stream' do
    let(:path) { diffs_stream_project_merge_request_path(project, merge_request) }

    it_behaves_like 'renders each notebook once'

    context 'when cache_notebook_diffs is disabled' do
      before do
        stub_feature_flags(cache_notebook_diffs: false)
      end

      it_behaves_like 'renders the notebooks on every request'
    end
  end
end
