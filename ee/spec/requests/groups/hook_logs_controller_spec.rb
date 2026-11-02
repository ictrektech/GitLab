# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::HookLogsController, feature_category: :webhooks do
  let_it_be(:user) { create(:user) }
  let_it_be_with_refind(:web_hook) { create(:group_hook) }
  let_it_be_with_refind(:web_hook_log) { create(:web_hook_log, web_hook: web_hook) }

  let_it_be(:group) { web_hook.group }

  it_behaves_like 'web hook log actions' do
    let(:edit_hook_path) { edit_group_hook_url(group, web_hook) }

    before_all do
      group.add_owner(user)
    end
  end

  context 'when the user is a maintainer' do
    let_it_be(:maintainer) { create(:user, maintainer_of: group) }

    before do
      sign_in(maintainer)
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

  context 'when the user is an auditor' do
    let_it_be(:auditor) { create(:auditor) }

    before do
      stub_licensed_features(auditor_user: true)
      sign_in(auditor)
    end

    it 'returns 200 for show' do
      get web_hook_log.present.details_path

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'returns 404 for retry and does not execute the hook' do
      expect(WebHooks::Events::ResendService).not_to receive(:new)

      post web_hook_log.present.retry_path

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  context 'with a custom role' do
    let_it_be(:role) { create(:member_role, :guest, :admin_web_hook) }
    let_it_be(:membership) { create(:group_member, :guest, member_role: role, user: user, group: group) }

    before do
      stub_licensed_features(custom_roles: true)
    end

    it_behaves_like 'web hook log actions' do
      let(:edit_hook_path) { edit_group_hook_url(group, web_hook) }
    end
  end
end
