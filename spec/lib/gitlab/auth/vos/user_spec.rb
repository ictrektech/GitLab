# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Auth::Vos::User, feature_category: :system_access do
  let_it_be(:organization) { create(:organization) }
  let(:auth) do
    OmniAuth::AuthHash.new(provider: 'vos', uid: 'subject-a',
      info: { nickname: 'vos_subject_a', name: 'Example User', email: 'example@users.invalid' })
  end

  before do
    stub_omniauth_setting(allow_single_sign_on: ['vos'], block_auto_created_users: false,
      auto_link_user: true, auto_link_ldap_user: false)
  end

  it 'creates an ordinary account and reuses it on subsequent logins' do
    first = described_class.new(auth, organization_id: organization.id)
    expect(first.find_and_update!).to be_persisted
    expect(first.gl_user).not_to be_admin
    second = described_class.new(auth, organization_id: organization.id)
    expect(second.gl_user.id).to eq(first.gl_user.id)
  end

  it 'does not auto-link an existing account by email even when globally enabled' do
    existing = create(:user, email: auth.info.email)
    candidate = described_class.new(auth, organization_id: organization.id)
    expect(candidate.gl_user).not_to eq(existing)
    expect(existing.identities.with_provider('vos')).to be_empty
  end

  it 'rejects a blocked mapped account' do
    user = create(:user, :blocked)
    create(:identity, user: user, provider: 'vos', extern_uid: auth.uid)
    expect(described_class.new(auth, organization_id: organization.id)).not_to be_valid_sign_in
  end
end
