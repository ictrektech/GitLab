# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::ErrorMapping, :aggregate_failures, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  subject(:mapping) { described_class.new(transport) }

  let(:transport) do
    ArtifactRegistry::Transport.new(
      base_url: 'https://artifact-registry.example.test',
      current_user: nil,
      organization: nil,
      token_exchange: nil,
      service_credential: instance_double(ArtifactRegistry::ServiceCredential, token: 'svc-token')
    )
  end

  let(:v7_id) { '01928f3a-7b2c-7d4e-8f5a-000000000001' }
  let(:digest) { "sha256:#{'a' * 64}" }

  before do
    allow(Gitlab::ErrorTracking).to receive(:log_exception)
  end

  describe '#raise_error' do
    def raise_for(status, body: nil, headers: {})
      response = instance_double(Faraday::Response, body: body, headers: headers)

      mapping.raise_error(status, response, :get, slug: 'my-group')
    end

    def envelope(**error)
      { 'error' => { 'code' => 'error_code', 'message' => 'something went wrong', 'request_id' => 'req-1' }
        .merge(error.stringify_keys) }
    end

    context 'for each status band' do
      where(:status, :error_class) do
        401 | ArtifactRegistry::Errors::AuthorizationError
        403 | ArtifactRegistry::Errors::AuthorizationError
        404 | ArtifactRegistry::Errors::ApiError
        409 | ArtifactRegistry::Errors::ApiError
        429 | ArtifactRegistry::Errors::UnavailableError
        503 | ArtifactRegistry::Errors::UnavailableError
      end

      with_them do
        it 'raises the error class for the band with the envelope message and request id' do
          expect { raise_for(status, body: envelope) }.to raise_error(error_class, 'something went wrong') do |error|
            expect(error.status).to eq(status)
            expect(error.request_id).to eq('req-1')
          end
        end
      end
    end

    it 'reports a terminal status with its code and the caller attribution' do
      expect { raise_for(503, body: envelope(code: 'unavailable')) }
        .to raise_error(ArtifactRegistry::Errors::UnavailableError)
      expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
        instance_of(ArtifactRegistry::Errors::UnavailableError),
        hash_including(method: :get, status: 503, code: 'unavailable', request_id: 'req-1', slug: 'my-group')
      )
    end

    context 'for an authorization failure' do
      where(status: [401, 403])

      with_them do
        it 'reports it once with its code and the caller attribution' do
          expect { raise_for(status, body: envelope(code: 'forbidden')) }
            .to raise_error(ArtifactRegistry::Errors::AuthorizationError)
          expect(Gitlab::ErrorTracking).to have_received(:log_exception).once
          expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
            instance_of(ArtifactRegistry::Errors::AuthorizationError),
            hash_including(method: :get, status: status, code: 'forbidden', request_id: 'req-1', slug: 'my-group')
          )
        end
      end
    end

    it 'does not report a client error' do
      expect { raise_for(404, body: envelope) }.to raise_error(ArtifactRegistry::Errors::ApiError)
      expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
    end

    it 'carries the code and the allowlisted details on an ApiError' do
      body = envelope(code: 'invalid', details: { 'repository_ids' => [v7_id], 'unknown' => 'dropped' })

      expect { raise_for(422, body: body) }.to raise_error(ArtifactRegistry::Errors::ApiError) do |error|
        expect(error.code).to eq('invalid')
        expect(error.details).to eq({ 'repository_ids' => ['01928f3a-7b2c-7d4e-8f5a-000000000001'] })
      end
    end

    it 'redacts credentials in every envelope field' do
      body = envelope(code: 'svc-token', message: 'Bearer leaked-token', request_id: 'Bearer leaked-id')

      expect { raise_for(404, body: body) }
        .to raise_error(ArtifactRegistry::Errors::ApiError, 'Bearer [REDACTED]') do |error|
          expect(error.code).to eq('[REDACTED]')
          expect(error.request_id).to eq('Bearer [REDACTED]')
        end
    end

    context 'without an AR envelope' do
      where(:body, :message) do
        { 'error' => 'plain error string' } | 'plain error string'
        { 'detail' => 'proxy detail', 'title' => 'Forbidden', 'token' => 'svc-token' } | 'proxy detail Forbidden'
        'upstream connect error' | 'upstream connect error'
      end

      with_them do
        it 'reads the message from the body and carries no code or details' do
          expect { raise_for(404, body: body) }.to raise_error(ArtifactRegistry::Errors::ApiError, message) do |error|
            expect(error.code).to be_nil
            expect(error.details).to be_nil
          end
        end
      end
    end

    it 'falls back to the X-Request-Id header when the envelope has no request id' do
      headers = { 'X-Request-Id' => 'Bearer header-token' }

      expect { raise_for(404, body: 'not found', headers: headers) }
        .to raise_error(ArtifactRegistry::Errors::ApiError) do |error|
          expect(error.request_id).to eq('Bearer [REDACTED]')
        end
    end

    it 'prefers the envelope request id over the header' do
      expect { raise_for(404, body: envelope, headers: { 'X-Request-Id' => 'header-id' }) }
        .to raise_error(ArtifactRegistry::Errors::ApiError) do |error|
          expect(error.request_id).to eq('req-1')
        end
    end

    describe 'details allowlist' do
      where(:details, :expected) do
        { 'repository_ids' => ['01928f3a-7b2c-7d4e-8f5a-000000000001'] } |
          { 'repository_ids' => ['01928f3a-7b2c-7d4e-8f5a-000000000001'] }
        { 'repository_ids' => ['3f2c1b4a-9d8e-4c7b-a6f5-0123456789ab'] } | nil
        { 'repository_ids' => [] }                                        | nil
        { 'parents' => ["sha256:#{'a' * 64}"] }                           | { 'parents' => ["sha256:#{'a' * 64}"] }
        { 'upstream_repository_id' => '01928f3a-7b2c-7d4e-8f5a-000000000001' } |
          { 'upstream_repository_id' => '01928f3a-7b2c-7d4e-8f5a-000000000001' }
        { 'upstream_repository_id' => '01928F3A-7B2C-7D4E-8F5A-000000000001' } | nil
        { 'unknown' => 'value' }                                          | nil
        'not a hash'                                                      | nil
      end

      with_them do
        it 'carries only the allowlisted shapes' do
          expect { raise_for(409, body: envelope(details: details)) }
            .to raise_error(ArtifactRegistry::Errors::ApiError) do |error|
              expect(error.details).to eq(expected)
            end
        end
      end

      it 'drops the parent digests whole and logs it when one is not digest-shaped' do
        body = envelope(details: { 'parents' => [digest, 'sha256:short'] })

        expect { raise_for(409, body: body) }.to raise_error(ArtifactRegistry::Errors::ApiError) do |error|
          expect(error.details).to be_nil
        end
        expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
          an_object_having_attributes(
            class: ArtifactRegistry::Errors::Error,
            message: 'Artifact Registry sent 2 parent digests, not all of the digest shape'
          ),
          hash_including(url: 'https://artifact-registry.example.test')
        )
      end
    end
  end

  describe '#raise_transport_error' do
    def raise_from_rescue(error)
      raise error
    rescue Faraday::Error => e
      mapping.raise_transport_error(e, :get, slug: 'my-group')
    end

    def parsing_error(status)
      Faraday::ParsingError.new(JSON::ParserError.new('unexpected token'), { status: status })
    end

    it 'raises a 404 ApiError for an unreadable 404, caused by the parsing failure' do
      expect { raise_from_rescue(parsing_error(404)) }.to raise_error(ArtifactRegistry::Errors::ApiError) do |error|
        expect(error.status).to eq(404)
        expect(error.cause).to be_a(Faraday::ParsingError)
      end
      expect(Gitlab::ErrorTracking).not_to have_received(:log_exception)
    end

    context 'for an unreadable authorization failure' do
      where(status: [401, 403])

      with_them do
        it 'reports and raises AuthorizationError caused by the parsing failure' do
          expect { raise_from_rescue(parsing_error(status)) }.to raise_error(
            ArtifactRegistry::Errors::AuthorizationError, 'Artifact Registry returned an unreadable response'
          ) do |error|
            expect(error.status).to eq(status)
            expect(error.cause).to be_a(Faraday::ParsingError)
          end
          expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
            instance_of(ArtifactRegistry::Errors::AuthorizationError),
            hash_including(method: :get, status: status, slug: 'my-group')
          )
        end
      end
    end

    it 'reports any other unreadable status as UnavailableError' do
      expect { raise_from_rescue(parsing_error(500)) }.to raise_error(
        ArtifactRegistry::Errors::UnavailableError, 'Artifact Registry returned an unreadable response'
      ) do |error|
        expect(error.status).to eq(500)
        expect(error.cause).to be_a(Faraday::ParsingError)
      end
      expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
        instance_of(ArtifactRegistry::Errors::UnavailableError),
        hash_including(method: :get, status: 500, slug: 'my-group')
      )
    end

    it 'reports a TLS failure with its reason' do
      expect { raise_from_rescue(Faraday::SSLError.new('certificate verify failed')) }.to raise_error(
        ArtifactRegistry::Errors::UnavailableError, 'Artifact Registry TLS connection failed: certificate verify failed'
      ) do |error|
        expect(error.cause).to be_a(Faraday::SSLError)
      end
    end

    it 'reports any other transport failure as a failed request' do
      expect { raise_from_rescue(Faraday::ConnectionFailed.new('refused')) }.to raise_error(
        ArtifactRegistry::Errors::UnavailableError, 'Artifact Registry request failed'
      ) do |error|
        expect(error.cause).to be_a(Faraday::ConnectionFailed)
      end
      expect(Gitlab::ErrorTracking).to have_received(:log_exception).with(
        instance_of(ArtifactRegistry::Errors::UnavailableError),
        hash_including(method: :get, slug: 'my-group')
      )
    end
  end
end
