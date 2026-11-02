# frozen_string_literal: true

# Requires a context containing:
# - subject: the signed request, with a payload carrying `team_id`
# - team_id
# - service_class: the service the endpoint delegates to
RSpec.shared_examples 'Slack per-workspace rate limited endpoint' do |rate_limit_key:|
  describe 'per-workspace rate limit', :clean_gitlab_redis_rate_limiting do
    let(:log_entry) do
      a_hash_including(
        message: 'Application_Rate_Limiter_Request',
        env: :"#{rate_limit_key}_request_limit",
        method: 'POST',
        slack_workspace: team_id
      )
    end

    before do
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?).and_call_original
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled?)
        .with(rate_limit_key, hash_including(scope: { slack_workspace: team_id }))
        .and_return(true)
    end

    context 'when the workspace is over the limit' do
      it 'drops the request with a 2xx response and does not call the service' do
        allow(Gitlab::AuthLogger).to receive(:error)
        expect(service_class).not_to receive(:new)

        subject

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.headers['RateLimit-Name']).to eq(rate_limit_key.to_s)
        expect(json_response).to eq({})
        expect(Gitlab::AuthLogger).to have_received(:error).with(log_entry).once
      end

      context 'when the slack_app_workspace_rate_limit feature flag is disabled' do
        before do
          stub_feature_flags(slack_app_workspace_rate_limit: false)
        end

        it 'logs the would-be throttle but still calls the service' do
          allow(Gitlab::AuthLogger).to receive(:error)
          expect_next_instance_of(service_class) do |service|
            expect(service).to receive(:execute).and_return(ServiceResponse.success)
          end

          subject

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.headers['RateLimit-Name']).to be_nil
          expect(Gitlab::AuthLogger).to have_received(:error).with(log_entry).once
        end
      end
    end

    context 'when the request signature is not verified' do
      before do
        headers[::API::Integrations::Slack::Request::VERIFICATION_SIGNATURE_HEADER] = 'unverified_signature'
      end

      it 'does not count against the workspace' do
        expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)

        subject

        expect(response).to have_gitlab_http_status(:unauthorized)
      end
    end
  end
end
