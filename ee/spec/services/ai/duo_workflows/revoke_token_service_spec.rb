# frozen_string_literal: true

require 'spec_helper'
RSpec.describe ::Ai::DuoWorkflows::RevokeTokenService, feature_category: :duo_agent_platform do
  describe '#execute' do
    let_it_be(:user) { create(:user) }
    let_it_be(:another_user) { create(:user) }

    it 'returns success when token to revoke is invalid' do
      result = described_class.new(token: "not-a-valid-token", current_user: user).execute

      expect(result[:status]).to eq(:success)
    end

    it 'returns error when token to revoke does not belong to current user' do
      token = create(:oauth_access_token, user: another_user, scopes: ['ai_workflows'])

      result = described_class.new(token: token.plaintext_token, current_user: user).execute

      expect(result[:status]).to eq(:error)
      expect(result[:reason]).to eq(:invalid_token_ownership)
      expect(token.reload.revoked?).to be(false)
    end

    it 'returns error when token to revoke has no resource owner' do
      token = create(:oauth_access_token, resource_owner: nil, scopes: ['ai_workflows'])

      result = described_class.new(token: token.plaintext_token, current_user: user).execute

      expect(result[:status]).to eq(:error)
      expect(result[:reason]).to eq(:invalid_token_ownership)
      expect(token.reload.revoked?).to be(false)
    end

    it 'returns error when token to revoke does not have ai_workflows scope' do
      token = create(:oauth_access_token, user: user, scopes: ['api'])

      result = described_class.new(token: token.plaintext_token, current_user: user).execute

      expect(result[:status]).to eq(:error)
      expect(result[:reason]).to eq(:insufficient_token_scope)
      expect(token.reload.revoked?).to be(false)
    end

    it 'returns error when token could not be revoked' do
      token = create(:oauth_access_token, user: user, scopes: ['ai_workflows'])

      allow(Doorkeeper::AccessToken).to receive(:by_token).with(token.plaintext_token).and_return(token)
      allow(token).to receive(:revoke).and_return(false)

      result = described_class.new(token: token.plaintext_token, current_user: user).execute

      expect(result[:status]).to eq(:error)
      expect(result[:reason]).to eq(:failed_to_revoke)
      expect(token.reload.revoked?).to be(false)
    end

    it 'returns success when token could be revoked' do
      token = create(:oauth_access_token, user: user, scopes: ['ai_workflows'])

      result = described_class.new(token: token.plaintext_token, current_user: user).execute

      expect(result[:status]).to eq(:success)
      expect(token.reload.revoked?).to be(true)
    end

    context 'with composite identity' do
      let_it_be(:service_account) { create(:service_account, composite_identity_enforced: true) }
      let_it_be(:regular_user) { create(:user) }
      let_it_be(:another_user) { create(:user) }

      it 'returns success when token belongs to service account but has user scope matching current user' do
        token = create(:oauth_access_token,
          resource_owner: service_account,
          scopes: ['ai_workflows', "user:#{regular_user.id}"]
        )

        result = described_class.new(token: token.plaintext_token, current_user: regular_user).execute

        expect(result[:status]).to eq(:success)
        expect(token.reload.revoked?).to be(true)
      end

      it 'returns error when token has user scope but does not match current user' do
        token = create(:oauth_access_token,
          resource_owner: service_account,
          scopes: ['ai_workflows', "user:#{another_user.id}"]
        )

        result = described_class.new(token: token.plaintext_token, current_user: regular_user).execute

        expect(result[:status]).to eq(:error)
        expect(result[:reason]).to eq(:invalid_token_ownership)
        expect(token.reload.revoked?).to be(false)
      end

      it 'returns error when token belongs to service account but has no user scope' do
        token = create(:oauth_access_token,
          resource_owner: service_account,
          scopes: ['ai_workflows']
        )

        result = described_class.new(token: token.plaintext_token, current_user: regular_user).execute

        expect(result[:status]).to eq(:error)
        expect(result[:reason]).to eq(:invalid_token_ownership)
        expect(token.reload.revoked?).to be(false)
      end

      it 'returns error when user scope has invalid format' do
        token = create(:oauth_access_token,
          resource_owner: service_account,
          scopes: ['ai_workflows', 'user:invalid']
        )

        result = described_class.new(token: token.plaintext_token, current_user: regular_user).execute

        expect(result[:status]).to eq(:error)
        expect(result[:reason]).to eq(:invalid_token_ownership)
        expect(token.reload.revoked?).to be(false)
      end

      it 'returns error when service account does not have composite identity enforced' do
        service_account_without_ci = create(:service_account, composite_identity_enforced: false)
        token = create(:oauth_access_token,
          resource_owner: service_account_without_ci,
          scopes: ['ai_workflows', "user:#{regular_user.id}"]
        )

        result = described_class.new(token: token.plaintext_token, current_user: regular_user).execute

        expect(result[:status]).to eq(:error)
        expect(result[:reason]).to eq(:invalid_token_ownership)
      end
    end

    context 'with a StatelessAccessToken JWT', :clean_gitlab_redis_shared_state do
      let_it_be(:cloud_connector_key) { create(:cloud_connector_keys) }
      let_it_be(:organization) { create(:organization) }

      before do
        allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk).and_return(cloud_connector_key.to_jwk)
        allow(::CloudConnector::Keys).to receive(:valid).and_return([cloud_connector_key])
      end

      def issue_jwt(for_user: user, scopes: ['ai_workflows'], identities: [])
        ::Authn::Tokens::StatelessAccessToken.issue(
          user: for_user, organization: organization, ttl: 1.hour.to_i, scopes: scopes, identities: identities
        ).plaintext_token
      end

      it 'denies the jti and returns success for a matching, in-scope token' do
        jwt = issue_jwt
        token = ::Authn::Tokens::StatelessAccessToken.from_jwt(jwt)

        result = described_class.new(token: jwt, current_user: user).execute

        expect(result[:status]).to eq(:success)
        expect(::Authn::Tokens::StatelessAccessToken.from_jwt(jwt)).to be_revoked
        expect(::Authn::Tokens::StatelessAccessToken::Denylist.denied?(token.id)).to be(true)
      end

      it 'returns error when the token does not belong to current user' do
        jwt = issue_jwt(for_user: another_user)

        result = described_class.new(token: jwt, current_user: user).execute

        expect(result[:status]).to eq(:error)
        expect(result[:reason]).to eq(:invalid_token_ownership)
      end

      it 'returns error when the token lacks the ai_workflows scope' do
        jwt = issue_jwt(scopes: ['api'])

        result = described_class.new(token: jwt, current_user: user).execute

        expect(result[:status]).to eq(:error)
        expect(result[:reason]).to eq(:insufficient_token_scope)
      end

      it 'still revokes the token when the underlying user has since been blocked' do
        blocked_user = create(:user, :blocked)
        jwt = issue_jwt(for_user: blocked_user)

        result = described_class.new(token: jwt, current_user: blocked_user).execute

        expect(result[:status]).to eq(:success)
      end

      it 'returns success (RFC 7009) for an already-expired JWT, via the Doorkeeper fallback' do
        jwt = ::Authn::Tokens::StatelessAccessToken.issue(
          user: user, organization: organization, ttl: -1, scopes: ['ai_workflows']
        ).plaintext_token
        expect(::Authn::Tokens::StatelessAccessToken::Denylist).not_to receive(:deny!)

        result = described_class.new(token: jwt, current_user: user).execute

        expect(result[:status]).to eq(:success)
      end

      it 'returns success (RFC 7009) when revoking an already-denylisted token' do
        jwt = issue_jwt
        token = ::Authn::Tokens::StatelessAccessToken.from_jwt(jwt)
        ::Authn::Tokens::StatelessAccessToken::Denylist.deny!(token)

        result = described_class.new(token: jwt, current_user: user).execute

        expect(result[:status]).to eq(:success)
      end

      context 'with a composite-identity token (service account subject, human identities claim)' do
        let_it_be(:service_account) { create(:service_account, composite_identity_enforced: true) }

        it 'resolves ownership from the embedded human identity, not the service account' do
          jwt = issue_jwt(for_user: service_account, identities: [{ kind: 'user', local_id: user.id }])

          result = described_class.new(token: jwt, current_user: user).execute

          expect(result[:status]).to eq(:success)
          expect(::Authn::Tokens::StatelessAccessToken.from_jwt(jwt)).to be_revoked
        end

        it 'returns error when the current user is not the embedded human identity' do
          jwt = issue_jwt(for_user: service_account, identities: [{ kind: 'user', local_id: another_user.id }])

          result = described_class.new(token: jwt, current_user: user).execute

          expect(result[:status]).to eq(:error)
          expect(result[:reason]).to eq(:invalid_token_ownership)
        end
      end
    end
  end
end
