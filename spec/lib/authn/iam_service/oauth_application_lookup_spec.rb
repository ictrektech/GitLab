# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::IamService::OauthApplicationLookup, :use_clean_rails_memory_store_caching,
  feature_category: :system_access do
  let(:client_id) { 'cross-cell-client' }
  let(:grpc_client) { instance_double(Authn::IamService::GrpcClient) }
  let(:created_at) { Time.zone.parse('2026-10-01T10:00:00Z') }
  let(:response) do
    ::Gitlab::Iam::Auth::V1::InternalOAuthClientsServiceGetClientResponse.new(
      client: ::Gitlab::Iam::Auth::V1::ManagedClient.new(
        client_id: client_id,
        client_name: 'Remote app',
        owner: 'Jane Doe',
        created_at: Google::Protobuf::Timestamp.new(seconds: created_at.to_i)
      )
    )
  end

  subject(:lookup) { described_class.new(client: grpc_client) }

  def request_error(reason)
    Authn::IamService::GrpcClient::RequestError.new("IAM service request failed: #{reason}", reason: reason)
  end

  describe '#find' do
    context 'when IAM knows the client' do
      before do
        allow(grpc_client).to receive(:get_oauth_application).with(client_id: client_id).and_return(response)
      end

      it 'returns the application as IAM describes it', :aggregate_failures do
        application = lookup.find(client_id)

        expect(application).to be_a(Authn::IamService::RemoteOauthApplication)
        expect(application).to have_attributes(
          client_id: client_id, name: 'Remote app', owner_label: 'Jane Doe', created_at: created_at
        )
        expect(application).not_to be_placeholder
      end

      it 'asks IAM once per client id, however many lookups run' do
        expect(grpc_client).to receive(:get_oauth_application).once.and_return(response)

        lookup.find(client_id)

        expect(described_class.new(client: grpc_client).find(client_id))
          .to have_attributes(name: 'Remote app', created_at: created_at)
      end
    end

    context 'when the cache cannot be written' do
      before do
        allow(grpc_client).to receive(:get_oauth_application).and_return(response)
        allow(Rails.cache).to receive(:write).and_raise(StandardError, 'cache down')
      end

      it 'tracks the error and still returns the application', :aggregate_failures do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(an_instance_of(StandardError), client_id: client_id)

        expect(lookup.find(client_id)).to have_attributes(name: 'Remote app', placeholder: nil)
      end

      it 'keeps asking IAM for other client ids' do
        expect(grpc_client).to receive(:get_oauth_application).twice.and_return(response)

        lookup.find(client_id)
        lookup.find('another-client')
      end
    end

    context 'when IAM does not know the client' do
      before do
        allow(grpc_client).to receive(:get_oauth_application).and_raise(request_error(:not_found))
      end

      it 'returns nil' do
        expect(lookup.find(client_id)).to be_nil
      end

      it 'asks again on the next lookup' do
        expect(grpc_client).to receive(:get_oauth_application).twice.and_raise(request_error(:not_found))

        lookup.find(client_id)
        described_class.new(client: grpc_client).find(client_id)
      end

      it 'keeps asking for other client ids' do
        expect(grpc_client).to receive(:get_oauth_application).twice.and_raise(request_error(:not_found))

        lookup.find(client_id)
        lookup.find('another-client')
      end
    end

    context 'when IAM answers without a client' do
      let(:response) { ::Gitlab::Iam::Auth::V1::InternalOAuthClientsServiceGetClientResponse.new }

      before do
        allow(grpc_client).to receive(:get_oauth_application).and_return(response)
      end

      it 'tracks the malformed answer and returns a placeholder, not a not-found', :aggregate_failures do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(an_instance_of(described_class::EmptyResponseError), client_id: client_id)

        expect(lookup.find(client_id)).to be_placeholder
        expect(Rails.cache.read(described_class.cache_key(client_id))).to be_nil
      end
    end

    context 'when IAM answers with a client that has no id' do
      let(:response) do
        ::Gitlab::Iam::Auth::V1::InternalOAuthClientsServiceGetClientResponse.new(
          client: ::Gitlab::Iam::Auth::V1::ManagedClient.new(client_name: 'Nameless')
        )
      end

      before do
        allow(grpc_client).to receive(:get_oauth_application).and_return(response)
      end

      it 'returns a placeholder without caching it', :aggregate_failures do
        expect(lookup.find(client_id)).to be_placeholder
        expect(Rails.cache.read(described_class.cache_key(client_id))).to be_nil
      end
    end

    context 'when IAM cannot answer' do
      before do
        allow(grpc_client).to receive(:get_oauth_application).and_raise(request_error(:unavailable))
      end

      it 'returns a placeholder named after the client id', :aggregate_failures do
        application = lookup.find(client_id)

        expect(application).to be_placeholder
        expect(application).to have_attributes(client_id: client_id, name: client_id)
      end

      it 'logs the failure without raising' do
        expect(Gitlab::AuthLogger).to receive(:error).with(
          hash_including(
            'message' => 'IAM OAuth application lookup failed',
            'client_id' => client_id,
            Labkit::Fields::CLASS_NAME => described_class.name,
            Labkit::Fields::ERROR_TYPE => 'unavailable'
          )
        )

        lookup.find(client_id)
      end

      it 'stops asking IAM for the rest of this lookup' do
        expect(grpc_client).to receive(:get_oauth_application).once.and_raise(request_error(:unavailable))

        lookup.find(client_id)

        expect(lookup.find('another-client')).to be_placeholder
      end

      it 'does not remember the failure beyond this lookup' do
        lookup.find(client_id)
        allow(grpc_client).to receive(:get_oauth_application).and_return(response)

        expect(described_class.new(client: grpc_client).find(client_id)).to have_attributes(name: 'Remote app')
      end
    end

    context 'when the lookup has spent its runtime budget' do
      before do
        allow_next_instance_of(Gitlab::Metrics::RuntimeLimiter) do |limiter|
          allow(limiter).to receive(:over_time?).and_return(true)
        end
      end

      it 'returns a placeholder without asking IAM' do
        expect(grpc_client).not_to receive(:get_oauth_application)

        expect(lookup.find(client_id)).to be_placeholder
      end

      it 'still serves cached applications' do
        Rails.cache.write(described_class.cache_key(client_id),
          Authn::IamService::RemoteOauthApplication.new(client_id: client_id, name: 'Cached app').to_h)

        expect(lookup.find(client_id)).to have_attributes(name: 'Cached app')
      end

      it 'ignores cached fields the application no longer has' do
        Rails.cache.write(described_class.cache_key(client_id),
          { client_id: client_id, name: 'Cached app', renamed_elsewhere: 'stale' })

        expect(lookup.find(client_id)).to have_attributes(name: 'Cached app')
      end
    end

    context 'when the call fails for an unexpected reason' do
      before do
        allow(grpc_client).to receive(:get_oauth_application).and_raise(StandardError, 'boom')
      end

      it 'tracks the error and returns a placeholder' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(an_instance_of(StandardError), client_id: client_id)

        expect(lookup.find(client_id)).to be_placeholder
      end
    end
  end
end
