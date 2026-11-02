# frozen_string_literal: true

require 'spec_helper'

RSpec.describe('shared/credentials_inventory/ssh_keys/_ssh_key.html.haml', feature_category: :user_management) do
  let_it_be(:expiry_date) { 20.days.since }
  let_it_be(:ssh_key_delete_path) { |key| 'ssh_key_delete_path' }

  let(:user) { build_stubbed(:user) }
  let(:ssh_key) { build_stubbed(:personal_key, user: user, expires_at: expiry_date) }

  before do
    allow(view).to receive_messages(ssh_key_delete_path: 'key_path', user_detail_path: 'abcd')
    render 'shared/credentials_inventory/ssh_keys/ssh_key', ssh_key: ssh_key
  end

  it 'shows the users name' do
    expect(rendered).to have_text(user.name)
  end

  it 'shows the created on date' do
    expect(rendered).to have_text(ssh_key.created_at.to_date.to_s)
  end

  it 'shows the expiry date' do
    expect(rendered).to have_text(ssh_key.expires_at.to_date.to_s)
  end

  it 'shows the delete button' do
    expect(rendered).to have_css('.js-confirm-modal-button', text: "Delete")
  end

  context 'last accessed date' do
    context 'when set' do
      let_it_be(:last_used_date) { 10.days.ago }
      let(:ssh_key) { build_stubbed(:personal_key, user: user, last_used_at: last_used_date) }

      it 'shows the last accessed on date' do
        expect(rendered).to have_text(ssh_key.last_used_at.to_date.to_s)
      end
    end

    context 'when not set' do
      let(:ssh_key) { build_stubbed(:personal_key, user: user) }

      it 'shows "Never" for the last accessed on date' do
        expect(rendered).to have_text('Last Accessed On Never')
      end
    end
  end
end
