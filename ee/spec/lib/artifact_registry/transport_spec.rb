# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::Transport, :aggregate_failures, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  subject(:transport) { described_class.new(**constructor_args) }

  let(:base_url) { 'https://artifact-registry.example.test' }
  let(:url) { 'https://artifact-registry.example.test/api/v1/my-group/repositories' }
  let(:path) { '/api/v1/my-group/repositories' }
  let(:current_user) { instance_double(User) }
  let(:organization) { instance_double(Organizations::Organization) }
  let(:token_exchange) { instance_double(ArtifactRegistry::TokenExchange, token_for: 'user-jwt') }
  let(:service_credential) { instance_double(ArtifactRegistry::ServiceCredential, token: 'svc-token') }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  describe '.new' do
    where(blank_base_url: [nil, ''])

    with_them do
      it 'rejects a blank base_url' do
        expect { described_class.new(**constructor_args, base_url: blank_base_url) }
          .to raise_error(ArtifactRegistry::Errors::ConfigurationError, 'base_url is required')
      end
    end

    it 'rejects a base_url that fails the configuration rules' do
      expect { described_class.new(**constructor_args, base_url: 'https://ar.test/api/v1') }
        .to raise_error(ArtifactRegistry::Errors::ConfigurationError, 'base_url must not carry a path')
    end

    it 'logs the unparseable base_url and raises without echoing it' do
      allow(Gitlab::ErrorTracking).to receive(:log_exception)

      expect { described_class.new(**constructor_args, base_url: 'https://ar-internal.example:80|80') }
        .to raise_error(ArtifactRegistry::Errors::ConfigurationError, 'base_url is not a parseable URL')
      expect(Gitlab::ErrorTracking).to have_received(:log_exception)
        .with(instance_of(Addressable::URI::InvalidURIError), { url: 'https://ar-internal.example:80|80' })
    end
  end

  describe '#user_request' do
    it 'sends the user bearer token minted for the organization and returns the parsed response' do
      request = stub_request(:post, url)
        .with(
          query: { 'limit' => '2' },
          body: { 'name' => 'my-repo' },
          headers: { 'Authorization' => 'Bearer user-jwt', 'User-Agent' => %r{\AGitLab/} }
        )
        .to_return(status: 201, body: { 'id' => 'repo-1' }.to_json, headers: json_headers)

      response = transport.user_request(:post, path, slug: 'my-group', query: { limit: 2 }, body: { name: 'my-repo' })

      expect(response.body).to eq({ 'id' => 'repo-1' })
      expect(request).to have_been_requested
      expect(token_exchange).to have_received(:token_for).with(current_user, organization)
    end

    it 'raises ArgumentError without a current user and sends nothing' do
      request = stub_request(:get, url)
      transport = described_class.new(**constructor_args, current_user: nil)

      expect { transport.user_request(:get, path, slug: 'my-group') }
        .to raise_error(ArgumentError, 'current_user is required for a per-user request')
      expect(request).not_to have_been_requested
    end

    it 'raises AuthorizationError when no token is minted and sends nothing' do
      request = stub_request(:get, url)
      allow(token_exchange).to receive(:token_for).and_return('')

      expect { transport.user_request(:get, path, slug: 'my-group') }
        .to raise_error(ArtifactRegistry::Errors::AuthorizationError, 'No Artifact Registry credential was obtained')
      expect(request).not_to have_been_requested
    end
  end

  describe '#service_request' do
    it 'sends the bare service token in its own header and no Authorization header' do
      request = stub_request(:get, url)
        .with(headers: { 'Gitlab-Artifact-Registry-Token' => 'svc-token' }) { |req| !req.headers.key?('Authorization') }
        .to_return(status: 200, body: '{}', headers: json_headers)

      transport.service_request(:get, path, uuid: 'uuid-1')

      expect(request).to have_been_requested
      expect(token_exchange).not_to have_received(:token_for)
    end

    it 'raises AuthorizationError when the service token is blank and sends nothing' do
      request = stub_request(:get, url)
      allow(service_credential).to receive(:token).and_return(nil)

      expect { transport.service_request(:get, path) }
        .to raise_error(ArtifactRegistry::Errors::AuthorizationError, 'No Artifact Registry credential was obtained')
      expect(request).not_to have_been_requested
    end
  end

  describe 'correlation id' do
    it 'forwards the current correlation id as X-Request-Id' do
      request = stub_request(:get, url).with(headers: { 'X-Request-Id' => 'corr-1' })

      Labkit::Correlation::CorrelationId.use_id('corr-1') do
        transport.service_request(:get, path)
      end

      expect(request).to have_been_requested
    end

    it 'omits X-Request-Id when there is no correlation id' do
      allow(Labkit::Correlation::CorrelationId).to receive(:current_id).and_return(nil)
      request = stub_request(:get, url).with { |req| !req.headers.key?('X-Request-Id') }

      transport.service_request(:get, path)

      expect(request).to have_been_requested
    end
  end

  describe 'query encoding' do
    around do |example|
      notation = WebMock::Config.instance.query_values_notation
      WebMock::Config.instance.query_values_notation = :flat_array
      example.run
    ensure
      WebMock::Config.instance.query_values_notation = notation
    end

    it 'repeats a list-valued key once per value, rather than bracketing it' do
      request = stub_request(:get, "#{url}?format=docker&format=oci")

      transport.service_request(:get, path, query: { format: %w[docker oci] })

      expect(request).to have_been_requested
    end
  end

  describe 'failures' do
    it 'hands a non-2xx response to ErrorMapping with the attribution' do
      stub_request(:get, url).to_return(status: 404, body: '{}', headers: json_headers)

      expect_next_instance_of(ArtifactRegistry::ErrorMapping) do |mapping|
        expect(mapping).to receive(:raise_error)
          .with(404, instance_of(Faraday::Response), :get, slug: 'my-group').and_call_original
      end

      expect { transport.user_request(:get, path, slug: 'my-group') }
        .to raise_error(ArtifactRegistry::Errors::ApiError)
    end

    it 'hands a Faraday failure to ErrorMapping with the attribution' do
      stub_request(:post, url).to_raise(Faraday::ConnectionFailed.new('refused'))

      expect_next_instance_of(ArtifactRegistry::ErrorMapping) do |mapping|
        expect(mapping).to receive(:raise_transport_error)
          .with(instance_of(Faraday::ConnectionFailed), :post, slug: 'my-group').and_call_original
      end

      expect { transport.user_request(:post, path, slug: 'my-group') }
        .to raise_error(ArtifactRegistry::Errors::UnavailableError) do |error|
          expect(error.cause).to be_a(Faraday::ConnectionFailed)
        end
    end

    it 'reports the failed attempt with the request path and without the query string' do
      allow(Gitlab::ErrorTracking).to receive(:log_exception)
      stub_request(:delete, url).with(query: { 'destructive' => 'true' })
        .to_raise(Faraday::ConnectionFailed.new('refused'))

      Labkit::Correlation::CorrelationId.use_id('corr-1') do
        expect { transport.user_request(:delete, path, slug: 'my-group', query: { destructive: 'true' }) }
          .to raise_error(ArtifactRegistry::Errors::UnavailableError)
      end

      expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
        instance_of(Faraday::ConnectionFailed),
        {
          url: 'https://artifact-registry.example.test/api/v1/my-group/repositories',
          method: :delete,
          correlation_id: 'corr-1'
        }
      )
    end

    context 'when the failed attempt has no request path' do
      where(request_url: [nil, URI('https://artifact-registry.example.test')])

      with_them do
        it 'reports the base URL' do
          allow(Gitlab::ErrorTracking).to receive(:log_exception)
          error = Faraday::ConnectionFailed.new('refused')

          transport.send(:report_attempt, { url: request_url, method: :get }, error)

          expect(Gitlab::ErrorTracking).to have_received(:log_exception)
            .with(error, hash_including(url: 'https://artifact-registry.example.test', method: :get))
        end
      end
    end

    it 'keeps the parsing failure as the cause of an unreadable 404' do
      stub_request(:get, url).to_return(status: 404, body: 'not json', headers: json_headers)

      expect { transport.user_request(:get, path, slug: 'my-group') }
        .to raise_error(ArtifactRegistry::Errors::ApiError) do |error|
          expect(error.status).to eq(404)
          expect(error.cause).to be_a(Faraday::ParsingError)
        end
    end
  end

  describe 'RETRY_OPTIONS' do
    it 'allows GET, HEAD, OPTIONS, and PUT but not POST or DELETE' do
      expect(described_class::RETRY_OPTIONS[:methods]).to contain_exactly(:get, :head, :options, :put)
    end
  end

  describe 'retries' do
    let(:retry_options) do
      described_class::RETRY_OPTIONS.merge(interval: 0, interval_randomness: 0, backoff_factor: 0)
    end

    before do
      stub_const('ArtifactRegistry::Transport::RETRY_OPTIONS', retry_options)
      stub_request(http_method, url).to_raise(Faraday::ConnectionFailed.new('refused'))
    end

    where(:http_method, :attempts) do
      :get    | (described_class::RETRY_OPTIONS[:max] + 1)
      :put    | (described_class::RETRY_OPTIONS[:max] + 1)
      :post   | 1
      :delete | 1
    end

    with_them do
      it 'replays only the idempotent methods' do
        expect { transport.user_request(http_method, path, slug: 'my-group') }
          .to raise_error(ArtifactRegistry::Errors::UnavailableError)
        expect(a_request(http_method, url)).to have_been_made.times(attempts)
      end
    end
  end

  describe 'HTTPS guard' do
    let(:base_url) { 'http://artifact-registry.example.test' }
    let(:url) { 'http://artifact-registry.example.test/api/v1/my-group/repositories' }

    it 'allows http outside production' do
      request = stub_request(:get, url)

      transport.service_request(:get, path)

      expect(request).to have_been_requested
    end

    context 'in production' do
      before do
        allow(Rails.env).to receive(:production?).and_return(true)
      end

      it 'refuses http before any credential is read' do
        request = stub_request(:get, url)

        expect { transport.service_request(:get, path) }.to raise_error(
          ArtifactRegistry::Errors::ConfigurationError,
          'base_url must be HTTPS in production for credential-authenticated requests'
        )
        expect(request).not_to have_been_requested
        expect(service_credential).not_to have_received(:token)
      end

      context 'with an https base_url' do
        let(:base_url) { 'https://artifact-registry.example.test' }
        let(:url) { 'https://artifact-registry.example.test/api/v1/my-group/repositories' }

        it 'allows the request' do
          request = stub_request(:get, url)

          transport.service_request(:get, path)

          expect(request).to have_been_requested
        end
      end
    end
  end

  describe '#log_error' do
    it 'logs the error with the request identifiers and the caller context' do
      allow(Gitlab::ErrorTracking).to receive(:log_exception)
      error = ArtifactRegistry::Errors::ApiError.new('gone', status: 404, request_id: 'req-1')

      Labkit::Correlation::CorrelationId.use_id('corr-1') do
        transport.log_error(error, slug: 'my-group')
      end

      expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
        instance_of(ArtifactRegistry::Errors::ApiError),
        {
          url: 'https://artifact-registry.example.test',
          correlation_id: 'corr-1',
          status: 404,
          request_id: 'req-1',
          slug: 'my-group'
        }
      )
    end
  end

  describe '#raise_terminal' do
    before do
      allow(Gitlab::ErrorTracking).to receive(:log_exception)
      allow(Labkit::Correlation::CorrelationId).to receive(:current_id).and_return('corr-1')
    end

    def raise_unavailable(**options)
      transport.raise_terminal(ArtifactRegistry::Errors::UnavailableError, 'AR is down', :get, **options)
    end

    def raise_unavailable_while_rescuing
      raise StandardError, 'reporting side'
    rescue StandardError
      raise_unavailable
    end

    it 'reports the error and raises it with the given cause' do
      cause = Faraday::TimeoutError.new('timed out')

      expect { raise_unavailable(cause: cause, status: 503, slug: 'my-group') }
        .to raise_error(ArtifactRegistry::Errors::UnavailableError, 'AR is down') do |error|
          expect(error.status).to eq(503)
          expect(error.cause).to be(cause)
        end

      expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
        instance_of(ArtifactRegistry::Errors::UnavailableError),
        {
          url: 'https://artifact-registry.example.test',
          method: :get,
          correlation_id: 'corr-1',
          status: 503,
          slug: 'my-group'
        }
      )
    end

    it 'raises with no cause, even inside a rescue, when none is given' do
      expect { raise_unavailable_while_rescuing }.to raise_error(ArtifactRegistry::Errors::UnavailableError) do |error|
        expect(error.cause).to be_nil
      end
    end
  end

  describe '#redacted_snippet' do
    it 'redacts the service token and bearer credentials and bounds the length' do
      snippet = transport.redacted_snippet("Bearer user-jwt svc-token #{'x' * 300}")

      expect(snippet).to start_with('Bearer [REDACTED] [REDACTED] xxx')
      expect(snippet.length).to eq(ArtifactRegistry::Redaction::MAX_SNIPPET)
    end

    it 'still redacts bearer credentials when the service token cannot be read' do
      allow(service_credential).to receive(:token).and_raise(ArtifactRegistry::Errors::AuthorizationError)

      expect(transport.redacted_snippet('Bearer user-jwt')).to eq('Bearer [REDACTED]')
    end

    context 'when the first service token read fails' do
      before do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_request(:get, url).to_return(
          status: 500, body: { error: { message: 'upstream rejected svc-token' } }.to_json, headers: json_headers
        )

        allow(service_credential).to receive(:token).and_raise(ArtifactRegistry::Errors::AuthorizationError)
        transport.redacted_snippet('warm-up')
        allow(service_credential).to receive(:token).and_return('svc-token')
      end

      it 'redacts the service token once it can be read' do
        expect { transport.service_request(:get, path) }
          .to raise_error(ArtifactRegistry::Errors::UnavailableError, 'upstream rejected [REDACTED]')
        expect(Gitlab::ErrorTracking).to have_received(:log_exception)
          .with(having_attributes(message: 'upstream rejected [REDACTED]'), anything)
        expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
          .with(having_attributes(message: /svc-token/), anything)
      end
    end
  end

  def constructor_args
    {
      base_url: base_url,
      current_user: current_user,
      organization: organization,
      token_exchange: token_exchange,
      service_credential: service_credential
    }
  end
end
