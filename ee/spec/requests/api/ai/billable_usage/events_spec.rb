# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Ai::BillableUsage::Events, feature_category: :"self-hosted_models" do
  describe 'POST /ai/billable_usage/events/com.snowplowanalytics.snowplow/tp2' do
    let_it_be(:group) { create(:group) }
    let_it_be(:service_account) { create(:user, :service_account) }
    let_it_be(:human_user) { create(:user) }
    let_it_be(:tokens) do
      {
        ai_features: create(:personal_access_token, scopes: %w[ai_features], user: service_account),
        api: create(:personal_access_token, scopes: %w[api], user: service_account),
        read_api: create(:personal_access_token, scopes: %w[read_api], user: service_account),
        human_user: create(:personal_access_token, scopes: %w[ai_features], user: human_user)
      }
    end

    let(:path) { '/ai/billable_usage/events/com.snowplowanalytics.snowplow/tp2' }
    let(:access_token) { tokens[:ai_features] }
    let(:headers) do
      { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token.token}" }
    end

    let(:event_id) { SecureRandom.uuid }
    let(:contexts_envelope) do
      {
        schema: 'iglu:com.snowplowanalytics.snowplow/contexts/jsonschema/1-0-1',
        data: [{
          schema: 'iglu:com.gitlab/billable_usage/jsonschema/1-0-3',
          data: {
            event_id: event_id,
            event_type: 'duo_agent_platform_workflow_completion',
            unit_of_measure: 'tokens',
            quantity: 5328.0,
            timestamp: '2026-10-02T10:08:16.196123',
            namespace_id: group.id,
            metadata: { feature_qualified_name: 'duo_agent_platform' }
          }
        }]
      }
    end

    let(:payload) do
      {
        schema: 'iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4',
        data: [{
          e: 'se',
          se_ca: 'DuoWorkflowService',
          se_ac: 'duo_agent_platform_workflow_completion',
          eid: event_id,
          aid: 'gitlab_ai_gateway',
          tv: 'py-1.0.0',
          p: 'srv',
          cx: Base64.urlsafe_encode64(contexts_envelope.to_json)
        }]
      }
    end

    subject(:send_payload) do
      post api(path), params: payload.to_json, headers: headers
    end

    before do
      allow(::Ai::BillableUsage::IngestService).to receive(:enabled?).and_return(true)
    end

    shared_examples 'does not forward the event' do |status|
      it "returns #{status}" do
        expect(::Gitlab::BillingEvents::Client).not_to receive(:track_billing_event)

        send_payload

        expect(response).to have_gitlab_http_status(status)
      end
    end

    context 'when the IngestService is disabled' do
      before do
        allow(::Ai::BillableUsage::IngestService).to receive(:enabled?).and_return(false)
      end

      it_behaves_like 'does not forward the event', :not_found
    end

    context 'when no token is provided' do
      let(:headers) { { 'Content-Type' => 'application/json' } }

      it_behaves_like 'does not forward the event', :unauthorized
    end

    context 'when the token has the read_api scope' do
      let(:access_token) { tokens[:read_api] }

      it_behaves_like 'does not forward the event', :forbidden
    end

    context 'when the token belongs to a human user' do
      let(:access_token) { tokens[:human_user] }

      it_behaves_like 'does not forward the event', :forbidden

      it 'explains the token requirement' do
        send_payload

        expect(json_response['message']).to eq('403 Forbidden - Token must belong to a service account')
      end
    end

    shared_examples 'forwards the billing event' do
      it 'calls the billing client and acknowledges the payload' do
        expect(::Gitlab::BillingEvents::Client).to receive(:track_billing_event).with(
          hash_including(
            event_type: 'duo_agent_platform_workflow_completion',
            category: 'DuoWorkflowService',
            quantity: 5328.0,
            unit_of_measure: 'tokens',
            namespace: group,
            idempotency_key: event_id
          )
        )

        send_payload

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to eq('status' => 'ok')
      end
    end

    context 'when the service account token has the ai_features scope' do
      it_behaves_like 'forwards the billing event'
    end

    context 'when the service account token has the api scope' do
      let(:access_token) { tokens[:api] }

      it_behaves_like 'forwards the billing event'
    end

    context 'when the payload has no data array' do
      let(:payload) { { schema: 'iglu:com.snowplowanalytics.snowplow/payload_data/jsonschema/1-0-4' } }

      it_behaves_like 'does not forward the event', :bad_request

      it 'explains the error' do
        send_payload

        expect(json_response['message']).to include('Invalid Snowplow payload')
      end
    end
  end
end
