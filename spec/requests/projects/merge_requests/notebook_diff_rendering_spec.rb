# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Notebook diff rendering on diff endpoints', feature_category: :code_review_workflow do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project, :public, :repository, maintainers: user) }
  let_it_be(:notebook_paths) { %w[notebooks/first.ipynb notebooks/second.ipynb] }

  let_it_be(:merge_request) do
    project.repository.commit_files(
      user, branch_name: 'notebooks-base', start_branch_name: 'master', message: 'Add notebooks',
      actions: notebook_paths.map { |path| { action: :create, file_path: path, content: notebook(1) } }
    )
    project.repository.commit_files(
      user, branch_name: 'notebooks-change', start_branch_name: 'notebooks-base', message: 'Change notebooks',
      actions: notebook_paths.map { |path| { action: :update, file_path: path, content: notebook(2) } }
    )

    create(:merge_request, source_project: project, target_project: project,
      source_branch: 'notebooks-change', target_branch: 'notebooks-base')
  end

  # Each run changes three lines of the .ipynb JSON, but one line of the rendered notebook: the output.
  def notebook(run)
    output = { output_type: 'execute_result', execution_count: run, metadata: {}, data: { 'text/plain': [run.to_s] } }

    Gitlab::Json.pretty_generate(
      cells: [{ cell_type: 'code', execution_count: run, metadata: {}, outputs: [output], source: ['1 + 1'] }],
      metadata: {}, nbformat: 4, nbformat_minor: 5
    )
  end

  before do
    # The render cache serves repeated renders of the same blobs, and this spec counts renders.
    stub_feature_flags(cache_notebook_diffs: false)
    allow(IpynbDiff).to receive(:diff).and_call_original
  end

  shared_examples 'renders notebooks' do |expected_renders|
    it "renders #{expected_renders} notebook diffs" do
      send_request

      expect(response).to have_gitlab_http_status(:ok)
      expect(IpynbDiff).to have_received(:diff).exactly(expected_renders).times
    end
  end

  describe 'GET diffs_metadata' do
    let(:send_request) do
      get diffs_metadata_namespace_project_json_merge_request_path(
        namespace_id: project.namespace, project_id: project, id: merge_request.iid, format: :json
      )
    end

    it_behaves_like 'renders notebooks', 0

    context 'when signed in' do
      before do
        sign_in(user)
      end

      it_behaves_like 'renders notebooks', 0
    end

    it 'returns the same files as with rendered notebooks' do
      send_request
      files = diff_files_without_line_counts

      stub_feature_flags(reduce_notebook_diff_rendering: false)
      send_request

      expect(files.pluck('new_path')).to match_array(notebook_paths)
      expect(diff_files_without_line_counts).to eq(files)
    end

    it 'returns the line counts of the raw notebook diff' do
      send_request

      expect(line_counts).to eq(added: [3, 3], removed: [3, 3], total: [6, 6])
    end

    def diff_files_without_line_counts
      json_response['diff_files'].map { |file| file.except('added_lines', 'removed_lines') }
    end

    def line_counts
      {
        added: json_response['diff_files'].pluck('added_lines'),
        removed: json_response['diff_files'].pluck('removed_lines'),
        total: json_response.values_at('added_lines', 'removed_lines')
      }
    end

    context 'when reduce_notebook_diff_rendering is disabled' do
      before do
        stub_feature_flags(reduce_notebook_diff_rendering: false)
      end

      it_behaves_like 'renders notebooks', 2

      it 'returns the line counts of the rendered notebook diff' do
        send_request

        expect(line_counts).to eq(added: [1, 1], removed: [1, 1], total: [2, 2])
      end
    end
  end

  describe 'GET diffs_batch' do
    def send_request(headers: {})
      get diffs_batch_namespace_project_json_merge_request_path(
        namespace_id: project.namespace, project_id: project, id: merge_request.iid, page: 0, per_page: 30,
        format: :json
      ), headers: headers
    end

    shared_examples 'renders notebooks for a not modified response' do |expected_renders|
      it "renders #{expected_renders} notebook diffs" do
        send_request
        renders = 0
        allow(IpynbDiff).to receive(:diff).and_wrap_original do |method, *args, **kwargs|
          renders += 1
          method.call(*args, **kwargs)
        end

        send_request(headers: { 'If-None-Match' => response.headers['ETag'] })

        expect(response).to have_gitlab_http_status(:not_modified)
        expect(renders).to eq(expected_renders)
      end
    end

    # Anonymous requests ignore whitespace changes, so they compare the repository instead of the stored diff.
    context 'when anonymous' do
      it_behaves_like 'renders notebooks', 2
      it_behaves_like 'renders notebooks for a not modified response', 0

      context 'when reduce_notebook_diff_rendering is disabled' do
        before do
          stub_feature_flags(reduce_notebook_diff_rendering: false)
        end

        it_behaves_like 'renders notebooks', 4
        it_behaves_like 'renders notebooks for a not modified response', 2
      end
    end

    context 'when signed in' do
      before do
        sign_in(user)
      end

      it_behaves_like 'renders notebooks', 2

      context 'when reduce_notebook_diff_rendering is disabled' do
        before do
          stub_feature_flags(reduce_notebook_diff_rendering: false)
        end

        it_behaves_like 'renders notebooks', 2
      end
    end

    context 'when cache_notebook_diffs is enabled', :use_clean_rails_redis_caching do
      before do
        stub_feature_flags(cache_notebook_diffs: true)
      end

      # Both notebooks change the same blobs, so one render serves both files.
      it_behaves_like 'renders notebooks', 1

      it 'serves a second request from the cache' do
        send_request
        send_request

        expect(response).to have_gitlab_http_status(:ok)
        expect(IpynbDiff).to have_received(:diff).once
      end
    end
  end

  describe 'GET diffs_stream' do
    let(:send_request) { get diffs_stream_project_merge_request_path(project, merge_request) }

    it_behaves_like 'renders notebooks', 2

    context 'when reduce_notebook_diff_rendering is disabled' do
      before do
        stub_feature_flags(reduce_notebook_diff_rendering: false)
      end

      it_behaves_like 'renders notebooks', 4
    end
  end

  # The page renders the first diff files through MergeRequestDiff#paginated_diffs.
  describe 'GET diffs with rapid diffs' do
    let(:send_request) { get diffs_project_merge_request_path(project, merge_request, rapid_diffs: 'true') }

    it_behaves_like 'renders notebooks', 2

    context 'when reduce_notebook_diff_rendering is disabled' do
      before do
        stub_feature_flags(reduce_notebook_diff_rendering: false)
      end

      it_behaves_like 'renders notebooks', 4
    end
  end

  describe 'rapid diffs metadata and stats' do
    where(:endpoint) do
      [
        [:diff_files_metadata_project_merge_request_path],
        [:diffs_stats_project_merge_request_path]
      ]
    end

    with_them do
      let(:send_request) { get public_send(endpoint, project, merge_request) }

      it_behaves_like 'renders notebooks', 0

      context 'when reduce_notebook_diff_rendering is disabled' do
        before do
          stub_feature_flags(reduce_notebook_diff_rendering: false)
        end

        it_behaves_like 'renders notebooks', 2
      end
    end

    context 'on compare' do
      where(:endpoint) do
        [
          [:diff_files_metadata_project_compare_index_path],
          [:diffs_stats_project_compare_index_path]
        ]
      end

      with_them do
        let(:send_request) { get public_send(endpoint, project, from: 'notebooks-base', to: 'notebooks-change') }

        it_behaves_like 'renders notebooks', 0

        context 'when reduce_notebook_diff_rendering is disabled' do
          before do
            stub_feature_flags(reduce_notebook_diff_rendering: false)
          end

          it_behaves_like 'renders notebooks', 2
        end
      end
    end
  end
end
