# frozen_string_literal: true

RSpec.shared_examples 'a webhook log policy' do
  let_it_be(:web_hook_log, freeze: false) { create(:web_hook_log, web_hook: web_hook) }

  context 'when the user is authorized' do
    subject(:policy) { described_class.new(authorized_user, web_hook_log) }

    it "can read and resend webhook events" do
      expect(policy).to be_allowed(:read_webhook_event)
      expect(policy).to be_allowed(:resend_webhook_event)
    end
  end

  context 'when the user is not authorized' do
    subject(:policy) { described_class.new(unauthorized_user, web_hook_log) }

    it "cannot read or resend webhook events" do
      expect(policy).to be_disallowed(:read_webhook_event)
      expect(policy).to be_disallowed(:resend_webhook_event)
    end
  end
end
