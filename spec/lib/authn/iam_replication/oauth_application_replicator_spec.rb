# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::IamReplication::OauthApplicationReplicator, feature_category: :system_access do
  let(:client) do
    instance_double(Authn::IamService::GrpcClient, upsert_oauth_application: nil, delete_oauth_application: nil)
  end

  subject(:replicator) { described_class.new(client: client) }

  describe '.reconciliation_scope' do
    it 'returns every application' do
      applications = [create(:oauth_application), create(:oauth_application, :dynamic)]

      expect(described_class.reconciliation_scope).to match_array(applications)
    end
  end

  describe '#upsert' do
    let_it_be(:application) { create(:oauth_application) }

    it 'pushes the full field set to IAM and returns :delivered', :aggregate_failures do
      expect(replicator.upsert(application)).to eq(:delivered)
      expect(client).to have_received(:upsert_oauth_application).once.with(
        client_id: application.uid,
        hashed_client_secret: application.secret,
        redirect_uris: application.redirect_uri.split,
        grant_types: %w[authorization_code refresh_token client_credentials],
        response_types: %w[code],
        scopes: application.scopes.to_a,
        public: !application.confidential?,
        client_name: application.name,
        owner: application.owner.name,
        trusted: application.trusted?,
        created_at: Google::Protobuf::Timestamp.new(seconds: application.created_at.to_i),
        updated_at: Google::Protobuf::Timestamp.new(seconds: application.updated_at.to_i),
        dynamic: false,
        organization_id: application.organization.uuid,
        owning_cell_id: Gitlab.config.cell.id.to_i,
        source_id: application.id
      )
    end

    it 'sends a hashed_client_secret in the digest format IAM validates' do
      replicator.upsert(application)

      expect(client).to have_received(:upsert_oauth_application)
        .with(hash_including(hashed_client_secret: match(/\A[0-9a-f]{128}\z/)))
    end

    it 'sends an organization_id in the UUIDv7 format IAM validates' do
      replicator.upsert(application)

      expect(client).to have_received(:upsert_oauth_application).with(
        hash_including(
          organization_id: match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
        )
      )
    end

    context 'with a different configured cell' do
      before do
        stub_config_cell(id: 7)
      end

      it 'sends the configured owning_cell_id' do
        replicator.upsert(application)

        expect(client).to have_received(:upsert_oauth_application).with(hash_including(owning_cell_id: 7))
      end
    end

    context 'when IAM fails' do
      before do
        allow(client).to receive(:upsert_oauth_application)
          .and_raise(Authn::IamService::GrpcClient::RequestError.new('down', reason: :unavailable))
      end

      it 'raises' do
        expect { replicator.upsert(application) }.to raise_error(Authn::IamService::GrpcClient::RequestError)
      end
    end

    context 'when the application is not confidential' do
      let(:application) { create(:oauth_application, confidential: false) }

      it 'omits client_credentials and marks the app public' do
        replicator.upsert(application)

        expect(client).to have_received(:upsert_oauth_application).with(
          hash_including(public: true, grant_types: %w[authorization_code refresh_token])
        )
      end
    end

    context 'when the application has no owner' do
      let(:application) { create(:oauth_application, :without_owner) }

      it 'sends the administrator label' do
        replicator.upsert(application)

        expect(client).to have_received(:upsert_oauth_application).with(hash_including(owner: 'An administrator'))
      end
    end

    context 'when the application is dynamic' do
      let(:application) { create(:oauth_application, :dynamic) }

      it 'sends no owner and marks it as dynamic' do
        replicator.upsert(application)

        expect(client).to have_received(:upsert_oauth_application).with(hash_including(owner: nil, dynamic: true))
      end
    end

    context 'when the application is owned by a group' do
      let(:application) { create(:oauth_application, :group_owned) }

      it 'sends the group name' do
        replicator.upsert(application)

        expect(client).to have_received(:upsert_oauth_application).with(hash_including(owner: application.owner.name))
      end
    end

    context 'when the application has multiple redirect URIs' do
      let(:application) do
        create(:oauth_application, redirect_uri: "https://a.example.com\nhttps://b.example.com")
      end

      it 'splits them into an array' do
        replicator.upsert(application)

        expect(client).to have_received(:upsert_oauth_application).with(
          hash_including(redirect_uris: %w[https://a.example.com https://b.example.com])
        )
      end
    end

    context 'when the stored secret is not a supported digest' do
      let(:application_with_stored_secret) do
        create(:oauth_application).tap { |app| app.update_column(:secret, 'test-secret') }
      end

      it 'sends its SHA-512 digest and returns :delivered', :aggregate_failures do
        expect(replicator.upsert(application_with_stored_secret)).to eq(:delivered)
        expect(client).to have_received(:upsert_oauth_application)
          .with(hash_including(hashed_client_secret: Gitlab::DoorkeeperSecretStoring::Sha512Hash.transform_secret('test-secret')))
      end
    end
  end

  describe '#bulk_upsert' do
    let_it_be(:applications) { create_list(:oauth_application, 2) }

    before do
      allow(client).to receive(:bulk_upsert_oauth_applications).and_return(
        ::Gitlab::Iam::Auth::V1::InternalOAuthClientsServiceBulkUpsertClientsResponse.new(
          results: [{ reason: :REASON_WRITTEN }, { reason: :REASON_INVALID, message: 'invalid' }]
        )
      )
    end

    it 'sends every application in one call' do
      replicator.bulk_upsert(applications)

      expect(client).to have_received(:bulk_upsert_oauth_applications).once.with(clients: [
        hash_including(client_id: applications.first.uid, source_id: applications.first.id),
        hash_including(client_id: applications.second.uid, source_id: applications.second.id)
      ])
    end

    it 'returns the outcome, the IAM message and the IAM reason for each application' do
      expect(replicator.bulk_upsert(applications)).to eq([
        [applications.first, :delivered, nil, 'REASON_WRITTEN'],
        [applications.second, :invalid_request, 'invalid', 'REASON_INVALID']
      ])
    end

    context 'when IAM returns a different number of results than clients' do
      where(returned: [1, 3])

      with_them do
        before do
          allow(client).to receive(:bulk_upsert_oauth_applications).and_return(
            ::Gitlab::Iam::Auth::V1::InternalOAuthClientsServiceBulkUpsertClientsResponse.new(
              results: Array.new(returned) { { reason: :REASON_WRITTEN } }
            )
          )
        end

        it 'raises' do
          expect { replicator.bulk_upsert(applications) }.to raise_error(
            ::Authn::IamService::GrpcClient::RequestError, "IAM returned #{returned} results for 2 clients"
          )
        end
      end
    end

    context 'with no applications' do
      it 'returns nothing without calling IAM', :aggregate_failures do
        expect(replicator.bulk_upsert([])).to eq([])
        expect(client).not_to have_received(:bulk_upsert_oauth_applications)
      end
    end
  end

  describe '#deliver' do
    context 'with an upsert event' do
      let_it_be(:application) { create(:oauth_application) }
      let(:row) { build(:iam_outbox, entity_id: application.id) }

      it 'upserts the application and returns :delivered', :aggregate_failures do
        expect(replicator.deliver(row)).to eq(:delivered)
        expect(client).to have_received(:upsert_oauth_application).with(hash_including(source_id: application.id))
      end

      context 'when the upsert fails' do
        before do
          allow(client).to receive(:upsert_oauth_application)
            .and_raise(Authn::IamService::GrpcClient::RequestError.new('down', reason: :unavailable))
        end

        it 'raises' do
          expect { replicator.deliver(row) }.to raise_error(Authn::IamService::GrpcClient::RequestError)
        end
      end

      context 'when the Rails record is absent' do
        let(:row) { build(:iam_outbox, entity_id: non_existing_record_id) }

        it 'returns :skipped without calling IAM', :aggregate_failures do
          expect(replicator.deliver(row)).to eq(:skipped)
          expect(client).not_to have_received(:upsert_oauth_application)
        end
      end
    end

    context 'with a delete event' do
      let(:uid) { build(:oauth_application).uid }
      let(:row) { build(:iam_outbox, event_type: :delete, payload: { 'uid' => uid }) }

      it 'removes via the payload uid and returns :delivered', :aggregate_failures do
        expect(replicator.deliver(row)).to eq(:delivered)
        expect(client).to have_received(:delete_oauth_application).with(client_id: uid)
      end

      context 'with a symbol-keyed payload' do
        let(:row) { build(:iam_outbox, event_type: :delete, payload: { uid: uid }) }

        it 'removes via the payload uid' do
          replicator.deliver(row)

          expect(client).to have_received(:delete_oauth_application).with(client_id: uid)
        end
      end

      context 'without a uid in the payload' do
        let(:row) { build(:iam_outbox, event_type: :delete, payload: {}) }

        it 'raises' do
          expect { replicator.deliver(row) }.to raise_error(KeyError)
        end
      end

      context 'when IAM no longer has the client' do
        before do
          allow(client).to receive(:delete_oauth_application)
            .and_raise(Authn::IamService::GrpcClient::RequestError.new('gone', reason: :not_found))
        end

        it 'returns :delivered' do
          expect(replicator.deliver(row)).to eq(:delivered)
        end
      end

      context 'when the delete fails for another reason' do
        before do
          allow(client).to receive(:delete_oauth_application)
            .and_raise(Authn::IamService::GrpcClient::RequestError.new('down', reason: :unavailable))
        end

        it 'raises' do
          expect { replicator.deliver(row) }.to raise_error(Authn::IamService::GrpcClient::RequestError)
        end
      end
    end

    context 'with an event_type the replicator does not handle' do
      let(:row) { instance_double(Authn::IamOutbox, event_type: 'unknown') }

      it 'raises' do
        expect { replicator.deliver(row) }.to raise_error(ArgumentError, /unhandled event_type/)
      end
    end
  end
end
