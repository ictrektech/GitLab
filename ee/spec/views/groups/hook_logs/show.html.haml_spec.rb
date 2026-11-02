# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'groups/hook_logs/show', feature_category: :webhooks do
  let_it_be(:user) { build_stubbed(:user) }

  let(:web_hook) { build_stubbed(:group_hook) }
  let(:web_hook_log) { build_stubbed(:web_hook_log, web_hook: web_hook) }
  let(:can_resend) { true }

  before do
    assign :group, web_hook.group
    assign :hook, web_hook
    assign :hook_log, web_hook_log
    allow(view).to receive(:current_user).and_return(user)
    allow(view).to receive(:can?).and_call_original
    allow(view).to receive(:can?).with(user, :resend_webhook_event, web_hook.group).and_return(can_resend)
    render
  end

  it 'renders the request details page' do
    expect(rendered).to have_text('Request details')
    expect(rendered).to have_text('Resend Request')
  end

  context 'without resend_webhook_event' do
    let(:can_resend) { false }

    it 'does not render the Resend Request button' do
      expect(rendered).to have_text('Request details')
      expect(rendered).not_to have_text('Resend Request')
    end
  end
end
