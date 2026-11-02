# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Internal::Workhorse, :allow_forgery_protection, feature_category: :shared do
  include WorkhorseHelpers

  context '/authorize_upload' do
    let_it_be(:user) { create(:user) }

    let(:headers) { {} }

    subject { post(api('/internal/workhorse/authorize_upload'), headers: headers) }

    def expect_status(status)
      subject
      expect(response).to have_gitlab_http_status(status)
    end

    context 'without workhorse internal header', :verify_workhorse_jwt do
      it { expect_status(:forbidden) }
    end

    context 'with workhorse internal header' do
      let(:headers) { workhorse_internal_api_request_header }

      it { expect_status(:unauthorized) }

      context 'as a logged in user' do
        before do
          login_as(user)
        end

        it { expect_status(:success) }

        it 'returns the temp upload path' do
          subject
          expect(json_response['TempPath']).to eq(Rails.root.join('tmp/tests/public/uploads/tmp').to_s)
        end
      end
    end
  end

  context '/oauth_routing', feature_category: :system_access do
    let_it_be(:application) { create(:oauth_application) }
    let(:headers) { workhorse_internal_api_request_header }
    let(:params) { { client_id: application.uid } }

    subject(:perform_request) do
      post(api('/internal/workhorse/oauth_routing'), headers: headers, params: params)
    end

    context 'without workhorse internal header', :verify_workhorse_jwt do
      let(:headers) { {} }

      it 'returns 403 forbidden' do
        perform_request

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'with workhorse internal header' do
      it 'returns the workhorse vendor content type' do
        perform_request

        expect(response.media_type).to eq(Gitlab::Workhorse::INTERNAL_API_CONTENT_TYPE)
      end

      context 'when the feature flag is enabled for the application' do
        before do
          stub_feature_flags(proxy_oauth_requests_to_iam_service: application)
        end

        it 'routes to IAM', :aggregate_failures do
          perform_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to eq('destination' => 'iam')
        end
      end

      context 'when the feature flag is disabled for the application' do
        before do
          stub_feature_flags(proxy_oauth_requests_to_iam_service: false)
        end

        it 'routes to Rails', :aggregate_failures do
          perform_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to eq('destination' => 'rails')
        end
      end

      context 'when the client_id does not match any application' do
        let(:params) { { client_id: 'nonexistent-client-id' } }

        it 'routes to IAM', :aggregate_failures do
          perform_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to eq('destination' => 'iam')
        end
      end

      context 'when the client_id parameter is missing' do
        let(:params) { {} }

        it 'routes to IAM', :aggregate_failures do
          perform_request

          expect(response).to have_gitlab_http_status(:ok)
          expect(json_response).to eq('destination' => 'iam')
        end
      end
    end
  end

  context '/register_routing', :clean_gitlab_redis_rate_limiting, feature_category: :system_access do
    using RSpec::Parameterized::TableSyntax

    let(:headers) { workhorse_internal_api_request_header }
    let(:client_ip) { '203.0.113.7' }
    let(:flag_enabled) { true }
    let(:skip_limit) { false }
    let(:limit) do
      ::Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits
        .rule_for(:oauth_dynamic_registration).limit
    end

    before do
      stub_feature_flags(proxy_dcr_to_iam: flag_enabled)
      allow(::Oauth::DynamicRegistrationsController).to receive(:skip_rate_limit?).and_return(skip_limit)
      stub_env('GITLAB_THROTTLE_BYPASS_HEADER', 'Gitlab-Bypass-Rate-Limiting')
    end

    def perform_request(ip: client_ip, bypass: false)
      request_headers = headers.merge('X-Forwarded-For' => ip)
      request_headers['Gitlab-Bypass-Rate-Limiting'] = '1' if bypass

      post(api('/internal/workhorse/register_routing'), headers: request_headers)
    end

    def destination_for(ip: client_ip, bypass: false)
      perform_request(ip: ip, bypass: bypass)
      json_response['destination']
    end

    def exhaust_limit(count = limit)
      count.times { perform_request }
    end

    def client_ip_throttled?
      ::Gitlab::ApplicationRateLimiter.peek(:oauth_dynamic_registration, scope: { ip: client_ip })
    end

    context 'without workhorse internal header', :verify_workhorse_jwt do
      let(:headers) { {} }

      it 'returns 403 forbidden' do
        perform_request

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'with workhorse internal header' do
      where(:flag_enabled, :skip_limit, :over_limit, :destination, :reason, :throttled) do
        false | false | true  | 'rails' | 'flag_disabled' | false
        true  | false | false | 'iam'   | nil             | false
        true  | false | true  | 'rails' | 'rate_limited'  | true
        true  | true  | true  | 'iam'   | nil             | false
      end

      with_them do
        it 'returns the routing decision and throttles only limited requests', :aggregate_failures do
          exhaust_limit(over_limit ? limit : limit - 1)

          expect(destination_for).to eq(destination)
          expect(json_response['reason']).to eq(reason)
          expect(response).to have_gitlab_http_status(:ok)
          expect(response.media_type).to eq(Gitlab::Workhorse::INTERNAL_API_CONTENT_TYPE)
          expect(client_ip_throttled?).to be(throttled)
        end
      end
    end

    context 'when the client IP is over the limit' do
      before do
        exhaust_limit
      end

      where(:scenario, :forwarded_for, :bypass, :destination) do
        'another client IP'                  | '198.51.100.9'              | false | 'iam'
        'spoofed entry before the client IP' | '198.51.100.9, 203.0.113.7' | false | 'rails'
        'trusted proxy after the client IP'  | '203.0.113.7, 127.0.0.1'    | false | 'rails'
        'throttle bypass header'             | '203.0.113.7'               | true  | 'iam'
      end

      with_them do
        it 'returns the routing decision' do
          expect(destination_for(ip: forwarded_for, bypass: bypass)).to eq(destination)
        end
      end

      it 'logs the throttled request like the controller' do
        expect(::Gitlab::AuthLogger).to receive(:error).with(
          hash_including(
            message: 'Application_Rate_Limiter_Request',
            env: :oauth_dynamic_registration_request_limit,
            remote_ip: client_ip
          )
        ).and_call_original

        perform_request
      end
    end
  end
end
