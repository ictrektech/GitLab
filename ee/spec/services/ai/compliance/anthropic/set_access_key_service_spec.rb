# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Compliance::Anthropic::SetAccessKeyService, feature_category: :compliance_management do
  let(:api_key) { 'sk-ant-api01-test-compliance-access-key' }
  let(:sessions_url) { 'https://api.anthropic.com/v1/compliance/apps/sessions/local' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:sessions_body) { { data: [], next_page: nil }.to_json }

  let(:integration) { build(:ai_compliance_anthropic_integration, api_key: nil) }

  subject(:response) { described_class.new(integration, api_key: api_key).execute }

  def stub_sessions(status:, body:, headers: {})
    stub_request(:get, sessions_url)
      .with(query: { 'limit' => described_class::PROBE_LIMIT })
      .to_return(status: status, body: body, headers: json_headers.merge(headers))
  end

  # Matches the probe only, so a request for a full page fails the expectation.
  def sessions_request
    a_request(:get, sessions_url).with(query: { 'limit' => described_class::PROBE_LIMIT })
  end

  def error_body(type, message)
    { error: { type: type, message: message } }.to_json
  end

  context 'when the key can read local sessions' do
    before do
      stub_sessions(status: 200, body: sessions_body)
    end

    it 'stores the key and enables the integration' do
      expect(response).to be_success
      expect(response.payload[:integration]).to eq(integration)

      expect(integration).to be_persisted
      expect(integration.api_key).to eq(api_key)
      expect(integration.enabled).to be(true)
      expect(integration.disabled_reason).to be_nil
    end

    it 'clears the failure state left by a previous key' do
      integration.consecutive_failure_count = 5
      integration.last_error = 'Compliance API responded with 401'
      integration.disabled_reason = :invalid_key

      expect(response).to be_success
      expect(integration.consecutive_failure_count).to eq(0)
      expect(integration.last_error).to be_nil
      expect(integration.disabled_reason).to be_nil
    end

    it 'validates with a short timeout and a single attempt' do
      expect(Ai::Compliance::Anthropic::Client)
        .to receive(:new)
        .with(
          api_key: api_key,
          timeout: described_class::VALIDATION_TIMEOUT,
          max_attempts: described_class::VALIDATION_ATTEMPTS
        )
        .and_call_original

      response
    end
  end

  context 'when the key has surrounding whitespace' do
    subject(:response) { described_class.new(integration, api_key: "  #{api_key}\n").execute }

    before do
      stub_sessions(status: 200, body: sessions_body)
    end

    it 'verifies and stores the stripped key' do
      expect(response).to be_success
      expect(integration.api_key).to eq(api_key)
      expect(sessions_request.with(headers: { 'x-api-key' => api_key })).to have_been_made.once
    end
  end

  context 'when local sessions are switched off for the Claude organization' do
    before do
      stub_sessions(status: 404, body: error_body('not_found_error', 'Local sessions are not available.'))
    end

    it 'stores the key but leaves the integration disabled with the reason recorded' do
      expect(response).to be_success

      expect(integration).to be_persisted
      expect(integration.api_key).to eq(api_key)
      expect(integration.enabled).to be(false)
      expect(integration).to be_disabled_reason_local_sessions_unavailable
    end
  end

  context 'when the key is rejected' do
    [401, 403].each do |status|
      context "with a #{status}" do
        before do
          stub_sessions(status: status, body: error_body('authentication_error', 'invalid x-api-key'))
        end

        it 'does not store the key' do
          expect(response).to be_error
          expect(response.reason).to eq(:invalid_key)
          expect(integration).not_to be_persisted
        end
      end
    end
  end

  context 'when Anthropic rate limits the request' do
    before do
      stub_sessions(status: 429, body: error_body('rate_limit_error', 'rate limit exceeded'))
    end

    it 'reports a retryable failure without storing the key' do
      expect(response).to be_error
      expect(response.reason).to eq(:rate_limited)
      expect(integration).not_to be_persisted
    end

    it 'does not retry' do
      response

      expect(sessions_request).to have_been_made.once
    end
  end

  context 'when replacing the key of a stored integration' do
    let(:integration) { create(:ai_compliance_anthropic_integration, enabled: true) }
    let!(:previous_key) { integration.api_key }

    before do
      stub_sessions(status: 401, body: error_body('authentication_error', 'invalid x-api-key'))
    end

    it 'keeps the previous key when the new one is rejected' do
      expect(response).to be_error
      expect(integration.reload.api_key).to eq(previous_key)
      expect(integration.enabled).to be(true)
    end
  end

  context 'when the request to Anthropic times out' do
    before do
      stub_request(:get, sessions_url).with(query: { 'limit' => described_class::PROBE_LIMIT }).to_timeout
    end

    it 'reports a verification failure without storing the key' do
      expect(response).to be_error
      expect(response.reason).to eq(:verification_failed)
      expect(integration).not_to be_persisted
    end
  end

  context 'when Anthropic is unreachable' do
    before do
      stub_sessions(
        status: 500,
        body: error_body('api_error', 'internal server error'),
        headers: { 'request-id' => 'req_011' }
      )
    end

    it 'reports a verification failure without storing the key' do
      expect(response).to be_error
      expect(response.reason).to eq(:verification_failed)
      expect(integration).not_to be_persisted
    end

    it 'tracks the error with the Anthropic request id' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
        an_instance_of(Ai::Compliance::Anthropic::Client::TransientError),
        namespace_id: integration.namespace_id,
        request_id: 'req_011'
      )

      response
    end

    it 'does not retry' do
      response

      expect(sessions_request).to have_been_made.once
    end
  end

  context 'when no key is supplied' do
    where(api_key: [nil, '  '])

    with_them do
      it 'fails without calling Anthropic' do
        expect(response).to be_error
        expect(response.reason).to eq(:blank_key)
        expect(sessions_request).not_to have_been_made
        expect(integration).not_to be_persisted
      end
    end
  end

  context 'when the integration itself is invalid' do
    let(:integration) { build(:ai_compliance_anthropic_integration, namespace: create(:group, :nested), api_key: nil) }

    it 'surfaces the model errors without calling Anthropic' do
      expect(response).to be_error
      expect(response.reason).to eq(:invalid_integration)
      expect(response.message).to include('must be a top-level group')
      expect(sessions_request).not_to have_been_made
      expect(integration).not_to be_persisted
      expect(integration.api_key).to be_nil
    end
  end

  context 'when the key is too long to store' do
    let(:api_key) { 'k' * 511 }

    it 'fails without calling Anthropic' do
      expect(response).to be_error
      expect(response.reason).to eq(:invalid_integration)
      expect(sessions_request).not_to have_been_made
      expect(integration.api_key).to be_nil
    end
  end

  context 'when saving the verified key fails' do
    let(:integration) { create(:ai_compliance_anthropic_integration, enabled: false) }
    let!(:previous_key) { integration.api_key }

    before do
      stub_sessions(status: 200, body: sessions_body)
      allow(integration).to receive(:save).and_return(false)
    end

    it 'restores the unsaved attributes on the integration' do
      expect(response).to be_error
      expect(response.reason).to eq(:invalid_integration)
      expect(integration.api_key).to eq(previous_key)
      expect(integration.enabled).to be(false)
      expect(integration).not_to be_changed
    end
  end

  context 'when a concurrent create for the same group wins the race' do
    let(:group) { create(:group) }
    let(:integration) { build(:ai_compliance_anthropic_integration, namespace: group, api_key: nil) }

    before do
      stub_sessions(status: 200, body: sessions_body)

      # The competing row lands after save's uniqueness validation, so the INSERT hits the unique index.
      allow(integration).to receive(:save).and_wrap_original do |original|
        create(:ai_compliance_anthropic_integration, namespace: group)
        original.call(validate: false)
      end
    end

    it 'returns the duplicate integration error and restores the unsaved attributes' do
      expect(response).to be_error
      expect(response.reason).to eq(:invalid_integration)
      expect(response.message).to eq('Namespace has already been taken')
      expect(integration).not_to be_persisted
      expect(integration.api_key).to be_nil
      expect(integration.changed).not_to include(*described_class::STORED_ATTRIBUTES.map(&:to_s))
    end
  end
end
