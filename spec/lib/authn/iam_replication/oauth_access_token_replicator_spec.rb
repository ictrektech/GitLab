# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::IamReplication::OauthAccessTokenReplicator, feature_category: :system_access do
  let_it_be(:application) { create(:oauth_application) }

  let(:client) { instance_double(Authn::IamService::GrpcClient, upsert_oauth_refresh_token: nil) }

  subject(:replicator) { described_class.new(client: client) }

  describe '.reconciliation_scope' do
    it 'returns only tokens with a refresh token' do
      token = create(:oauth_access_token, application: application)
      create(:oauth_access_token, application: application, refresh_token: nil)

      expect(described_class.reconciliation_scope).to contain_exactly(token)
    end

    it 'excludes tokens without an application' do
      token = create(:oauth_access_token, application: application)
      create(:oauth_access_token, application: application).update_column(:application_id, nil)

      expect(described_class.reconciliation_scope).to contain_exactly(token)
    end

    it 'excludes tokens revoked before the revocation cutoff' do
      live_token = create(:oauth_access_token, application: application)
      revoked_after_cutoff = create(:oauth_access_token,
        application: application, revoked_at: described_class::REVOCATION_CUTOFF + 1.day)
      create(:oauth_access_token, application: application, revoked_at: described_class::REVOCATION_CUTOFF - 1.day)

      expect(described_class.reconciliation_scope).to contain_exactly(live_token, revoked_after_cutoff)
    end
  end

  describe '#upsert' do
    let_it_be(:user) { create(:user) }
    let_it_be(:token) do
      create(:oauth_access_token,
        application: application, resource_owner: user, scopes: 'api read_user', use_refresh_token: true)
    end

    it 'pushes the full field set to IAM and returns :delivered', :aggregate_failures do
      expect(replicator.upsert(token)).to eq(:delivered)
      expect(client).to have_received(:upsert_oauth_refresh_token).once.with(
        signature: token.refresh_token,
        client_id: application.uid,
        subject: user.id.to_s,
        scopes: %w[api read_user],
        revoked_at: nil,
        created_at: Google::Protobuf::Timestamp.new(seconds: token.created_at.to_i),
        owning_cell_id: Gitlab.config.cell.id.to_i,
        source_id: token.id
      )
    end

    context 'with a different configured cell' do
      before do
        stub_config_cell(id: 7)
      end

      it 'sends the configured owning_cell_id' do
        replicator.upsert(token)

        expect(client).to have_received(:upsert_oauth_refresh_token).with(hash_including(owning_cell_id: 7))
      end
    end

    context 'when IAM fails' do
      before do
        allow(client).to receive(:upsert_oauth_refresh_token)
          .and_raise(Authn::IamService::GrpcClient::RequestError.new('down', reason: :unavailable))
      end

      it 'raises' do
        expect { replicator.upsert(token) }.to raise_error(Authn::IamService::GrpcClient::RequestError)
      end
    end

    context 'when the application of the token was deleted' do
      let_it_be(:orphan_application) { create(:oauth_application) }
      let_it_be_with_reload(:orphan_token) { create(:oauth_access_token, application: orphan_application) }

      before do
        orphan_application.delete
      end

      it 'returns :skipped without calling IAM', :aggregate_failures do
        expect(replicator.upsert(orphan_token)).to eq(:skipped)
        expect(client).not_to have_received(:upsert_oauth_refresh_token)
      end
    end

    context 'when the stored refresh token is not a supported digest' do
      let(:token_with_stored_value) do
        create(:oauth_access_token, application: application).tap { |t| t.update_column(:refresh_token, 'test-token') }
      end

      it 'sends its SHA-512 digest as signature' do
        replicator.upsert(token_with_stored_value)

        expect(client).to have_received(:upsert_oauth_refresh_token)
          .with(hash_including(signature: Gitlab::DoorkeeperSecretStoring::Sha512Hash.transform_secret('test-token')))
      end
    end

    context 'when the token is revoked' do
      let_it_be(:revoked_token) do
        create(:oauth_access_token, application: application, revoked_at: 1.minute.ago, use_refresh_token: true)
      end

      it 'sends revoked_at' do
        replicator.upsert(revoked_token)

        expect(client).to have_received(:upsert_oauth_refresh_token).with(
          hash_including(revoked_at: Google::Protobuf::Timestamp.new(seconds: revoked_token.revoked_at.to_i))
        )
      end
    end
  end
end
