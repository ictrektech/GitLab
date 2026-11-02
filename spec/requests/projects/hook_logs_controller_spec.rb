# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::HookLogsController, feature_category: :webhooks do
  let_it_be(:user) { create(:user) }
  let_it_be_with_refind(:web_hook) { create(:project_hook) }
  let_it_be_with_refind(:web_hook_log) { create(:web_hook_log, web_hook: web_hook) }

  let(:project) { web_hook.project }

  it_behaves_like 'web hook log actions' do
    let(:edit_hook_path) { edit_project_hook_url(project, web_hook) }

    before do
      project.add_owner(user)
    end
  end

  context 'when the user is a developer' do
    before do
      project.add_developer(user)
      sign_in(user)
    end

    it 'returns 404 for show' do
      get web_hook_log.present.details_path

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns 404 for retry and does not execute the hook' do
      expect(WebHooks::Events::ResendService).not_to receive(:new)

      post web_hook_log.present.retry_path

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end
end
