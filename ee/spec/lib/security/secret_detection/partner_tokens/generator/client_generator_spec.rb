# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::Generator::ClientGenerator, feature_category: :secret_detection do
  let(:vendor_definition) do
    Security::SecretDetection::PartnerTokens::Generator::VendorDefinition.new(
      token_type: 'Acme API token',
      class_name: 'AcmeGeneratedClient',
      partner_name: 'acme',
      endpoint: 'https://api.acme.dev/v1/whoami',
      http_method: 'get',
      auth_style: 'bearer',
      token_pattern: '\\Aacme_[a-z0-9]{20}\\z',
      sample_token: "acme_#{'a' * 20}",
      status_map: { '200' => 'active', '401' => 'inactive', '429' => 'rate_limit', '500' => 'network_error' },
      rate_limit_key: 'partner_acme_api',
      doc_url: 'https://docs.acme.example'
    )
  end

  let(:generator) { described_class.new(vendor_definition) }
  let(:prefix_attrs) { { auth_style: 'header', auth_param: 'Authorization', auth_prefix: 'AccessKey ' } }

  describe '#client_source' do
    context 'with an auth style the generator does not model' do
      it 'fails at generation time instead of emitting invalid Ruby' do
        allow(vendor_definition).to receive(:auth_style).and_return('query')

        expect { generator.client_source }
          .to raise_error(ArgumentError, /unsupported auth_style/)
      end
    end

    it 'produces frozen_string_literal Ruby with the right constants' do
      src = generator.client_source

      expect(src).to include('# frozen_string_literal: true')
      expect(src).to include('class AcmeGeneratedClient < BaseClient')
      expect(src).to include('API_ENDPOINT = "https://api.acme.dev/v1/whoami"')
    end

    it 'emits the unknown fallthrough for unmapped codes, never inactive', :aggregate_failures do
      src = generator.client_source
      else_branch = src[/else.*?end/m]

      expect(else_branch).to include('token_response(:unknown)')
      expect(else_branch).not_to include(':inactive')
    end

    it 'collapses codes with the same outcome into one when branch' do
      allow(vendor_definition).to receive(:compiled_status_map)
        .and_return({ 200 => :active, 202 => :active, 401 => :inactive })

      src = generator.client_source

      expect(src).to include('when 200, 202')
      expect(src.scan('token_response(:active)').size).to eq(1)
    end

    # A `when` for an explicitly-unknown code would duplicate the else body and
    # trip Lint/DuplicateBranch on the generated file.
    it 'lets explicitly mapped unknown codes fall through to the else branch', :aggregate_failures do
      allow(vendor_definition).to receive(:compiled_status_map)
        .and_return({ 200 => :active, 401 => :inactive, 403 => :unknown })

      src = generator.client_source

      expect(src).not_to include('when 403')
      expect(src.scan('token_response(:unknown)').size).to eq(1)
    end

    it 'notes the absent vendor doc URL when the definition has none' do
      allow(vendor_definition).to receive(:doc_url).and_return(nil)

      expect(generator.client_source).to include('The definition provided no vendor doc URL.')
    end

    it 'emits the declared header as the credential header' do
      allow(vendor_definition).to receive_messages(auth_style: 'header', auth_param: 'Acme-Api-Key')

      expect(generator.client_source).to include('{ "Acme-Api-Key" => token_value')
    end

    it 'emits basic auth with the token as the username' do
      allow(vendor_definition).to receive(:auth_style).and_return('basic_username')

      # rubocop:disable Lint/InterpolationCheck -- asserting the literal #{} in generated source
      expect(generator.client_source).to include('Base64.strict_encode64("#{token_value}:")')
      # rubocop:enable Lint/InterpolationCheck
    end

    it 'emits basic auth headers one per line so rubocop -a leaves them unchanged', :aggregate_failures do
      allow(vendor_definition).to receive(:auth_style).and_return('basic_username')

      src = generator.client_source

      expect { RubyVM::InstructionSequence.compile(src) }.not_to raise_error
      expect(src).to match(%r{^\s*'Authorization' => "Basic .+",\n\s*'Accept' => 'application/json'$})
    end

    it 'keeps the headers on one line without extra headers' do
      expect(generator.client_source).to include("'Accept' => 'application/json' }")
    end

    it 'emits each extra header on its own line between the credential and Accept', :aggregate_failures do
      allow(vendor_definition).to receive(:extra_headers).and_return('Acme-Version' => '2024-01-01')

      src = generator.client_source

      expect { RubyVM::InstructionSequence.compile(src) }.not_to raise_error
      expect(src).to match(
        %r{^\s*'Authorization' => "Bearer .+",\n\s*"Acme-Version" => "2024-01-01",\n\s*'Accept' => 'application/json'$}
      )
    end

    context 'with extra headers on other auth styles' do
      using RSpec::Parameterized::TableSyntax

      where(:auth_style, :credential_line) do
        'header'         | /^\s*"Acme-Api-Key" => token_value,$/
        'basic_username' | /^\s*'Authorization' => "Basic .+",$/
        'basic_password' | /^\s*'Authorization' => "Basic .+",$/
      end

      with_them do
        it 'emits valid Ruby with the credential on its own line', :aggregate_failures do
          allow(vendor_definition).to receive_messages(
            auth_style: auth_style, auth_param: 'Acme-Api-Key', extra_headers: { 'Acme-Version' => '2024-01-01' }
          )

          src = generator.client_source

          expect { RubyVM::InstructionSequence.compile(src) }.not_to raise_error
          expect(src).to match(credential_line)
        end
      end
    end

    it 'emits the auth prefix in front of the token, one header per line', :aggregate_failures do
      allow(vendor_definition).to receive_messages(**prefix_attrs)

      src = generator.client_source

      expect { RubyVM::InstructionSequence.compile(src) }.not_to raise_error
      expect(src).to match(%r{^\s*"Authorization" => "AccessKey #\{token_value\}",\n\s*'Accept' => 'application/json'$})
    end

    it 'emits basic auth with the token as the password and a fixed username' do
      allow(vendor_definition).to receive_messages(auth_style: 'basic_password', auth_param: 'api')

      expect(generator.client_source).to include('Base64.strict_encode64("api:#{token_value}")')
    end

    it 'emits basic auth with an empty username when basic_password has no auth_param' do
      allow(vendor_definition).to receive_messages(auth_style: 'basic_password', auth_param: nil)

      expect(generator.client_source).to include('Base64.strict_encode64(":#{token_value}")')
    end

    it 'emits basic_password headers one per line so rubocop -a leaves them unchanged', :aggregate_failures do
      allow(vendor_definition).to receive_messages(auth_style: 'basic_password', auth_param: 'api')

      src = generator.client_source

      expect { RubyVM::InstructionSequence.compile(src) }.not_to raise_error
      expect(src).to match(%r{^\s*'Authorization' => "Basic .+",\n\s*'Accept' => 'application/json'$})
    end

    it 'safely embeds an endpoint containing a single quote' do
      endpoint = "https://api.acme.example/v1/whoami?note=it's-fine"
      allow(vendor_definition).to receive(:endpoint).and_return(endpoint)

      src = generator.client_source

      expect { RubyVM::InstructionSequence.compile(src) }.not_to raise_error
      expect(src).to include(endpoint)
    end

    it 'safely embeds quotes and backslashes in partner_name and token_type', :aggregate_failures do
      allow(vendor_definition).to receive_messages(
        token_type: %q(Bob's API token),
        partner_name: 'acme "prod" \\ vendor'
      )

      expect(generator.registry_entry).to include(%q("Bob's API token" =>))
      expect { RubyVM::InstructionSequence.compile(generator.client_source) }.not_to raise_error
      expect { RubyVM::InstructionSequence.compile("{ #{generator.registry_entry} }") }.not_to raise_error
    end
  end

  describe 'the generated client behaves correctly once loaded', :aggregate_failures do
    # Exercise the real produced code, proving the AI-assisted path yields a
    # working verifier. We eval the generated class body into an anonymous
    # subclass of BaseClient so nothing leaks into the global namespace.
    let(:generated_class) do
      klass = Class.new(Security::SecretDetection::PartnerTokens::BaseClient)
      klass.class_eval(generator.class_body_source, generator.client_path)
      # Give the anonymous class a real name so name-derived behaviour (error
      # tracking, inspect output) works exactly as it would for a generated,
      # required file.
      stub_const('Security::SecretDetection::PartnerTokens::AcmeGeneratedClient', klass)
      klass
    end

    let(:client) { generated_class.new }
    let(:valid_token) { "acme_#{'a' * 20}" }
    let(:response) { instance_double(Net::HTTPResponse) }

    it 'returns active on 200' do
      allow(response).to receive_messages(code: '200', body: '{}')
      allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)

      expect(client.verify_token(valid_token).active?).to be(true)
    end

    it 'returns inactive on 401' do
      allow(response).to receive_messages(code: '401', body: '{}')
      allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)

      expect(client.verify_token(valid_token).inactive?).to be(true)
    end

    it 'returns unknown on an unmapped code' do
      allow(response).to receive_messages(code: '418', body: '')
      allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)

      expect(client.verify_token(valid_token).unknown?).to be(true)
    end

    context 'with extra headers' do
      before do
        allow(vendor_definition).to receive(:extra_headers).and_return('Acme-Version' => '2024-01-01')
      end

      it 'sends them with the request' do
        allow(response).to receive_messages(code: '200', body: '{}')
        allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)

        client.verify_token(valid_token)

        expect(Integrations::Clients::HTTP).to have_received(:get)
          .with(anything, headers: hash_including('Acme-Version' => '2024-01-01'))
      end
    end

    context 'with an auth prefix' do
      before do
        allow(vendor_definition).to receive_messages(**prefix_attrs)
      end

      it 'sends the prefix in front of the token' do
        allow(response).to receive_messages(code: '200', body: '{}')
        allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)

        client.verify_token(valid_token)

        expect(Integrations::Clients::HTTP).to have_received(:get)
          .with(anything, headers: hash_including('Authorization' => "AccessKey #{valid_token}"))
      end
    end

    it 'raises on rate limit and service error' do
      allow(response).to receive_messages(code: '429', body: '')
      allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)
      expect { client.verify_token(valid_token) }.to raise_error(generated_class::RateLimitError)

      allow(response).to receive(:code).and_return('500')
      expect { client.verify_token(valid_token) }.to raise_error(generated_class::NetworkError)
    end

    it 'labels metrics and metadata with the vendor, not the class name' do
      allow(response).to receive_messages(code: '200', body: '{}')
      allow(Integrations::Clients::HTTP).to receive(:get).and_return(response)

      expect(client.verify_token(valid_token).metadata[:partner]).to eq('ACME')
    end
  end

  describe '#spec_source' do
    it 'generates a runnable spec referencing the class and guardrails' do
      src = generator.spec_source

      expect(src).to include('RSpec.describe Security::SecretDetection::PartnerTokens::AcmeGeneratedClient')
      expect(src).to include('unknown, never inactive')
      expect(src).to include("it_behaves_like 'a partner token client', http_method: :get")
    end

    it 'generates error-branch contexts for mapped rate-limit and service-error codes', :aggregate_failures do
      src = generator.spec_source

      expect(src).to include('raise_error(described_class::RateLimitError)')
      expect(src).to include('raise_error(described_class::NetworkError)')
    end

    it 'generates a context for an explicitly mapped unknown code' do
      allow(vendor_definition).to receive(:compiled_status_map)
        .and_return({ 200 => :active, 401 => :inactive, 403 => :unknown })

      src = generator.spec_source

      expect(src).to include("context 'when the vendor maps a code to unknown' do")
    end

    it 'generates a context for each further code of a status outcome', :aggregate_failures do
      allow(vendor_definition).to receive(:compiled_status_map)
        .and_return({ 200 => :active, 403 => :active, 401 => :inactive, 410 => :inactive })

      src = generator.spec_source

      expect(src).to include("context 'when the vendor returns 403' do", "context 'when the vendor returns 410' do")
      expect(src).not_to include("context 'when the vendor returns 200' do")
      expect { RubyVM::InstructionSequence.compile(src) }.not_to raise_error
    end

    it 'generates an extra headers example that matches the request keywords', :aggregate_failures do
      allow(vendor_definition).to receive(:extra_headers).and_return('Acme-Version' => '2024-01-01')

      src = generator.spec_source

      expect(src).to include("it 'sends the extra headers' do")
      expect(src).to match(/^\s*expected_headers = \{\n\s*"Acme-Version" => "2024-01-01"\n\s*\}$/)
      expect(src).to include('.with(anything, headers: hash_including(expected_headers))')
      expect { RubyVM::InstructionSequence.compile(src) }.not_to raise_error
    end

    it 'expects the body keyword in the extra headers example for POST definitions' do
      allow(vendor_definition).to receive_messages(http_method: 'post', extra_headers: { 'Acme-Version' => '1' })

      expect(generator.spec_source).to include('headers: hash_including(expected_headers), body: anything')
    end

    it 'generates an auth prefix example that expects the prefixed header', :aggregate_failures do
      allow(vendor_definition).to receive_messages(**prefix_attrs)

      src = generator.spec_source

      expect(src).to include("it 'sends the auth prefix' do")
      expect(src).to include('expected_header = { "Authorization" => "AccessKey #{valid_token}" }')
      expect(src).to include('.with(anything, headers: hash_including(expected_header))')
      expect { RubyVM::InstructionSequence.compile(src) }.not_to raise_error
    end

    it 'expects the body keyword in the auth prefix example for POST definitions' do
      allow(vendor_definition).to receive_messages(http_method: 'post', **prefix_attrs)

      expect(generator.spec_source).to include('headers: hash_including(expected_header), body: anything')
    end

    it 'adds none of them for one code per status outcome, no extra headers and no prefix', :aggregate_failures do
      src = generator.spec_source

      expect(src).not_to include("context 'when the vendor returns")
      expect(src).not_to include('sends the extra headers')
      expect(src).not_to include('sends the auth prefix')
    end

    # Error outcomes and explicit unknown codes are optional in a definition,
    # unlike active/inactive which the contract requires.
    it 'notes missing optional mappings instead of emitting empty contexts', :aggregate_failures do
      allow(vendor_definition).to receive(:compiled_status_map)
        .and_return({ 200 => :active, 401 => :inactive })

      src = generator.spec_source

      expect(src).to include('# no rate_limit mapping declared')
      expect(src).to include('# no network_error mapping declared')
      expect(src).to include('# no explicit unknown mapping declared')
    end

    it 'notes a missing inactive mapping instead of emitting an empty context' do
      allow(vendor_definition).to receive(:compiled_status_map).and_return({ 200 => :active })

      src = generator.spec_source

      expect(src).to include('# no inactive mapping declared')
    end

    it 'notes a missing active mapping instead of emitting an empty context' do
      allow(vendor_definition).to receive(:compiled_status_map).and_return({ 401 => :inactive })

      src = generator.spec_source

      expect(src).to include('# no active mapping declared')
    end
  end

  describe '#client_path and #spec_path' do
    it 'derives both file names from the class name' do
      expect(generator.client_path)
        .to eq('ee/lib/security/secret_detection/partner_tokens/acme_generated_client.rb')
      expect(generator.spec_path)
        .to eq('ee/spec/lib/security/secret_detection/partner_tokens/acme_generated_client_spec.rb')
    end
  end

  describe '#registry_entry' do
    it 'produces a paste-ready ADR-006 registry line' do
      entry = generator.registry_entry

      expect(entry).to include(%("Acme API token" =>))
      expect(entry).to include('client_class: ::Security::SecretDetection::PartnerTokens::AcmeGeneratedClient')
      expect(entry).to include('rate_limit_key: :partner_acme_api')
    end

    it 'restricts new vendors to GSS findings' do
      expect(generator.registry_entry).to include('enabled_targets: [Scanners::GSS].freeze')
    end
  end
end
