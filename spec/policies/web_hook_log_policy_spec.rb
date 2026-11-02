# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WebHookLogPolicy, feature_category: :webhooks do
  describe 'read_webhook_event and resend_webhook_event' do
    context 'when the webhook log belongs to a project hook' do
      let_it_be(:web_hook) { create(:project_hook) }
      let_it_be(:authorized_user) { create(:user, maintainer_of: web_hook.project) }
      let_it_be(:unauthorized_user) { create(:user, developer_of: web_hook.project) }

      it_behaves_like 'a webhook log policy'
    end

    context 'when the webhook log belongs to a system hook' do
      let_it_be(:user) { build(:user) }
      let(:web_hook_log) { build_stubbed(:web_hook_log, web_hook: build_stubbed(:system_hook)) }

      subject(:policy) { described_class.new(user, web_hook_log) }

      it { is_expected.to delegate_to(SystemHookPolicy) }
    end
  end
end
