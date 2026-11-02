# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Oauth::AuthorizedApplicationsController, feature_category: :system_access do
  let(:user) { create(:user) }
  let(:guest) { create(:user) }
  let(:application) { create(:oauth_application, owner: guest) }

  before do
    sign_in(user)
  end

  describe 'GET #index' do
    it 'responds with 404' do
      get :index

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  describe 'DELETE #destroy' do
    let(:application) { create(:oauth_application) }
    let!(:grant) { create(:oauth_access_grant, resource_owner_id: user.id, application: application) }
    let!(:access_token) { create(:oauth_access_token, resource_owner: user, application: application) }

    before do
      allow_next_instance_of(Authn::IamService::GrpcClient) do |client|
        allow(client).to receive(:revoke_user_client_tokens).and_return(
          ::Gitlab::Iam::Auth::V1::InternalOAuthTokensServiceRevokeUserClientTokensResponse.new
        )
      end
    end

    it 'revokes both access grants and tokens when id is passed', :aggregate_failures do
      expect(grant).not_to be_revoked
      expect(access_token).not_to be_revoked

      delete :destroy, params: { id: application.id }

      expect(grant.reload).to be_revoked
      expect(access_token.reload).to be_revoked
      expect(flash[:notice]).to eq('The application was revoked access.')
    end

    context 'when the revoke service fails' do
      before do
        allow_next_instance_of(Authn::OauthApplications::RevokeService) do |service|
          allow(service).to receive(:execute)
            .and_return(ServiceResponse.error(message: 'nothing changed', reason: :iam_revocation_failed))
        end
      end

      it 'redirects back with the error as an alert', :aggregate_failures do
        delete :destroy, params: { id: application.id }

        expect(response).to redirect_to(user_settings_applications_url)
        expect(flash[:alert]).to eq('nothing changed')
        expect(flash[:notice]).to be_nil
        expect(grant.reload).not_to be_revoked
      end
    end

    it 'delegates to Authn::OauthApplications::RevokeService when id is passed' do
      expect_next_instance_of(
        Authn::OauthApplications::RevokeService,
        current_user: user, application_id: application.id.to_s
      ) do |service|
        expect(service).to receive(:execute).and_call_original
      end

      delete :destroy, params: { id: application.id }
    end

    it 'revokes a specific token when token_id is passed' do
      expect(grant).not_to be_revoked
      expect(access_token).not_to be_revoked

      # id is required for this path, but is not used by the
      # controller
      delete :destroy, params: { id: 9999999, token_id: access_token.id }

      expect(grant.reload).not_to be_revoked
      expect(access_token.reload).to be_revoked
    end
  end

  it 'includes Two-factor enforcement concern' do
    expect(described_class.included_modules.include?(EnforcesTwoFactorAuthentication)).to be(true)
  end
end
