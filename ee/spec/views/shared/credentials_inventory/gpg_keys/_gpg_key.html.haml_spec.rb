# frozen_string_literal: true

require 'spec_helper'

RSpec.describe('shared/credentials_inventory/gpg_keys/_gpg_key.html.haml') do
  let(:user) { build_stubbed(:user, email: GpgHelpers::User1.emails.first) }
  let(:gpg_key) do
    build_stubbed(:gpg_key, user: user, key: GpgHelpers::User1.public_key,
      primary_keyid: GpgHelpers::User1.primary_keyid)
  end

  before do
    allow(view).to receive(:user_detail_path).and_return('abcd')
    render 'shared/credentials_inventory/gpg_keys/gpg_key', gpg_key: gpg_key
  end

  it 'shows the users name' do
    expect(rendered).to have_text(user.name)
  end

  it 'shows the ID' do
    expect(rendered).to have_text(gpg_key.primary_keyid)
  end

  context 'shows the status' do
    it 'when the key is verified it shows the verified badge', :aggregate_failures do
      expect(rendered).to have_css('.badge-success')
      expect(rendered).to have_text('Verified')
    end

    context 'when the key is not verified' do
      let(:user) { build_stubbed(:user, email: 'random@example.com') }
      let(:gpg_key) { build_stubbed(:another_gpg_key, user: user, primary_keyid: GpgHelpers::User1.primary_keyid2) }

      it 'shows the unverified badge', :aggregate_failures do
        expect(rendered).to have_css('.badge-danger')
        expect(rendered).to have_text('Unverified')
      end
    end
  end
end
