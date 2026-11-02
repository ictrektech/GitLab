# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::IamService::RejectLoginChallengeService, feature_category: :system_access do
  let(:iam_service_url) { 'https://iam.example.com' }
  let(:challenge) { 'a' * 64 }
  let(:redirect_url) { "#{iam_service_url}/oauth/authorize?client_id=test-app&login_verifier=#{'b' * 64}" }
  let(:response) { ::Gitlab::Iam::Auth::V1::LoginServiceRejectResponse.new(redirect_to: redirect_url) }

  let(:grpc_client) { instance_double(Authn::IamService::GrpcClient) }

  describe '.new' do
    it 'keeps IAM refusals of a stale or forged challenge out of Sentry' do
      expect(Authn::IamService::GrpcClient).to receive(:new).with(report_invalid_requests: false)

      described_class.new(challenge: challenge)
    end
  end

  describe '#execute' do
    subject(:result) { described_class.new(challenge: challenge, client: grpc_client).execute }

    before do
      allow(Authn::IamAuthService).to receive(:url).and_return(iam_service_url)
      allow(grpc_client).to receive(:reject_login_challenge).and_return(response)
    end

    context 'when the IAM service rejects the challenge' do
      it 'returns a success response with the redirect URL', :aggregate_failures do
        expect(result).to be_success
        expect(result.payload[:redirect_to]).to eq(redirect_url)
        expect(grpc_client).to have_received(:reject_login_challenge).with(challenge: challenge)
      end
    end

    context 'when the gRPC client raises a RequestError' do
      before do
        allow(grpc_client).to receive(:reject_login_challenge)
          .and_raise(Authn::IamService::GrpcClient::RequestError, 'Failed to connect to IAM service')
      end

      include_examples 'iam service error response',
        reason: :service_unavailable,
        message: 'Failed to connect to IAM service'
    end

    context 'when the response is missing redirect_to' do
      let(:response) { ::Gitlab::Iam::Auth::V1::LoginServiceRejectResponse.new(redirect_to: '') }

      include_examples 'iam service error response',
        reason: :invalid_response,
        message: 'IAM login reject response missing redirect_to'
    end

    context 'when redirect_to points to a different host' do
      let(:response) { ::Gitlab::Iam::Auth::V1::LoginServiceRejectResponse.new(redirect_to: 'https://untrusted.com/oauth2/authorize') }

      include_examples 'iam service error response',
        reason: :invalid_redirect_url,
        message: 'IAM login reject response contains invalid redirect URL'
    end

    context 'when IAM refuses the challenge' do
      let(:error) { Authn::IamService::GrpcClient::RequestError.new('IAM service request failed: 3', reason: :invalid_request) }

      before do
        allow(grpc_client).to receive(:reject_login_challenge).and_raise(error)
        allow(Gitlab::AuthLogger).to receive(:error)
      end

      it 'returns a client error and logs the gRPC error reason', :aggregate_failures do
        expect(result.reason).to eq(:invalid_request)
        expect(Gitlab::AuthLogger).to have_received(:error)
          .with(hash_including(Labkit::Fields::ERROR_TYPE => 'invalid_request'))
      end
    end
  end
end
