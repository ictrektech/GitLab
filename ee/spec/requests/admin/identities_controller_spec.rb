# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Admin::IdentitiesController, :enable_admin_mode, feature_category: :user_management do
  let_it_be(:admin) { create(:admin) }

  before do
    sign_in(admin)
  end

  describe 'UPDATE group_saml identity' do
    let(:old_saml_provider) { create :saml_provider }
    let!(:new_saml_provider) { create :saml_provider }
    let(:user) do
      create(:omniauth_user, provider: 'group_saml', extern_uid: '000000', saml_provider: old_saml_provider)
    end

    subject(:update_identity) do
      put admin_user_identity_path(user.username, user.identities.last),
        params: { identity: { saml_provider_id: new_saml_provider.id } }
    end

    it 'updates provider_id' do
      expect { update_identity }.to change {
                                      user.reload.identities.last.saml_provider
                                    }.from(old_saml_provider).to(new_saml_provider)
    end
  end
end
