# frozen_string_literal: true

module Authn
  module IamReplication
    class OauthAccessTokenReplicator
      # Tokens revoked before the sweep first ran were never live in IAM, so the sweep skips them.
      REVOCATION_CUTOFF = Date.new(2026, 10, 21)

      def self.reconciliation_scope
        # rubocop:disable CodeReuse/ActiveRecord -- scope owned by the Layer 4 reconciliation
        ::OauthAccessToken
          .where.not(refresh_token: nil)
          .where.not(application_id: nil)
          .where(revoked_at: [nil, REVOCATION_CUTOFF..])
          .preload(:application)
        # rubocop:enable CodeReuse/ActiveRecord
      end

      def initialize(client: nil, timeout: nil)
        @client = client || ::Authn::IamService::GrpcClient.new(timeout: timeout)
      end

      def upsert(token)
        # The application can be deleted without its tokens.
        return ::Authn::IamReplication::Results::SKIPPED unless token.application

        client.upsert_oauth_refresh_token(**upsert_attributes(token))
        ::Authn::IamReplication::Results::DELIVERED
      end

      private

      attr_reader :client

      # No expires_at: Doorkeeper refresh tokens never expire.
      def upsert_attributes(token)
        {
          signature: ::Authn::IamReplication::HashedSecret.of(token.refresh_token),
          client_id: token.application.uid,
          subject: token.resource_owner_id.to_s,
          scopes: token.scopes.to_a,
          revoked_at: (timestamp(token.revoked_at) if token.revoked_at),
          created_at: timestamp(token.created_at),
          owning_cell_id: Gitlab.config.cell.id.to_i,
          source_id: token.id
        }
      end

      def timestamp(time)
        ::Google::Protobuf::Timestamp.new(seconds: time.to_i)
      end
    end
  end
end
