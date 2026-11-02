# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::Redaction, :aggregate_failures, feature_category: :artifact_registry do
  subject(:redaction) { described_class.new }

  describe '#redact' do
    it 'redacts a bearer credential' do
      expect(redaction.redact('request with Bearer leaked-bearer failed'))
        .to eq('request with Bearer [REDACTED] failed')
    end

    it 'redacts a JWT-shaped token' do
      jwt = 'not-a-real-jwt-000.not-a-real-jwt-111.not-a-real-jwt-222'

      expect(redaction.redact("token #{jwt} rejected")).to eq('token [REDACTED] rejected')
    end

    it 'leaves versioned filenames, versions, coordinates, hostnames, and IPs alone' do
      {
        'artifact mylib-1.2.3.jar not found' => 'artifact mylib-1.2.3.jar not found',
        'package numpy-1.26.4-cp311-none-any.whl rejected' => 'package numpy-1.26.4-cp311-none-any.whl rejected',
        'requires v1.2.3 or later' => 'requires v1.2.3 or later',
        'requires 1.2.3.RELEASE' => 'requires 1.2.3.RELEASE',
        'package com.example.my-lib not found' => 'package com.example.my-lib not found',
        'could not reach artifact-registry.example.test' => 'could not reach artifact-registry.example.test',
        'upstream 10.0.0.1.nip.io refused' => 'upstream 10.0.0.1.nip.io refused',
        'see file.name.txt for details' => 'see file.name.txt for details'
      }.each do |input, expected|
        expect(redaction.redact(input)).to eq(expected)
      end
    end

    context 'with a service token to scrub' do
      subject(:redaction) { described_class.new(service_token: 'svc token/value+x') }

      it 'redacts the token in its raw and percent-encoded forms' do
        expect(redaction.redact('AR rejected svc token/value+x here')).to eq('AR rejected [REDACTED] here')
        expect(redaction.redact('AR rejected svc%20token%2Fvalue%2Bx here')).to eq('AR rejected [REDACTED] here')
      end

      it 'leaves a first-party encoded URL path intact' do
        expect(redaction.redact('logged https://ar.test/v1/foo%2Fbar%20baz/repositories done'))
          .to eq('logged https://ar.test/v1/foo%2Fbar%20baz/repositories done')
      end
    end

    context 'with a blank service token' do
      subject(:redaction) { described_class.new(service_token: '') }

      it 'scrubs nothing' do
        expect(redaction.redact('nothing to scrub')).to eq('nothing to scrub')
      end
    end
  end

  describe '#snippet' do
    it 'redacts, strips and bounds the text' do
      text = "  Bearer leaked #{'a' * 210}  "

      snippet = redaction.snippet(text)

      expect(snippet).to start_with('Bearer [REDACTED]')
      expect(snippet.length).to eq(described_class::MAX_SNIPPET)
    end

    it 'returns nil for blank input' do
      expect(redaction.snippet('   ')).to be_nil
    end
  end

  describe '#build_context / #allowed_context' do
    it 'keeps only the allowlisted keys and freezes the result' do
      context = redaction.build_context(
        url: 'https://example.test', method: :get, correlation_id: 'corr-1', uuid: 'uuid-1', authorization: 'Bearer x'
      )

      expect(context).to eq(url: 'https://example.test', method: :get, correlation_id: 'corr-1', uuid: 'uuid-1')
      expect(context).to be_frozen
    end

    it 'drops allowlisted keys whose value is nil' do
      expect(redaction.allowed_context(uuid: 'uuid-1', status: nil)).to eq(uuid: 'uuid-1')
    end
  end

  describe '#redacted_exception' do
    it 'rebuilds the same subclass with its typed attributes and backtrace' do
      exception = ArtifactRegistry::Errors::ApiError.new(
        'parse failed for Bearer plain-token', status: 404, code: 'not_found', request_id: 'req-1'
      )
      exception.set_backtrace(['ee/lib/artifact_registry/client.rb:1:in `run\''])

      redacted = redaction.redacted_exception(exception)

      expect(redacted).to be_a(ArtifactRegistry::Errors::ApiError)
      expect(redacted.message).to eq('parse failed for Bearer [REDACTED]')
      expect(redacted).to have_attributes(status: 404, code: 'not_found', request_id: 'req-1')
      expect(redacted.backtrace).to eq(exception.backtrace)
    end

    it 'rebuilds a base error without a code' do
      exception = ArtifactRegistry::Errors::Error.new('failed for Bearer plain-token', status: 500, request_id: 'req-1')

      redacted = redaction.redacted_exception(exception)

      expect(redacted).to be_an_instance_of(ArtifactRegistry::Errors::Error)
      expect(redacted).to have_attributes(message: 'failed for Bearer [REDACTED]', status: 500, request_id: 'req-1')
    end

    it 'leaves the backtrace unset when the original has none' do
      redacted = redaction.redacted_exception(ArtifactRegistry::Errors::Error.new('failed'))

      expect(redacted.backtrace).to be_nil
    end

    it 'falls back to a message-only copy for an exception outside the hierarchy' do
      redacted = redaction.redacted_exception(ArgumentError.new('leak Bearer plain-token'))

      expect(redacted).to be_an_instance_of(ArgumentError)
      expect(redacted.message).to eq('leak Bearer [REDACTED]')
    end
  end
end
