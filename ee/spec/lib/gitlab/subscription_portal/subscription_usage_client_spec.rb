# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::SubscriptionPortal::SubscriptionUsageClient, feature_category: :consumables_cost_management do
  let(:graphql_url) { ::Gitlab::Routing.url_helpers.subscription_portal_graphql_url }
  let(:request_options) { {} }
  let(:portal_unavailable_returns_server_error) { false }
  let(:params) do
    { query: query, variables: { instanceId: Gitlab::GlobalAnonymousId.instance_id }.merge(variables) }
  end

  let(:headers) do
    {
      "Accept" => "application/json",
      "Content-Type" => "application/json",
      "User-Agent" => "GitLab/#{Gitlab::VERSION}"
    }.merge(admin_headers || {})
  end

  let(:start_date) { '2025-10-01' }
  let(:end_date) { '2025-10-31' }

  subject(:client) do
    described_class.new(
      namespace_id: namespace_id,
      license_key: license_key,
      start_date: start_date,
      end_date: end_date
    )
  end

  shared_examples 'performs request with correct params' do
    it 'perform post request with correct params' do
      expect(::Gitlab::HTTP).to receive(:post).with(
        graphql_url,
        headers: headers,
        body: params.to_json,
        **request_options
      ).and_return(instance_double(
        HTTParty::Response,
        response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
        parsed_response: portal_response
      ))

      request
    end
  end

  shared_examples 'returns successfully' do
    it 'returns a successful response' do
      expect(::Gitlab::HTTP).to receive(:post).with(
        graphql_url,
        headers: headers,
        body: params.to_json,
        **request_options
      ).and_return(instance_double(
        HTTParty::Response,
        response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
        parsed_response: portal_response
      ))

      expect(request).to eq(expected_response)
    end
  end

  shared_examples 'raises error on unsuccessful subscription portal response' do
    it 'raises an error from subscription portal' do
      response = instance_double(
        HTTParty::Response,
        response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
        parsed_response: {
          success: false,
          data: {
            errors: 'some error'
          }
        }
      )

      expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception).with(
        a_kind_of(described_class::ResponseError),
        query: query,
        response: response.parsed_response
      ).and_call_original

      expect(::Gitlab::HTTP).to receive(:post).with(
        graphql_url,
        headers: headers,
        body: params.to_json,
        **request_options
      ).and_return(response)

      expect { request }.to raise_error(described_class::ResponseError, 'Received an error from CustomerDot')
    end

    it 'raises an error when subscription portal is not available' do
      # get_sessions maps a 5xx to `reason: :server_error` instead; see its own spec.
      skip 'this query returns :server_error on 5xx' if portal_unavailable_returns_server_error

      http_response = instance_double(
        HTTParty::Response,
        response: Net::HTTPServiceUnavailable.new(1.0, '503', 'Service Unavailable')
      )

      expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception).with(
        a_kind_of(described_class::ResponseError),
        query: query,
        response: { data: { errors: 'Service Unavailable' }, http_status: 503 }
      ).and_call_original

      expect(::Gitlab::HTTP).to receive(:post).with(
        graphql_url,
        headers: headers,
        body: params.to_json,
        **request_options
      ).and_return(http_response)

      expect { request }.to raise_error(described_class::ResponseError, 'Received an error from CustomerDot')
    end
  end

  shared_context 'for self-managed request' do
    let(:admin_headers) { nil }
    let(:namespace_id) { nil }
    let(:license_key) { 'license_key' }

    include_examples 'performs request with correct params'
    include_examples 'returns successfully'
    include_examples 'raises error on unsuccessful subscription portal response'
  end

  shared_context 'for gitlab.com request' do
    let(:namespace_id) { 1234 }
    let(:license_key) { nil }
    let(:admin_headers) do
      {
        "X-Admin-Email" => "gl_com_api@gitlab.com",
        "X-Admin-Token" => "customer_admin_token"
      }
    end

    include_examples 'performs request with correct params'
    include_examples 'returns successfully'
    include_examples 'raises error on unsuccessful subscription portal response'
  end

  describe '#get_metadata' do
    let(:request) { client.get_metadata }
    let(:query) { described_class::GET_METADATA_QUERY }
    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            gitlabCreditsUsage: {
              startDate: "2025-10-01",
              endDate: "2025-10-31",
              enabled: true,
              isOutdatedClient: false,
              lastEventTransactionAt: "2025-10-01T16:19:59Z",
              overageTermsAccepted: true,
              canAcceptOverageTerms: true,
              dapPromoEnabled: false,
              usageDashboardPath: "/subscriptions/A-S00012345/usage"
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        subscriptionUsage: {
          startDate: "2025-10-01",
          endDate: "2025-10-31",
          enabled: true,
          isOutdatedClient: false,
          lastEventTransactionAt: "2025-10-01T16:19:59Z",
          overageTermsAccepted: true,
          canAcceptOverageTerms: true,
          dapPromoEnabled: false,
          usageDashboardPath: "/subscriptions/A-S00012345/usage"
        }
      }
    end

    include_context 'for self-managed request' do
      let(:variables) do
        { licenseKey: license_key, startDate: start_date, endDate: end_date, gitlabVersion: Gitlab::VERSION }
      end
    end

    include_context 'for gitlab.com request' do
      let(:variables) do
        { namespaceId: namespace_id, startDate: start_date, endDate: end_date, gitlabVersion: Gitlab::VERSION }
      end
    end
  end

  describe '#get_subscription_usage' do
    let(:request) { client.get_subscription_usage({ sort: :date_asc, limit: 30 }) }
    let(:query) { described_class::GET_SUBSCRIPTION_USAGE_QUERY }
    let(:credits_used) { 287.45 }
    let(:daily_average) { 123.45 }
    let(:daily_usage) { [{ date: '2025-10-01', creditsUsed: 123.45 }] }

    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            gitlabCreditsUsage: {
              creditsUsed: credits_used,
              dailyAverage: daily_average,
              dailyUsage: daily_usage
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        subscriptionUsage: {
          creditsUsed: credits_used,
          dailyAverage: daily_average,
          dailyUsage: daily_usage
        }
      }
    end

    include_context 'for self-managed request' do
      let(:variables) do
        {
          licenseKey: license_key,
          startDate: start_date,
          endDate: end_date,
          sort: 'DATE_ASC',
          limit: 30
        }
      end
    end

    include_context 'for gitlab.com request' do
      let(:variables) do
        {
          namespaceId: namespace_id,
          startDate: start_date,
          endDate: end_date,
          sort: 'DATE_ASC',
          limit: 30
        }
      end
    end

    context 'when called without args' do
      let(:request) { client.get_subscription_usage }

      include_context 'for self-managed request' do
        let(:variables) do
          {
            licenseKey: license_key,
            startDate: start_date,
            endDate: end_date
          }
        end
      end

      include_context 'for gitlab.com request' do
        let(:variables) do
          {
            namespaceId: namespace_id,
            startDate: start_date,
            endDate: end_date
          }
        end
      end
    end

    context 'when flow_types are provided' do
      let(:request) { client.get_subscription_usage(sort: :date_asc, limit: 30, flow_types: %w[chat]) }

      include_context 'for self-managed request' do
        let(:variables) do
          {
            licenseKey: license_key,
            startDate: start_date,
            endDate: end_date,
            sort: 'DATE_ASC',
            limit: 30,
            flowTypes: %w[chat]
          }
        end
      end

      include_context 'for gitlab.com request' do
        let(:variables) do
          {
            namespaceId: namespace_id,
            startDate: start_date,
            endDate: end_date,
            sort: 'DATE_ASC',
            limit: 30,
            flowTypes: %w[chat]
          }
        end
      end
    end
  end

  describe '#get_non_billable_usage' do
    let(:request_options) { { read_timeout: described_class::CLICKHOUSE_QUERY_READ_TIMEOUT } }
    let(:request) { client.get_non_billable_usage(flow_types: %w[orbit_mcp]) }
    let(:query) { described_class::GET_NON_BILLABLE_USAGE_QUERY }
    let(:non_billable_usage) do
      [
        {
          productId: 'orbit',
          skipReason: 'promo',
          totalCreditsUsed: 30.0,
          dailyUsage: [{ date: '2025-10-01', creditsUsed: 10.0 }, { date: '2025-10-02', creditsUsed: 20.0 }]
        },
        {
          productId: 'orbit',
          skipReason: nil,
          totalCreditsUsed: 3.0,
          dailyUsage: [{ date: '2025-10-01', creditsUsed: 3.0 }]
        }
      ]
    end

    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            gitlabCreditsUsage: {
              nonBillableUsage: non_billable_usage
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        nonBillableUsage: non_billable_usage
      }
    end

    include_context 'for self-managed request' do
      let(:variables) do
        {
          licenseKey: license_key,
          startDate: start_date,
          endDate: end_date,
          flowTypes: %w[orbit_mcp]
        }
      end
    end

    include_context 'for gitlab.com request' do
      let(:variables) do
        {
          namespaceId: namespace_id,
          startDate: start_date,
          endDate: end_date,
          flowTypes: %w[orbit_mcp]
        }
      end
    end

    context 'when called without flow types' do
      let(:request) { client.get_non_billable_usage }

      include_context 'for gitlab.com request' do
        let(:variables) do
          {
            namespaceId: namespace_id,
            startDate: start_date,
            endDate: end_date
          }
        end
      end
    end

    context 'when CustomersDot could not read nonBillableUsage' do
      let(:namespace_id) { 1234 }
      let(:license_key) { nil }
      let(:portal_response) do
        {
          data: { subscription: { gitlabCreditsUsage: { nonBillableUsage: nil } } },
          errors: [
            {
              message: 'nonBillableUsage is temporarily unavailable',
              path: %w[subscription gitlabCreditsUsage nonBillableUsage],
              extensions: { code: 'NON_BILLABLE_USAGE_UNAVAILABLE' }
            }
          ]
        }
      end

      it 'warns and returns unsuccessfully instead of raising' do
        allow(::Gitlab::HTTP).to receive(:post).and_return(instance_double(
          HTTParty::Response,
          response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
          parsed_response: portal_response
        ))

        expect(Gitlab::ErrorTracking).not_to receive(:track_and_raise_exception)
        expect(Gitlab::AppLogger).to receive(:warn).with(
          hash_including(Labkit::Fields::LOG_MESSAGE => 'CustomersDot could not read nonBillableUsage')
        )

        expect(request).to eq({ success: false, nonBillableUsage: nil })
      end
    end

    context 'when called more than once with the same arguments' do
      let(:namespace_id) { 1234 }
      let(:license_key) { nil }

      it 'memoizes the result and performs a single request' do
        expect(::Gitlab::HTTP).to receive(:post).once.and_return(instance_double(
          HTTParty::Response,
          response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
          parsed_response: portal_response
        ))

        expect(request).to eq(expected_response)
        expect(client.get_non_billable_usage(flow_types: %w[orbit_mcp])).to eq(expected_response)
      end
    end
  end

  describe '#get_sessions' do
    # Every failure raises now, including a 5xx, so the shared unavailable example applies.
    let(:portal_unavailable_returns_server_error) { false }
    let(:request_options) { { read_timeout: described_class::CLICKHOUSE_QUERY_READ_TIMEOUT } }
    let(:updated_after) { Time.utc(2026, 9, 29, 10, 0, 0) }
    let(:updated_after_param) { '2026-09-29T10:00:00.000000Z' }
    let(:request) { client.get_sessions(updated_after: updated_after) }
    let(:query) { described_class::GET_SESSIONS_QUERY }

    let(:session_nodes) do
      [
        {
          workflowId: '11',
          creditsUsed: '12.5000',
          modelsUsed: %w[claude-opus-5 gpt-5],
          updatedAt: '2026-09-29T10:05:00.123456Z',
          creditsByModel: [
            { model: 'claude-opus-5', creditsUsed: '12.5000' },
            # A model the session used but was credited nothing for. Present, not absent.
            { model: 'gpt-5', creditsUsed: '0.0' }
          ]
        }
      ]
    end

    let(:page_info) { { hasNextPage: false, endCursor: 'b3BhcXVlLWN1cnNvcg' } }
    let(:synced_at) { '2026-09-29T10:10:00.000000Z' }

    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            gitlabCreditsUsage: {
              sessionsSyncedAt: synced_at,
              sessions: { nodes: session_nodes, pageInfo: page_info }
            }
          }
        }
      }
    end

    let(:expected_response) do
      { success: true, sessions: session_nodes, page_info: page_info, synced_at: synced_at }
    end

    include_context 'for self-managed request' do
      let(:variables) do
        { licenseKey: license_key, updatedAfter: updated_after_param, first: 1000 }
      end
    end

    include_context 'for gitlab.com request' do
      let(:variables) do
        { namespaceId: namespace_id, updatedAfter: updated_after_param, first: 1000 }
      end
    end

    describe 'the query itself' do
      it 'asks for everything the v2 ingest writes' do
        expect(query).to include('creditsUsed', 'modelsUsed', 'updatedAt', 'creditsByModel', 'pageInfo',
          'sessionsSyncedAt')
      end

      it 'declares updatedAfter with the microsecond scalar CustomersDot defines' do
        expect(query).to include('$updatedAfter: ISO8601DateTimeMicro!')
      end

      it 'sends no date window, because creditsUsed is a lifetime total' do
        expect(query).not_to include('startDate', 'endDate')
      end

      # The substring checks above cannot fail for a malformed query. Nothing else
      # parses this heredoc: gitlab:graphql:validate only covers .graphql files, and
      # CustomersDot's schema is not committed anywhere, so a typo would otherwise
      # surface only at runtime against the real portal.
      it 'is syntactically valid GraphQL' do
        expect { GraphQL.parse(query) }.not_to raise_error
      end
    end

    describe 'argument handling' do
      let(:namespace_id) { 1234 }
      let(:license_key) { nil }

      # Without this the failure surfaces as our own Net::ReadTimeout, which loses the
      # reason CustomersDot would have reported -- the thing this query logs on.
      it 'gives CustomersDot room to hit its own 20s query limit first' do
        expect(::Gitlab::HTTP).to receive(:post)
          .with(graphql_url, hash_including(read_timeout: 25))
          .and_return(instance_double(HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'), parsed_response: portal_response))

        request
      end

      it 'does not mutate the caller\'s Time' do
        non_utc = Time.new(2026, 9, 29, 12, 0, 0, '+02:00')
        original = non_utc.dup

        allow(::Gitlab::HTTP).to receive(:post).and_return(instance_double(
          HTTParty::Response,
          response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
          parsed_response: portal_response
        ))

        client.get_sessions(updated_after: non_utc)

        expect(non_utc).to eq(original)
        expect(non_utc.utc?).to be(false)
      end

      it 'serialises a non-UTC Time as the equivalent UTC instant' do
        expect(::Gitlab::HTTP).to receive(:post) do |_url, options|
          expect(Gitlab::Json::SafeParser.parse(options[:body]).dig('variables', 'updatedAfter'))
            .to eq('2026-09-29T10:00:00.000000Z')

          instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: portal_response
          )
        end

        client.get_sessions(updated_after: Time.new(2026, 9, 29, 12, 0, 0, '+02:00'))
      end
    end

    context 'with gitlab.com auth' do
      let(:namespace_id) { 1234 }
      let(:license_key) { nil }

      def stub_portal(response = portal_response, times: 1)
        expect(::Gitlab::HTTP).to receive(:post).exactly(times).times.and_return(instance_double(
          HTTParty::Response,
          response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
          parsed_response: response
        ))
      end

      it 'does not send a blank cursor' do
        expect(::Gitlab::HTTP).to receive(:post) do |_url, options|
          expect(Gitlab::Json::SafeParser.parse(options[:body])['variables'].keys).not_to include('after')

          instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: portal_response
          )
        end

        client.get_sessions(updated_after: updated_after, after: '')
      end

      [
        [{ hasNextPage: nil, endCursor: nil }, 'a null hasNextPage'],
        [{ endCursor: 'b3BhcXVlLWN1cnNvcg' }, 'no hasNextPage key'],
        [nil, 'no pageInfo at all']
      ].each do |sparse_page_info, description|
        it "returns the page as given with #{description}, leaving pagination to the caller" do
          stub_portal(
            {
              success: true,
              data: { subscription: { gitlabCreditsUsage: { sessions: {
                nodes: session_nodes, pageInfo: sparse_page_info
              } } } }
            }
          )

          expect(Gitlab::ErrorTracking).not_to receive(:track_and_raise_exception)

          result = request

          expect(result[:success]).to be(true)
          expect(result[:sessions]).to eq(session_nodes)
          expect(result[:page_info]).to eq(sparse_page_info)
        end
      end

      it 'logs and reports when the connection is null without a GraphQL error' do
        stub_portal({ success: true, data: { subscription: { gitlabCreditsUsage: { sessions: nil } } } })

        expect(Gitlab::AppLogger).to receive(:warn).with(
          hash_including(Labkit::Fields::LOG_MESSAGE => "CustomersDot returned no sessions connection")
        )
        expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception).and_call_original

        expect { request }.to raise_error(described_class::ResponseError) do |error|
          expect(error.reason).to eq(:malformed_response)
        end
      end

      it 'raises no_cdot_subscription_found without reporting when the subscription is null' do
        stub_portal({ success: true, data: { subscription: nil } })

        expect(Gitlab::AppLogger).to receive(:warn).with(
          hash_including(Labkit::Fields::LOG_MESSAGE => "CustomersDot has no subscription for this namespace")
        )
        expect(Gitlab::ErrorTracking).not_to receive(:track_and_raise_exception)

        expect { request }.to raise_error(described_class::ResponseError) do |error|
          expect(error.reason).to eq(:no_cdot_subscription_found)
        end
      end

      it 'logs and reports when gitlabCreditsUsage is null without a GraphQL error' do
        stub_portal({ success: true, data: { subscription: { gitlabCreditsUsage: nil } } })

        expect(Gitlab::AppLogger).to receive(:warn).with(
          hash_including(Labkit::Fields::LOG_MESSAGE => "CustomersDot returned no sessions connection")
        )

        expect { request }.to raise_error(described_class::ResponseError) do |error|
          expect(error.reason).to eq(:malformed_response)
        end
      end

      # Classification reads error messages only, so response data cannot look like a failure.
      it 'does not misclassify a successful page whose data mentions a missing field' do
        poisoned = session_nodes.deep_dup
        poisoned.first[:modelsUsed] = ["Field 'sessions' doesn't exist on type 'GitlabCreditsUsage'"]

        stub_portal(
          {
            success: true,
            data: { subscription: { gitlabCreditsUsage: { sessions: {
              nodes: poisoned, pageInfo: page_info
            } } } }
          }
        )

        result = request

        expect(result[:success]).to be(true)
        expect(result[:sessions]).to eq(poisoned)
      end

      it 'passes the requested page size through unchanged' do
        expect(::Gitlab::HTTP).to receive(:post) do |_url, options|
          expect(Gitlab::Json::SafeParser.parse(options[:body]).dig('variables', 'first')).to eq(5_000)

          instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: portal_response
          )
        end

        client.get_sessions(updated_after: updated_after, first: 5_000)
      end

      it 'forwards the cursor when paging' do
        expect(::Gitlab::HTTP).to receive(:post) do |_url, options|
          expect(Gitlab::Json::SafeParser.parse(options[:body])['variables']).to include('after' => 'next-page')

          instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: portal_response
          )
        end

        client.get_sessions(updated_after: updated_after, after: 'next-page')
      end

      it 'omits the cursor on the first page' do
        expect(::Gitlab::HTTP).to receive(:post) do |_url, options|
          expect(Gitlab::Json::SafeParser.parse(options[:body])['variables'].keys).not_to include('after')

          instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: portal_response
          )
        end

        request
      end

      it 'does not memoize, so the caller can walk successive pages' do
        stub_portal(portal_response, times: 2)

        expect(client.get_sessions(updated_after: updated_after)).to eq(expected_response)
        expect(client.get_sessions(updated_after: updated_after)).to eq(expected_response)
      end

      it 'returns pageInfo so the caller knows whether to continue' do
        stub_portal(portal_response.deep_merge(
          data: { subscription: { gitlabCreditsUsage: { sessions: {
            pageInfo: { hasNextPage: true, endCursor: 'more' }
          } } } }
        ))

        expect(request[:page_info]).to eq({ hasNextPage: true, endCursor: 'more' })
      end

      # Every failure logs its reason and raises; the reason survives only in the log line.
      [
        [
          'the sessions field is not deployed',
          { errors: [{ message: "Field 'sessions' doesn't exist on type 'GitlabCreditsUsage'" }] },
          'undefined_field'
        ],
        [
          'only part of the selection set is missing',
          { errors: [{ message: "Field 'creditsByModel' doesn't exist on type 'Session'" }] },
          'undefined_field'
        ],
        [
          'the field is switched off',
          { errors: [{ message: 'sessions is temporarily disabled',
                       extensions: { code: 'FEATURE_DISABLED', field: 'GitlabCreditsUsage.sessions' } }] },
          'disabled'
        ],
        [
          'the kill switch is recognised by its code when the wording differs',
          { errors: [{ message: 'nope',
                       extensions: { code: 'FEATURE_DISABLED', field: 'GitlabCreditsUsage.sessions' } }] },
          'disabled'
        ],
        [
          'the disabled wording arrives without the kill switch code',
          { errors: [{ message: 'sessions is temporarily disabled' }] },
          'error'
        ],
        [
          'the query timed out on CustomersDot',
          { errors: [{ message: described_class::SESSIONS_UNAVAILABLE_MESSAGE }] },
          'unavailable'
        ],
        [
          # Only an HTTP 429 is waited out; a throttle phrased as a GraphQL error is a plain failure.
          'CustomersDot reports a rate limit inside a 200 response',
          { errors: [{ message: 'Rate limit exceeded', extensions: { code: 'RATE_LIMITED' } }] },
          'error'
        ]
      ].each do |description, body, expected_reason|
        context "when #{description}" do
          it "logs #{expected_reason} and raises with that reason" do
            stub_portal(body)

            expect(Gitlab::AppLogger).to receive(:warn).with(
              hash_including(
                Labkit::Fields::LOG_MESSAGE => "CustomersDot sessions query failed: #{expected_reason}"
              )
            )
            expect(Gitlab::ErrorTracking).to receive(:track_and_raise_exception).and_call_original

            expect { request }.to raise_error(described_class::ResponseError) do |error|
              expect(error.reason).to eq(expected_reason.to_sym)
            end
          end
        end
      end

      context 'when CustomersDot is shedding load' do
        def portal_status(status, headers = {})
          response = Net::HTTPResponse::CODE_TO_OBJ[status.to_s].new(1.0, status.to_s, 'nope')
          headers.each { |name, value| response[name] = value }
          allow(::Gitlab::HTTP).to receive(:post).and_return(instance_double(HTTParty::Response, response: response))
        end

        it 'logs server_error for a 5xx and raises with no retry_after' do
          portal_status(503)

          expect(Gitlab::AppLogger).to receive(:warn).with(
            hash_including(Labkit::Fields::LOG_MESSAGE => "CustomersDot sessions query failed: server_error")
          )

          expect { request }.to raise_error(described_class::ResponseError) do |error|
            expect(error.reason).to eq(:server_error)
            expect(error.retry_after).to be_nil
          end
        end

        it 'tells a 429 apart from a 5xx and carries Retry-After in seconds, without a Sentry report' do
          portal_status(429, 'Retry-After' => '7')

          expect(Gitlab::AppLogger).to receive(:warn).with(
            hash_including(Labkit::Fields::LOG_MESSAGE => "CustomersDot sessions query failed: rate_limited")
          )
          # The worker waits a 429 out and retries, so each attempt must not become an exception.
          expect(Gitlab::ErrorTracking).not_to receive(:track_and_raise_exception)
          expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

          expect { request }.to raise_error(described_class::ResponseError) do |error|
            expect(error.reason).to eq(:rate_limited)
            expect(error.retry_after).to eq(7)
          end
        end

        it 'reads Retry-After as a decimal integer' do
          portal_status(429, 'Retry-After' => '010')

          expect { request }.to raise_error(described_class::ResponseError) do |error|
            expect(error.retry_after).to eq(10)
          end
        end

        it 'reads an HTTP-date Retry-After as seconds from now', :freeze_time do
          portal_status(429, 'Retry-After' => 90.seconds.from_now.httpdate)

          expect { request }.to raise_error(described_class::ResponseError) do |error|
            expect(error.retry_after).to eq(90)
          end
        end

        it 'carries no retry_after when the header is missing, in the past or unreadable', :aggregate_failures do
          [{}, { 'Retry-After' => 1.minute.ago.httpdate }, { 'Retry-After' => 'soon' }, { 'Retry-After' => '0' }]
            .each do |headers|
            portal_status(429, headers)

            expect { request }.to raise_error(described_class::ResponseError) do |error|
              expect(error.reason).to eq(:rate_limited)
              expect(error.retry_after).to be_nil
            end
          end
        end
      end
    end
  end

  describe '#get_monthly_waiver' do
    let(:request) { client.get_monthly_waiver }
    let(:query) { described_class::GET_MONTHLY_WAIVER_QUERY }
    let(:monthly_waiver) do
      {
        creditsUsed: 12.25,
        totalCredits: 1000.91,
        dailyUsage: [{ date: '2025-10-01', creditsUsed: 12.25 }]
      }
    end

    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            gitlabCreditsUsage: {
              monthlyWaiver: monthly_waiver
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        monthlyWaiver: monthly_waiver
      }
    end

    include_context 'for self-managed request' do
      let(:variables) { { licenseKey: license_key, startDate: start_date, endDate: end_date } }
    end

    include_context 'for gitlab.com request' do
      let(:variables) { { namespaceId: namespace_id, startDate: start_date, endDate: end_date } }
    end
  end

  describe '#get_monthly_commitment' do
    let(:request) { client.get_monthly_commitment }
    let(:query) { described_class::GET_MONTHLY_COMMITMENT_QUERY }
    let(:monthly_commitment) do
      {
        totalCredits: 1000.91,
        creditsUsed: 250.32,
        dailyUsage: [{ date: '2025-10-01', creditsUsed: 250.32 }]
      }
    end

    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            gitlabCreditsUsage: {
              monthlyCommitment: monthly_commitment
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        monthlyCommitment: monthly_commitment
      }
    end

    include_context 'for self-managed request' do
      let(:variables) { { licenseKey: license_key, startDate: start_date, endDate: end_date } }
    end

    include_context 'for gitlab.com request' do
      let(:variables) { { namespaceId: namespace_id, startDate: start_date, endDate: end_date } }
    end
  end

  describe '#get_overage' do
    let(:request) { client.get_overage }
    let(:query) { described_class::GET_OVERAGE_QUERY }
    let(:overage) do
      {
        isAllowed: true,
        creditsUsed: 250.32,
        dailyUsage: [{ date: '2025-10-01', creditsUsed: 250.32 }]
      }
    end

    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            gitlabCreditsUsage: {
              overage: overage
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        overage: overage
      }
    end

    include_context 'for self-managed request' do
      let(:variables) { { licenseKey: license_key, startDate: start_date, endDate: end_date } }
    end

    include_context 'for gitlab.com request' do
      let(:variables) { { namespaceId: namespace_id, startDate: start_date, endDate: end_date } }
    end
  end

  describe '#get_paid_tier_trial' do
    let(:request) { client.get_paid_tier_trial }
    let(:query) { described_class::GET_PAID_TIER_TRIAL_QUERY }
    let(:paid_tier_trial) do
      {
        isActive: true,
        dailyUsage: [
          { date: '2025-10-01', creditsUsed: 10.5 },
          { date: '2025-10-02', creditsUsed: 15.25 }
        ]
      }
    end

    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            gitlabCreditsUsage: {
              paidTierTrial: paid_tier_trial
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        paidTierTrial: paid_tier_trial
      }
    end

    include_context 'for self-managed request' do
      let(:variables) { { licenseKey: license_key, startDate: start_date, endDate: end_date } }
    end

    include_context 'for gitlab.com request' do
      let(:variables) { { namespaceId: namespace_id, startDate: start_date, endDate: end_date } }
    end
  end

  describe '#get_products' do
    let(:request) { client.get_products }
    let(:query) { described_class::GET_PRODUCTS_QUERY }
    let(:products) do
      [
        {
          id: 'duo_agent_platform',
          title: 'Duo Agent Platform',
          creditsUsed: 150.5,
          flowTypes: [
            { id: 'code_suggestions', title: 'Code Suggestions' },
            { id: 'fix_pipeline', title: 'Fix Pipeline Flow' }
          ]
        },
        {
          id: 'other_product',
          title: 'Other Product',
          creditsUsed: 75.25,
          flowTypes: [
            { id: 'other_flow_type', title: 'Other Flow Type' }
          ]
        }
      ]
    end

    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            gitlabCreditsUsage: {
              products: products
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        products: products
      }
    end

    include_context 'for self-managed request' do
      let(:variables) { { licenseKey: license_key, startDate: start_date, endDate: end_date } }
    end

    include_context 'for gitlab.com request' do
      let(:variables) { { namespaceId: namespace_id, startDate: start_date, endDate: end_date } }
    end
  end

  describe '#get_events_for_user_id' do
    let(:user_id) { 123 }
    let(:request_options) { { read_timeout: described_class::CLICKHOUSE_QUERY_READ_TIMEOUT } }
    let(:args) { { first: 20, last: nil, before: nil, after: nil, flow_types: nil } }
    let(:request) { client.get_events_for_user_id(user_id, args) }
    let(:query) { described_class::GET_USER_EVENTS_QUERY }
    let(:user_events) do
      [
        {
          timestamp: "2025-10-01T16:25:28Z",
          eventType: "ai_token_usage",
          flowType: "Software Development Flow",
          projectId: nil,
          namespaceId: nil,
          creditsUsed: 100.78
        },
        {
          timestamp: "2025-10-01T16:30:12Z",
          eventType: "workflow_execution",
          flowType: "Agentic Chat",
          projectId: "19",
          namespaceId: "99",
          creditsUsed: 200.56
        }
      ]
    end

    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            gitlabCreditsUsage: {
              usersUsage: {
                users: [{
                  events: {
                    nodes: user_events,
                    pageInfo: {
                      hasNextPage: false,
                      hasPreviousPage: false,
                      startCursor: "2025-10-01T16:25:28Z",
                      endCursor: "2025-10-01T16:30:12Z"
                    }
                  }
                }]
              }
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        userEvents: {
          nodes: user_events,
          pageInfo: {
            hasNextPage: false,
            hasPreviousPage: false,
            startCursor: "2025-10-01T16:25:28Z",
            endCursor: "2025-10-01T16:30:12Z"
          }
        }
      }
    end

    include_context 'for self-managed request' do
      let(:variables) do
        { licenseKey: license_key, startDate: start_date, endDate: end_date, userIds: [user_id], first: 20 }
      end
    end

    include_context 'for gitlab.com request' do
      let(:variables) do
        { namespaceId: namespace_id, startDate: start_date, endDate: end_date, userIds: [user_id], first: 20 }
      end
    end

    context 'when flow_types are provided' do
      let(:args) { { first: 20, last: nil, before: nil, after: nil, flow_types: %w[code_suggestions agentic_chat] } }

      include_context 'for self-managed request' do
        let(:variables) do
          { licenseKey: license_key, startDate: start_date, endDate: end_date,
            userIds: [user_id], flowTypes: %w[code_suggestions agentic_chat], first: 20 }
        end
      end

      include_context 'for gitlab.com request' do
        let(:variables) do
          { namespaceId: namespace_id, startDate: start_date, endDate: end_date,
            userIds: [user_id], flowTypes: %w[code_suggestions agentic_chat], first: 20 }
        end
      end
    end

    context 'when include_non_billable is requested' do
      let(:args) { { first: 20, last: nil, before: nil, after: nil, flow_types: nil, include_non_billable: true } }
      let(:query) { described_class::GET_USER_EVENTS_WITH_NON_BILLABLE_QUERY }
      let(:user_events) do
        [
          { timestamp: "2025-10-01T16:25:28Z", flowType: "Orbit - MCP", projectId: nil, namespaceId: "99",
            creditsUsed: 0.03, billable: false, skipReason: 'promo' },
          { timestamp: "2025-10-01T16:30:12Z", flowType: "Agentic Chat", projectId: "19", namespaceId: nil,
            creditsUsed: 200.56, billable: true, skipReason: nil }
        ]
      end

      include_context 'for self-managed request' do
        let(:variables) do
          { licenseKey: license_key, startDate: start_date, endDate: end_date, userIds: [user_id], first: 20 }
        end
      end

      include_context 'for gitlab.com request' do
        let(:variables) do
          { namespaceId: namespace_id, startDate: start_date, endDate: end_date, userIds: [user_id], first: 20 }
        end
      end

      it 'opts into non-billable events and leaves out the deprecated eventType to stay under the complexity cap' do
        expect(query).to include('includeNonBillable: true', 'billable', 'skipReason')
        expect(query).not_to include('eventType')
      end

      context 'when CustomerDot does not support includeNonBillable' do
        let(:namespace_id) { 1234 }
        let(:license_key) { nil }
        let(:variables) do
          { namespaceId: namespace_id, startDate: start_date, endDate: end_date, userIds: [user_id], first: 20 }
        end

        let(:fallback_params) { params.merge(query: described_class::GET_USER_EVENTS_QUERY) }
        let(:undefined_argument_response) do
          { errors: [{ message: "Field 'events' doesn't accept argument 'includeNonBillable'" }] }
        end

        it 'retries with the billable-only query' do
          expect(::Gitlab::HTTP).to receive(:post).with(
            graphql_url,
            headers: headers,
            body: params.to_json,
            **request_options
          ).and_return(instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: undefined_argument_response
          ))

          expect(::Gitlab::HTTP).to receive(:post).with(
            graphql_url,
            headers: headers,
            body: fallback_params.to_json,
            **request_options
          ).and_return(instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: portal_response
          ))

          expect(request).to eq(expected_response)
        end
      end
    end
  end

  describe '#get_used_flow_types_for_user_id' do
    let(:user_id) { 123 }
    let(:request_options) { { read_timeout: described_class::CLICKHOUSE_QUERY_READ_TIMEOUT } }
    let(:request) { client.get_used_flow_types_for_user_id(user_id) }
    let(:query) { described_class::GET_USED_FLOW_TYPES_QUERY }
    let(:used_flow_types) do
      [
        { id: 'code_suggestions', title: 'Code Suggestions' },
        { id: 'agentic_chat', title: 'Agentic Chat' }
      ]
    end

    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            gitlabCreditsUsage: {
              usersUsage: {
                users: [{
                  usedFlowTypes: used_flow_types
                }]
              }
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        usedFlowTypes: used_flow_types
      }
    end

    include_context 'for self-managed request' do
      let(:variables) { { licenseKey: license_key, startDate: start_date, endDate: end_date, userIds: [user_id] } }
    end

    include_context 'for gitlab.com request' do
      let(:variables) { { namespaceId: namespace_id, startDate: start_date, endDate: end_date, userIds: [user_id] } }
    end

    context 'when include_non_billable is requested' do
      let(:request) { client.get_used_flow_types_for_user_id(user_id, include_non_billable: true) }
      let(:query) { described_class::GET_USED_FLOW_TYPES_WITH_NON_BILLABLE_QUERY }

      include_context 'for gitlab.com request' do
        let(:variables) do
          { namespaceId: namespace_id, startDate: start_date, endDate: end_date, userIds: [user_id] }
        end
      end

      it 'opts into non-billable flow types' do
        expect(query).to include('usedFlowTypes(includeNonBillable: true)')
      end

      context 'when CustomerDot does not support includeNonBillable' do
        let(:namespace_id) { 1234 }
        let(:license_key) { nil }
        let(:variables) do
          { namespaceId: namespace_id, startDate: start_date, endDate: end_date, userIds: [user_id] }
        end

        let(:fallback_params) { params.merge(query: described_class::GET_USED_FLOW_TYPES_QUERY) }
        let(:undefined_argument_response) do
          { errors: [{ message: "Field 'usedFlowTypes' doesn't accept argument 'includeNonBillable'" }] }
        end

        it 'retries with the billable-only query' do
          expect(::Gitlab::HTTP).to receive(:post).with(
            graphql_url,
            headers: headers,
            body: params.to_json,
            **request_options
          ).and_return(instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: undefined_argument_response
          ))

          expect(::Gitlab::HTTP).to receive(:post).with(
            graphql_url,
            headers: headers,
            body: fallback_params.to_json,
            **request_options
          ).and_return(instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: portal_response
          ))

          expect(request).to eq(expected_response)
        end
      end
    end

    context 'when no users are returned' do
      let(:portal_response) do
        {
          success: true,
          data: {
            subscription: {
              gitlabCreditsUsage: {
                usersUsage: {
                  users: []
                }
              }
            }
          }
        }
      end

      let(:expected_response) do
        {
          success: true,
          usedFlowTypes: nil
        }
      end

      include_context 'for self-managed request' do
        let(:variables) do
          { licenseKey: license_key, startDate: start_date, endDate: end_date, userIds: [user_id] }
        end
      end

      include_context 'for gitlab.com request' do
        let(:variables) do
          { namespaceId: namespace_id, startDate: start_date, endDate: end_date, userIds: [user_id] }
        end
      end
    end
  end

  describe '#get_daily_usage_for_user_id' do
    let(:user_id) { 123 }
    let(:request) { client.get_daily_usage_for_user_id(user_id) }
    let(:query) { described_class::GET_USER_DAILY_USAGE_QUERY }
    let(:daily_usage) do
      [
        { date: '2025-10-01', creditsUsed: 12.5 },
        { date: '2025-10-02', creditsUsed: 3.0 }
      ]
    end

    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            gitlabCreditsUsage: {
              usersUsage: {
                users: [{ dailyUsage: daily_usage }]
              }
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        dailyUsage: daily_usage
      }
    end

    include_context 'for self-managed request' do
      let(:variables) { { licenseKey: license_key, startDate: start_date, endDate: end_date, userIds: [user_id] } }
    end

    include_context 'for gitlab.com request' do
      let(:variables) { { namespaceId: namespace_id, startDate: start_date, endDate: end_date, userIds: [user_id] } }
    end

    context 'when flow_types are provided' do
      let(:request) { client.get_daily_usage_for_user_id(user_id, flow_types: %w[chat]) }

      include_context 'for self-managed request' do
        let(:variables) do
          { licenseKey: license_key, startDate: start_date, endDate: end_date,
            userIds: [user_id], flowTypes: %w[chat] }
        end
      end

      include_context 'for gitlab.com request' do
        let(:variables) do
          { namespaceId: namespace_id, startDate: start_date, endDate: end_date,
            userIds: [user_id], flowTypes: %w[chat] }
        end
      end
    end

    context 'when no users are returned' do
      let(:portal_response) do
        {
          success: true,
          data: {
            subscription: {
              gitlabCreditsUsage: {
                usersUsage: { users: [] }
              }
            }
          }
        }
      end

      let(:expected_response) do
        {
          success: true,
          dailyUsage: nil
        }
      end

      include_context 'for self-managed request' do
        let(:variables) do
          { licenseKey: license_key, startDate: start_date, endDate: end_date, userIds: [user_id] }
        end
      end

      include_context 'for gitlab.com request' do
        let(:variables) do
          { namespaceId: namespace_id, startDate: start_date, endDate: end_date, userIds: [user_id] }
        end
      end
    end

    context 'when called more than once with the same arguments' do
      let(:namespace_id) { 1234 }
      let(:license_key) { nil }

      it 'memoizes the result and performs a single request' do
        expect(::Gitlab::HTTP).to receive(:post).once.and_return(instance_double(
          HTTParty::Response,
          response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
          parsed_response: portal_response
        ))

        expect(client.get_daily_usage_for_user_id(user_id)).to eq(expected_response)
        expect(client.get_daily_usage_for_user_id(user_id)).to eq(expected_response)
      end
    end
  end

  describe '#get_non_billable_usage_for_user_id' do
    let(:user_id) { 123 }
    let(:request_options) { { read_timeout: described_class::CLICKHOUSE_QUERY_READ_TIMEOUT } }
    let(:request) { client.get_non_billable_usage_for_user_id(user_id) }
    let(:query) { described_class::GET_USER_NON_BILLABLE_USAGE_QUERY }
    let(:non_billable_usage) do
      [
        {
          productId: 'orbit',
          skipReason: 'promo',
          totalCreditsUsed: 30.0,
          dailyUsage: [{ date: '2025-10-01', creditsUsed: 10.0 }, { date: '2025-10-02', creditsUsed: 20.0 }]
        }
      ]
    end

    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            gitlabCreditsUsage: {
              usersUsage: {
                users: [{ nonBillableUsage: non_billable_usage }]
              }
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        nonBillableUsage: non_billable_usage
      }
    end

    include_context 'for self-managed request' do
      let(:variables) { { licenseKey: license_key, startDate: start_date, endDate: end_date, userIds: [user_id] } }
    end

    include_context 'for gitlab.com request' do
      let(:variables) { { namespaceId: namespace_id, startDate: start_date, endDate: end_date, userIds: [user_id] } }
    end

    context 'when flow_types are provided' do
      let(:request) { client.get_non_billable_usage_for_user_id(user_id, flow_types: %w[orbit_mcp]) }

      include_context 'for gitlab.com request' do
        let(:variables) do
          { namespaceId: namespace_id, startDate: start_date, endDate: end_date,
            userIds: [user_id], flowTypes: %w[orbit_mcp] }
        end
      end
    end

    context 'when no users are returned' do
      let(:portal_response) do
        {
          success: true,
          data: {
            subscription: {
              gitlabCreditsUsage: {
                usersUsage: { users: [] }
              }
            }
          }
        }
      end

      let(:expected_response) do
        {
          success: true,
          nonBillableUsage: nil
        }
      end

      include_context 'for gitlab.com request' do
        let(:variables) do
          { namespaceId: namespace_id, startDate: start_date, endDate: end_date, userIds: [user_id] }
        end
      end
    end

    context 'when CustomersDot could not read nonBillableUsage' do
      let(:namespace_id) { 1234 }
      let(:license_key) { nil }
      let(:portal_response) do
        {
          data: { subscription: { gitlabCreditsUsage: { usersUsage: { users: [{ nonBillableUsage: nil }] } } } },
          errors: [
            {
              message: 'nonBillableUsage is temporarily unavailable',
              path: %w[subscription gitlabCreditsUsage usersUsage users 0 nonBillableUsage],
              extensions: { code: 'NON_BILLABLE_USAGE_UNAVAILABLE' }
            }
          ]
        }
      end

      it 'warns and returns unsuccessfully instead of raising' do
        allow(::Gitlab::HTTP).to receive(:post).and_return(instance_double(
          HTTParty::Response,
          response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
          parsed_response: portal_response
        ))

        expect(Gitlab::ErrorTracking).not_to receive(:track_and_raise_exception)
        expect(Gitlab::AppLogger).to receive(:warn).with(
          hash_including(Labkit::Fields::LOG_MESSAGE => 'CustomersDot could not read nonBillableUsage for user')
        )

        expect(request).to eq({ success: false, nonBillableUsage: nil })
      end
    end

    context 'when called more than once with the same arguments' do
      let(:namespace_id) { 1234 }
      let(:license_key) { nil }

      it 'memoizes the result and performs a single request' do
        expect(::Gitlab::HTTP).to receive(:post).once.and_return(instance_double(
          HTTParty::Response,
          response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
          parsed_response: portal_response
        ))

        expect(client.get_non_billable_usage_for_user_id(user_id)).to eq(expected_response)
        expect(client.get_non_billable_usage_for_user_id(user_id)).to eq(expected_response)
      end
    end
  end

  describe '#get_blocked_statuses' do
    let(:entity_ids) { %w[123 321] }
    let(:request) { client.get_blocked_statuses(entity_ids) }
    let(:query) { described_class::GET_BLOCKED_STATUSES_QUERY }
    let(:blocked_statuses) do
      [
        {
          entityId: '123',
          blocked: true,
          capType: 'FLAT_USER_CAP'
        },
        {
          entityId: '321',
          blocked: false,
          capType: nil
        }
      ]
    end

    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            gitlabCreditsUsage: {
              blockedStatuses: { nodes: blocked_statuses }
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        blockedStatuses: blocked_statuses
      }
    end

    include_context 'for self-managed request' do
      let(:variables) { { licenseKey: license_key, startDate: start_date, endDate: end_date, entityIds: entity_ids } }
    end

    include_context 'for gitlab.com request' do
      let(:variables) { { namespaceId: namespace_id, startDate: start_date, endDate: end_date, entityIds: entity_ids } }
    end
  end

  describe '#get_usage_for_user_ids' do
    let(:user_ids) { [123, 321] }
    let(:request) { client.get_usage_for_user_ids(user_ids) }
    let(:query) { described_class::GET_USERS_USAGE_QUERY }
    let(:users_usage) do
      [
        {
          userId: 123,
          totalCredits: 100.12,
          creditsUsed: 500.23,
          monthlyCommitmentCreditsUsed: 400.45,
          monthlyWaiverCreditsUsed: 25.56,
          overageCreditsUsed: 50.67,
          paidTierTrialCreditsUsed: 10.0,
          totalCreditsUsed: 986.91,
          nonBillableCreditsUsed: 1.314
        },
        {
          userId: 321,
          totalCredits: 100.12,
          creditsUsed: 50.23,
          monthlyCommitmentCreditsUsed: 0,
          monthlyWaiverCreditsUsed: 12.34,
          overageCreditsUsed: 0,
          paidTierTrialCreditsUsed: 0,
          totalCreditsUsed: 62.57,
          nonBillableCreditsUsed: 0.0
        }
      ]
    end

    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            gitlabCreditsUsage: {
              usersUsage: { users: users_usage }
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        usersUsage: users_usage
      }
    end

    include_context 'for self-managed request' do
      let(:variables) do
        { licenseKey: license_key, startDate: start_date, endDate: end_date, userIds: user_ids, flowTypes: nil }
      end
    end

    include_context 'for gitlab.com request' do
      let(:variables) do
        { namespaceId: namespace_id, startDate: start_date, endDate: end_date, userIds: user_ids, flowTypes: nil }
      end
    end

    context 'when flow_types are provided' do
      let(:request) { client.get_usage_for_user_ids(user_ids, flow_types: %w[chat]) }

      include_context 'for self-managed request' do
        let(:variables) do
          {
            licenseKey: license_key,
            startDate: start_date,
            endDate: end_date,
            userIds: user_ids,
            flowTypes: %w[chat]
          }
        end
      end

      include_context 'for gitlab.com request' do
        let(:variables) do
          {
            namespaceId: namespace_id,
            startDate: start_date,
            endDate: end_date,
            userIds: user_ids,
            flowTypes: %w[chat]
          }
        end
      end
    end

    it 'requests the non-billable credits from CustomerDot' do
      expect(query).to include('nonBillableCreditsUsed')
    end

    context 'when CustomerDot does not support nonBillableCreditsUsed' do
      let(:namespace_id) { 1234 }
      let(:license_key) { nil }
      let(:variables) do
        { namespaceId: namespace_id, startDate: start_date, endDate: end_date, userIds: user_ids, flowTypes: nil }
      end

      let(:fallback_params) { params.merge(query: described_class::GET_USERS_USAGE_WITHOUT_NON_BILLABLE_CREDITS_QUERY) }
      let(:undefined_field_response) do
        {
          errors: [{ message: "Field 'nonBillableCreditsUsed' doesn't exist on type 'GitlabCreditsUser'" }]
        }
      end

      it 'retries without nonBillableCreditsUsed' do
        expect(::Gitlab::HTTP).to receive(:post).with(
          graphql_url,
          headers: headers,
          body: params.to_json
        ).and_return(instance_double(
          HTTParty::Response,
          response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
          parsed_response: undefined_field_response
        ))

        expect(::Gitlab::HTTP).to receive(:post).with(
          graphql_url,
          headers: headers,
          body: fallback_params.to_json
        ).and_return(instance_double(
          HTTParty::Response,
          response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
          parsed_response: portal_response
        ))

        expect(request).to eq(expected_response)
        expect(described_class::GET_USERS_USAGE_WITHOUT_NON_BILLABLE_CREDITS_QUERY)
          .not_to include('nonBillableCreditsUsed')
      end
    end
  end

  describe '#get_consumers' do
    let(:args) { { sort: :total_credits_used_desc, first: 10, last: nil, before: nil, after: nil } }
    let(:request) { client.get_consumers(args) }
    let(:query) { described_class::GET_CONSUMERS_QUERY }
    let(:consumers) do
      {
        nodes: [
          {
            userId: 123,
            totalCredits: 100.12,
            creditsUsed: 500.23,
            monthlyCommitmentCreditsUsed: 400.45,
            monthlyWaiverCreditsUsed: 25.56,
            overageCreditsUsed: 50.67,
            paidTierTrialCreditsUsed: 10.0,
            totalCreditsUsed: 986.91,
            entityType: 'USER'
          },
          {
            userId: 321,
            totalCredits: 100.12,
            creditsUsed: 50.23,
            monthlyCommitmentCreditsUsed: 0,
            monthlyWaiverCreditsUsed: 12.34,
            overageCreditsUsed: 0,
            paidTierTrialCreditsUsed: 0,
            totalCreditsUsed: 62.57,
            entityType: 'NON_HUMAN'
          }
        ],
        pageInfo: {
          hasNextPage: false,
          hasPreviousPage: false,
          startCursor: "cursor1",
          endCursor: "cursor2"
        }
      }
    end

    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            gitlabCreditsUsage: {
              usersUsage: { consumers: consumers }
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        consumers: consumers
      }
    end

    include_context 'for self-managed request' do
      let(:variables) do
        { licenseKey: license_key, startDate: start_date, endDate: end_date,
          sort: 'TOTAL_CREDITS_USED_DESC', first: 10, last: nil, before: nil, after: nil, flowTypes: nil }
      end
    end

    include_context 'for gitlab.com request' do
      let(:variables) do
        { namespaceId: namespace_id, startDate: start_date, endDate: end_date,
          sort: 'TOTAL_CREDITS_USED_DESC', first: 10, last: nil, before: nil, after: nil, flowTypes: nil }
      end
    end

    context 'when flow_types are provided' do
      let(:args) do
        { sort: :total_credits_used_desc, first: 10, last: nil, before: nil, after: nil, flow_types: %w[chat] }
      end

      include_context 'for self-managed request' do
        let(:variables) do
          { licenseKey: license_key, startDate: start_date, endDate: end_date,
            sort: 'TOTAL_CREDITS_USED_DESC', first: 10, last: nil, before: nil, after: nil, flowTypes: %w[chat] }
        end
      end

      include_context 'for gitlab.com request' do
        let(:variables) do
          { namespaceId: namespace_id, startDate: start_date, endDate: end_date,
            sort: 'TOTAL_CREDITS_USED_DESC', first: 10, last: nil, before: nil, after: nil, flowTypes: %w[chat] }
        end
      end
    end

    it 'requests entity type from CustomerDot' do
      expect(query).to include('entityType')
    end

    context 'when CustomerDot does not support entityType' do
      let(:fallback_query) { described_class::GET_CONSUMERS_WITHOUT_ENTITY_TYPE_QUERY }
      let(:fallback_params) { params.merge(query: fallback_query) }
      let(:undefined_field_response) do
        {
          errors: [{ message: "Field 'entityType' doesn't exist on type 'GitlabCreditsConsumer'" }]
        }
      end

      it 'retries without entityType' do
        expect(::Gitlab::HTTP).to receive(:post).with(
          graphql_url,
          headers: headers,
          body: params.to_json
        ).and_return(instance_double(
          HTTParty::Response,
          response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
          parsed_response: undefined_field_response
        ))

        expect(::Gitlab::HTTP).to receive(:post).with(
          graphql_url,
          headers: headers,
          body: fallback_params.to_json
        ).and_return(instance_double(
          HTTParty::Response,
          response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
          parsed_response: portal_response
        ))

        expect(request).to eq(expected_response)
      end
    end

    it 'requests the non-billable credits from CustomerDot' do
      expect(query).to include('nonBillableCreditsUsed')
    end

    context 'when CustomerDot does not support nonBillableCreditsUsed' do
      let(:fallback_query) { query.gsub(/^\s+nonBillableCreditsUsed\n/, '') }
      let(:fallback_params) { params.merge(query: fallback_query) }
      let(:undefined_field_response) do
        {
          errors: [{ message: "Field 'nonBillableCreditsUsed' doesn't exist on type 'GitlabCreditsConsumer'" }]
        }
      end

      it 'retries without nonBillableCreditsUsed and keeps entityType' do
        expect(::Gitlab::HTTP).to receive(:post).with(
          graphql_url,
          headers: headers,
          body: params.to_json
        ).and_return(instance_double(
          HTTParty::Response,
          response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
          parsed_response: undefined_field_response
        ))

        expect(::Gitlab::HTTP).to receive(:post).with(
          graphql_url,
          headers: headers,
          body: fallback_params.to_json
        ).and_return(instance_double(
          HTTParty::Response,
          response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
          parsed_response: portal_response
        ))

        expect(request).to eq(expected_response)
        expect(fallback_query).to include('entityType')
        expect(fallback_query).not_to include('nonBillableCreditsUsed')
      end
    end

    context 'when sort is nil' do
      let(:args) { { sort: nil, first: 10, last: nil, before: nil, after: nil } }

      include_context 'for self-managed request' do
        let(:variables) do
          { licenseKey: license_key, startDate: start_date, endDate: end_date,
            sort: nil, first: 10, last: nil, before: nil, after: nil, flowTypes: nil }
        end
      end
    end
  end

  describe '#get_users_usage_stats' do
    let(:request) { client.get_users_usage_stats }
    let(:query) { described_class::GET_USERS_USAGE_STATS_QUERY }
    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            gitlabCreditsUsage: {
              usersUsage: {
                totalActiveUsers: 5,
                totalUsersUsingCredits: 9.87,
                totalUsersUsingMonthlyCommitment: 8.76,
                totalUsersUsingOverage: 6.54,
                creditsUsed: 123.45,
                dailyUsage: [{ date: '2025-10-01', creditsUsed: 123.45 }]
              }
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        usersUsage: portal_response[:data][:subscription][:gitlabCreditsUsage][:usersUsage]
      }
    end

    include_context 'for self-managed request' do
      let(:variables) { { licenseKey: license_key, startDate: start_date, endDate: end_date } }
    end

    include_context 'for gitlab.com request' do
      let(:variables) { { namespaceId: namespace_id, startDate: start_date, endDate: end_date } }
    end

    context 'when flow_types are provided' do
      let(:request) { client.get_users_usage_stats(flow_types: %w[chat]) }

      include_context 'for self-managed request' do
        let(:variables) do
          {
            licenseKey: license_key,
            startDate: start_date,
            endDate: end_date,
            flowTypes: %w[chat]
          }
        end
      end

      include_context 'for gitlab.com request' do
        let(:variables) do
          {
            namespaceId: namespace_id,
            startDate: start_date,
            endDate: end_date,
            flowTypes: %w[chat]
          }
        end
      end
    end
  end

  describe '#get_trial_usage' do
    let(:request) { client.get_trial_usage }
    let(:query) { described_class::GET_TRIAL_USAGE_QUERY }
    let(:trial_usage) do
      {
        activeTrial: {
          startDate: "2026-02-01",
          endDate: "2026-03-03"
        },
        usersUsage: {
          creditsUsed: 12.5,
          totalUsersUsingCredits: 3,
          users: []
        }
      }
    end

    let(:portal_response) do
      {
        success: true,
        data: {
          trialUsage: trial_usage
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        trialUsage: trial_usage
      }
    end

    include_context 'for self-managed request' do
      let(:variables) { { licenseKey: license_key, startDate: start_date, endDate: end_date } }
    end

    include_context 'for gitlab.com request' do
      let(:variables) { { namespaceId: namespace_id, startDate: start_date, endDate: end_date } }
    end

    context 'when trial has zero usage' do
      let(:trial_usage) do
        {
          activeTrial: {
            startDate: "2026-01-06",
            endDate: "2026-04-06"
          },
          usersUsage: {
            creditsUsed: 0.0,
            totalUsersUsingCredits: 0,
            users: []
          }
        }
      end

      let(:portal_response) do
        {
          success: true,
          data: {
            trialUsage: trial_usage
          }
        }
      end

      let(:expected_response) do
        {
          success: true,
          trialUsage: trial_usage
        }
      end

      include_context 'for self-managed request' do
        let(:variables) { { licenseKey: license_key, startDate: start_date, endDate: end_date } }
      end

      include_context 'for gitlab.com request' do
        let(:variables) { { namespaceId: namespace_id, startDate: start_date, endDate: end_date } }
      end
    end
  end

  describe '#get_trial_usage_for_user_ids' do
    let(:user_ids) { [123, 456] }
    let(:request) { client.get_trial_usage_for_user_ids(user_ids) }
    let(:query) { described_class::GET_TRIAL_USAGE_FOR_USER_IDS_QUERY }
    let(:trial_users_usage) do
      [
        {
          userId: 123,
          totalCredits: 24.0,
          creditsUsed: 4.5
        },
        {
          userId: 456,
          totalCredits: 24.0,
          creditsUsed: nil
        }
      ]
    end

    let(:portal_response) do
      {
        success: true,
        data: {
          trialUsage: {
            activeTrial: {
              startDate: "2026-01-06",
              endDate: "2026-04-06"
            },
            usersUsage: {
              creditsUsed: 4.5,
              totalUsersUsingCredits: 1,
              users: trial_users_usage
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        usersUsage: trial_users_usage
      }
    end

    include_context 'for self-managed request' do
      let(:variables) { { licenseKey: license_key, startDate: start_date, endDate: end_date, userIds: user_ids } }
    end

    include_context 'for gitlab.com request' do
      let(:variables) { { namespaceId: namespace_id, startDate: start_date, endDate: end_date, userIds: user_ids } }
    end

    context 'when all users have null creditsUsed' do
      let(:user_ids) { [123, 456, 789] }
      let(:trial_users_usage) do
        [
          {
            userId: 123,
            totalCredits: 24.0,
            creditsUsed: nil
          },
          {
            userId: 456,
            totalCredits: 24.0,
            creditsUsed: nil
          },
          {
            userId: 789,
            totalCredits: 24.0,
            creditsUsed: nil
          }
        ]
      end

      let(:portal_response) do
        {
          success: true,
          data: {
            trialUsage: {
              activeTrial: {
                startDate: "2026-01-06",
                endDate: "2026-04-06"
              },
              usersUsage: {
                creditsUsed: 0.0,
                totalUsersUsingCredits: 0,
                users: trial_users_usage
              }
            }
          }
        }
      end

      let(:expected_response) do
        {
          success: true,
          usersUsage: trial_users_usage
        }
      end

      include_context 'for self-managed request' do
        let(:variables) do
          { licenseKey: license_key, startDate: start_date, endDate: end_date, userIds: user_ids }
        end
      end

      include_context 'for gitlab.com request' do
        let(:variables) do
          { namespaceId: namespace_id, startDate: start_date, endDate: end_date, userIds: user_ids }
        end
      end
    end
  end

  describe '#get_budget_caps' do
    let(:request) { client.get_budget_caps }
    let(:query) { described_class::GET_BUDGET_CAPS_QUERY }
    let(:portal_response) do
      {
        success: true,
        data: {
          subscription: {
            budgetControls: {
              subscription: {
                subscriptionName: "A-S00012345",
                subscriptionCap: 500.0,
                subscriptionCapEnabled: true,
                flatUserCap: 100.0,
                flatUserCapEnabled: true
              },
              userBudgetCapOverrides: {
                nodes: [
                  {
                    entityId: "1",
                    cap: 50.0,
                    capEnabled: true,
                    selfManagedInstanceActivationId: nil,
                    createdAt: "2026-04-01T00:00:00Z",
                    updatedAt: "2026-04-01T00:00:00Z"
                  }
                ],
                pageInfo: {
                  hasNextPage: false,
                  hasPreviousPage: false,
                  startCursor: nil,
                  endCursor: nil
                }
              }
            }
          }
        }
      }
    end

    let(:expected_response) do
      {
        success: true,
        budgetControls: portal_response.dig(
          :data, :subscription, :budgetControls
        )
      }
    end

    include_context 'for self-managed request' do
      let(:variables) { { licenseKey: license_key } }
    end

    include_context 'for gitlab.com request' do
      let(:variables) { { namespaceId: namespace_id } }
    end

    context 'with entity_ids filter' do
      let(:request) { client.get_budget_caps(entity_ids: %w[1 2]) }

      context 'for gitlab.com request' do
        let(:namespace_id) { 1234 }
        let(:license_key) { nil }
        let(:admin_headers) do
          {
            "X-Admin-Email" => "gl_com_api@gitlab.com",
            "X-Admin-Token" => "customer_admin_token"
          }
        end

        it 'passes entity_ids with namespaceId' do
          expect(::Gitlab::HTTP).to receive(:post).with(
            graphql_url,
            headers: headers,
            body: {
              query: query,
              variables: {
                instanceId: Gitlab::GlobalAnonymousId.instance_id,
                namespaceId: namespace_id,
                entityIds: %w[1 2]
              }
            }.to_json
          ).and_return(instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: portal_response
          ))

          expect(request).to eq(expected_response)
        end
      end

      context 'for self-managed request' do
        let(:admin_headers) { nil }
        let(:namespace_id) { nil }
        let(:license_key) { 'license_key' }

        it 'passes entity_ids with licenseKey' do
          expect(::Gitlab::HTTP).to receive(:post).with(
            graphql_url,
            headers: headers,
            body: {
              query: query,
              variables: {
                instanceId: Gitlab::GlobalAnonymousId.instance_id,
                licenseKey: license_key,
                entityIds: %w[1 2]
              }
            }.to_json
          ).and_return(instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: portal_response
          ))

          expect(request).to eq(expected_response)
        end
      end
    end

    context 'with pagination args' do
      let(:request) do
        client.get_budget_caps(args: { first: 10, after: "cursor123" })
      end

      context 'for gitlab.com request' do
        let(:namespace_id) { 1234 }
        let(:license_key) { nil }
        let(:admin_headers) do
          {
            "X-Admin-Email" => "gl_com_api@gitlab.com",
            "X-Admin-Token" => "customer_admin_token"
          }
        end

        it 'passes pagination variables with namespaceId' do
          expect(::Gitlab::HTTP).to receive(:post).with(
            graphql_url,
            headers: headers,
            body: {
              query: query,
              variables: {
                instanceId: Gitlab::GlobalAnonymousId.instance_id,
                namespaceId: namespace_id,
                first: 10,
                after: "cursor123"
              }
            }.to_json
          ).and_return(instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: portal_response
          ))

          expect(request).to eq(expected_response)
        end
      end

      context 'for self-managed request' do
        let(:admin_headers) { nil }
        let(:namespace_id) { nil }
        let(:license_key) { 'license_key' }

        it 'passes pagination variables with licenseKey' do
          expect(::Gitlab::HTTP).to receive(:post).with(
            graphql_url,
            headers: headers,
            body: {
              query: query,
              variables: {
                instanceId: Gitlab::GlobalAnonymousId.instance_id,
                licenseKey: license_key,
                first: 10,
                after: "cursor123"
              }
            }.to_json
          ).and_return(instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: portal_response
          ))

          expect(request).to eq(expected_response)
        end
      end
    end
  end

  describe '#upsert_user_budget_cap_overrides' do
    let(:overrides) do
      [
        { entityId: "1", capAmount: 100.0, enabled: true },
        { entityId: "2", capAmount: 200.0, enabled: false }
      ]
    end

    let(:request) do
      client.upsert_user_budget_cap_overrides(overrides: overrides)
    end

    let(:query) do
      described_class::UPSERT_USER_BUDGET_CAPS_MUTATION
    end

    context 'for gitlab.com request' do
      let(:namespace_id) { 1234 }
      let(:license_key) { nil }
      let(:admin_headers) do
        {
          "X-Admin-Email" => "gl_com_api@gitlab.com",
          "X-Admin-Token" => "customer_admin_token"
        }
      end

      let(:expected_variables) do
        {
          input: {
            overrides: overrides,
            namespaceId: namespace_id
          }
        }
      end

      let(:portal_response) do
        {
          data: {
            upsertUserBudgetCapsBulk: {
              userBudgetCapOverrides: [
                {
                  entityId: "1",
                  cap: 100.0,
                  capEnabled: true,
                  selfManagedInstanceActivationId: nil
                },
                {
                  entityId: "2",
                  cap: 200.0,
                  capEnabled: false,
                  selfManagedInstanceActivationId: nil
                }
              ],
              errors: []
            }
          }
        }
      end

      it 'sends correct params and returns success' do
        expect(::Gitlab::HTTP).to receive(:post).with(
          graphql_url,
          headers: headers,
          body: {
            query: query, variables: expected_variables
          }.to_json
        ).and_return(instance_double(
          HTTParty::Response,
          response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
          parsed_response: portal_response
        ))

        expect(request).to eq({
          success: true,
          userBudgetCapOverrides:
            portal_response.dig(
              :data, :upsertUserBudgetCapsBulk,
              :userBudgetCapOverrides
            )
        })
      end

      context 'when CDot returns errors' do
        let(:portal_response) do
          {
            data: {
              upsertUserBudgetCapsBulk: {
                userBudgetCapOverrides: nil,
                errors: ["Cap must be greater than or equal to 0"]
              }
            }
          }
        end

        it 'returns failure with errors' do
          expect(::Gitlab::HTTP).to receive(:post).with(
            graphql_url,
            headers: headers,
            body: {
              query: query, variables: expected_variables
            }.to_json
          ).and_return(instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: portal_response
          ))

          expect(request).to eq({
            success: false,
            errors: ["Cap must be greater than or equal to 0"]
          })
        end
      end

      context 'when CDot returns nil mutation data' do
        let(:portal_response) do
          { data: { upsertUserBudgetCapsBulk: nil } }
        end

        it 'raises an error' do
          expect(::Gitlab::HTTP).to receive(:post).with(
            graphql_url,
            headers: headers,
            body: {
              query: query, variables: expected_variables
            }.to_json
          ).and_return(instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: portal_response
          ))

          expect { request }.to raise_error(
            described_class::ResponseError
          )
        end
      end
    end

    context 'for self-managed request' do
      let(:admin_headers) { nil }
      let(:namespace_id) { nil }
      let(:license_key) { 'license_key' }

      let(:expected_variables) do
        {
          input: {
            overrides: overrides,
            licenseKey: license_key,
            uniqueInstanceId: Gitlab::GlobalAnonymousId.instance_id
          }
        }
      end

      let(:portal_response) do
        {
          data: {
            upsertUserBudgetCapsBulk: {
              userBudgetCapOverrides: [
                {
                  entityId: "1",
                  cap: 100.0,
                  capEnabled: true,
                  selfManagedInstanceActivationId: "activation-123"
                }
              ],
              errors: []
            }
          }
        }
      end

      it 'sends license_key and uniqueInstanceId' do
        expect(::Gitlab::HTTP).to receive(:post).with(
          graphql_url,
          headers: headers,
          body: {
            query: query, variables: expected_variables
          }.to_json
        ).and_return(instance_double(
          HTTParty::Response,
          response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
          parsed_response: portal_response
        ))

        expect(request).to eq({
          success: true,
          userBudgetCapOverrides:
            portal_response.dig(
              :data, :upsertUserBudgetCapsBulk,
              :userBudgetCapOverrides
            )
        })
      end
    end
  end

  describe '#upsert_flat_user_cap' do
    let(:flat_user_cap) { 50.0 }
    let(:flat_user_cap_enabled) { true }
    let(:request) do
      client.upsert_flat_user_cap(
        flat_user_cap: flat_user_cap,
        flat_user_cap_enabled: flat_user_cap_enabled
      )
    end

    let(:query) { described_class::UPSERT_FLAT_USER_CAP_MUTATION }

    context 'for gitlab.com request' do
      let(:namespace_id) { 1234 }
      let(:license_key) { nil }
      let(:admin_headers) do
        {
          "X-Admin-Email" => "gl_com_api@gitlab.com",
          "X-Admin-Token" => "customer_admin_token"
        }
      end

      let(:expected_variables) do
        {
          input: {
            flatUserCap: flat_user_cap,
            flatUserCapEnabled: flat_user_cap_enabled,
            namespaceId: namespace_id
          }
        }
      end

      let(:portal_response) do
        {
          data: {
            upsertBudgetCapSubscription: {
              subscriptionBudgetCap: {
                subscriptionName: "A-S00012345",
                flatUserCap: flat_user_cap,
                flatUserCapEnabled: flat_user_cap_enabled
              },
              errors: []
            }
          }
        }
      end

      it 'sends correct params and returns success' do
        expect(::Gitlab::HTTP).to receive(:post).with(
          graphql_url,
          headers: headers,
          body: { query: query, variables: expected_variables }.to_json
        ).and_return(instance_double(
          HTTParty::Response,
          response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
          parsed_response: portal_response
        ))

        expect(request).to eq({
          success: true,
          subscriptionBudgetCap:
            portal_response.dig(
              :data, :upsertBudgetCapSubscription,
              :subscriptionBudgetCap
            )
        })
      end

      context 'when CDot returns errors' do
        let(:portal_response) do
          {
            data: {
              upsertBudgetCapSubscription: {
                subscriptionBudgetCap: nil,
                errors: ["Flat user cap must be greater than or equal to 0"]
              }
            }
          }
        end

        it 'returns failure with errors' do
          expect(::Gitlab::HTTP).to receive(:post).with(
            graphql_url,
            headers: headers,
            body: { query: query, variables: expected_variables }.to_json
          ).and_return(instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: portal_response
          ))

          expect(request).to eq({
            success: false,
            errors: ["Flat user cap must be greater than or equal to 0"]
          })
        end
      end

      context 'when CDot returns nil mutation data' do
        let(:portal_response) do
          { data: { upsertBudgetCapSubscription: nil } }
        end

        it 'raises an error' do
          expect(::Gitlab::HTTP).to receive(:post).with(
            graphql_url,
            headers: headers,
            body: { query: query, variables: expected_variables }.to_json
          ).and_return(instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: portal_response
          ))

          expect { request }.to raise_error(
            described_class::ResponseError
          )
        end
      end

      context 'when CDot returns an unsuccessful response' do
        let(:portal_response) do
          {
            data: {
              errors: "Something went wrong"
            }
          }
        end

        it 'raises an error' do
          expect(::Gitlab::HTTP).to receive(:post).with(
            graphql_url,
            headers: headers,
            body: { query: query, variables: expected_variables }.to_json
          ).and_return(instance_double(
            HTTParty::Response,
            response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
            parsed_response: portal_response
          ))

          expect { request }.to raise_error(
            described_class::ResponseError,
            "Received an error from CustomerDot"
          )
        end
      end
    end

    context 'for self-managed request' do
      let(:admin_headers) { nil }
      let(:namespace_id) { nil }
      let(:license_key) { 'license_key' }

      let(:expected_variables) do
        {
          input: {
            flatUserCap: flat_user_cap,
            flatUserCapEnabled: flat_user_cap_enabled,
            licenseKey: license_key
          }
        }
      end

      let(:portal_response) do
        {
          data: {
            upsertBudgetCapSubscription: {
              subscriptionBudgetCap: {
                subscriptionName: "A-S00012345",
                flatUserCap: flat_user_cap,
                flatUserCapEnabled: flat_user_cap_enabled
              },
              errors: []
            }
          }
        }
      end

      it 'sends license_key without namespaceId' do
        expect(::Gitlab::HTTP).to receive(:post).with(
          graphql_url,
          headers: headers,
          body: { query: query, variables: expected_variables }.to_json
        ).and_return(instance_double(
          HTTParty::Response,
          response: Net::HTTPSuccess.new(1.0, '200', 'OK'),
          parsed_response: portal_response
        ))

        expect(request).to eq({
          success: true,
          subscriptionBudgetCap:
            portal_response.dig(
              :data, :upsertBudgetCapSubscription,
              :subscriptionBudgetCap
            )
        })
      end
    end
  end

  describe 'CustomersDot read timeout' do
    let(:namespace_id) { nil }
    let(:license_key) { 'license-key' }
    let(:admin_headers) { nil }
    let(:http_response) do
      instance_double(HTTParty::Response, response: Net::HTTPSuccess.new(1.0, '200', 'OK'), parsed_response: {})
    end

    it 'passes an explicit read timeout through to the HTTP client' do
      expect(::Gitlab::HTTP).to receive(:post)
        .with(graphql_url, hash_including(read_timeout: 25))
        .and_return(http_response)

      client.send(:execute_cdot_graphql, query: 'query', variables: {}, read_timeout: 25)
    end

    it 'leaves the default timeout in place when none is given' do
      expect(::Gitlab::HTTP).to receive(:post)
        .with(graphql_url, hash_excluding(:read_timeout))
        .and_return(http_response)

      client.send(:execute_cdot_graphql, query: 'query', variables: {})
    end
  end
end
