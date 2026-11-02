# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Admin::HookLogsController, :enable_admin_mode, :with_current_organization, feature_category: :webhooks do
  let_it_be(:user) { create(:admin) }
  let_it_be_with_refind(:web_hook) { create(:system_hook, organization: current_organization) }
  let_it_be_with_refind(:web_hook_log) { create(:web_hook_log, web_hook: web_hook) }

  it_behaves_like 'web hook log actions' do
    let!(:show_path) { admin_hook_hook_log_path(web_hook, web_hook_log) }
    let!(:retry_path) { retry_admin_hook_hook_log_path(web_hook, web_hook_log) }
    let(:edit_hook_path) { edit_admin_hook_path(web_hook) }
  end

  context 'when the user is not an admin' do
    let_it_be(:non_admin) { create(:user) }

    before do
      sign_in(non_admin)
    end

    it 'returns 404 for show and retry' do
      get admin_hook_hook_log_path(web_hook, web_hook_log)

      expect(response).to have_gitlab_http_status(:not_found)

      post retry_admin_hook_hook_log_path(web_hook, web_hook_log)

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  describe 'organization scoping' do
    let(:organization) { current_organization }

    before do
      sign_in(user)
    end

    describe 'GET /admin/hooks/:hook_id/hook_logs/:id' do
      it_behaves_like 'system hook lookup scoped to the organization' do
        def request_system_hook(hook)
          get admin_hook_hook_log_path(hook, create(:web_hook_log, web_hook_id: hook.id))
        end
      end
    end

    describe 'POST /admin/hooks/:hook_id/hook_logs/:id/retry' do
      it_behaves_like 'system hook lookup scoped to the organization' do
        def request_system_hook(hook)
          post retry_admin_hook_hook_log_path(hook, create(:web_hook_log, web_hook_id: hook.id))
        end
      end
    end
  end
end
