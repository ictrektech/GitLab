# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::MergeRequests::ContentController, feature_category: :code_review_workflow do
  let(:project) { create(:project, :repository) }
  let(:user) { create(:user) }
  let(:merge_request) { create(:merge_request, target_project: project, source_project: project) }

  before do
    sign_in(user)
  end

  context 'when user has access to the project' do
    before do
      project.add_maintainer(user)
    end

    describe 'GET cached_widget' do
      it 'renders widget MR entity as json' do
        expect(::Gitlab::GitalyClient).to receive(:allow_ref_name_caching).and_call_original

        get cached_widget_project_json_merge_request_path(project, merge_request, format: :json)

        expect(response).to match_response_schema('entities/merge_request_poll_cached_widget')
      end
    end
  end
end
