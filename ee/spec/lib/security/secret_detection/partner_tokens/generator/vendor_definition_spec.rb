# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe Security::SecretDetection::PartnerTokens::Generator::VendorDefinition, feature_category: :secret_detection do
  let(:valid_attrs) do
    {
      token_type: 'Widgets API token',
      class_name: 'WidgetsClient',
      endpoint: 'https://api.widgets.dev/v1/me',
      http_method: 'get',
      auth_style: 'bearer',
      token_pattern: '\\Awgt_[a-z0-9]{20}\\z',
      sample_token: "wgt_#{'a' * 20}",
      status_map: { '200' => 'active', '401' => 'inactive', '429' => 'rate_limit', '500' => 'network_error' },
      rate_limit_key: 'partner_widgets_api',
      doc_url: 'https://docs.widgets.example'
    }
  end

  describe 'a valid definition' do
    subject(:definition) { described_class.new(valid_attrs) }

    it 'compiles the status map to integer keys and symbol outcomes' do
      expect(definition.compiled_status_map).to eq(
        200 => :active, 401 => :inactive, 429 => :rate_limit, 500 => :network_error
      )
    end

    it 'derives the partner name from the class name' do
      expect(definition.partner_name).to eq('Widgets')
    end

    it 'exposes a usable Regexp' do
      expect(definition.regexp).to be_a(Regexp)
      expect(definition.regexp).to match('wgt_abcdefghij0123456789')
    end
  end

  describe 'validation' do
    it 'rejects a missing required field' do
      expect { described_class.new(valid_attrs.except(:endpoint)) }
        .to raise_error(described_class::InvalidDefinitionError, /endpoint/)
    end

    it 'names every missing required field' do
      expect { described_class.new(status_map: valid_attrs[:status_map]) }
        .to raise_error(described_class::InvalidDefinitionError,
          /token_type, class_name, endpoint, token_pattern, sample_token, rate_limit_key/)
    end

    it 'rejects an unsupported http_method' do
      expect { described_class.new(valid_attrs.merge(http_method: 'delete')) }
        .to raise_error(described_class::InvalidDefinitionError, /http_method/)
    end

    it 'rejects a non-https endpoint' do
      expect { described_class.new(valid_attrs.merge(endpoint: 'http://api.widgets.dev')) }
        .to raise_error(described_class::InvalidDefinitionError, /https/)
    end

    it 'rejects an endpoint host that looks like a placeholder' do
      expect { described_class.new(valid_attrs.merge(endpoint: 'https://api.example.com/v1/me')) }
        .to raise_error(described_class::InvalidDefinitionError, /placeholder/)
    end

    it 'rejects a placeholder host regardless of case' do
      expect { described_class.new(valid_attrs.merge(endpoint: 'https://API.EXAMPLE.COM/v1/me')) }
        .to raise_error(described_class::InvalidDefinitionError, /placeholder/)
    end

    # 'https://' parses as URI::HTTPS, so the https check alone accepts it.
    it 'rejects a host-less https endpoint' do
      expect { described_class.new(valid_attrs.merge(endpoint: 'https://')) }
        .to raise_error(described_class::InvalidDefinitionError, /host is missing/)
    end

    it 'rejects an endpoint that does not parse as a URL' do
      expect { described_class.new(valid_attrs.merge(endpoint: 'https://api.widgets example')) }
        .to raise_error(described_class::InvalidDefinitionError, /not a valid URL/)
    end

    it 'rejects a sample_token that does not match token_pattern' do
      expect { described_class.new(valid_attrs.merge(sample_token: 'nope')) }
        .to raise_error(described_class::InvalidDefinitionError, /sample_token "nope" does not match token_pattern/)
    end

    it 'rejects an unanchored token pattern' do
      expect { described_class.new(valid_attrs.merge(token_pattern: 'wgt_[a-z0-9]{20}')) }
        .to raise_error(described_class::InvalidDefinitionError, /anchored/)
    end

    it 'rejects a token_pattern that is not a valid regexp' do
      expect { described_class.new(valid_attrs.merge(token_pattern: '\\Awgt_[\\z')) }
        .to raise_error(described_class::InvalidDefinitionError, /not a valid regexp/)
    end

    it 'rejects a pattern with no fixed prefix and no length constraint' do
      expect { described_class.new(valid_attrs.merge(token_pattern: '\\A[a-z]{4}\\z', sample_token: 'aaaa')) }
        .to raise_error(described_class::InvalidDefinitionError, /too broad/)
    end

    it 'accepts a keyless fixed-length pattern' do
      attrs = valid_attrs.merge(token_pattern: '\\A[0-9a-f]{32}\\z', sample_token: 'a' * 32)

      expect { described_class.new(attrs) }.not_to raise_error
    end

    it 'rejects a quantified wildcard dot' do
      expect { described_class.new(valid_attrs.merge(token_pattern: '\\Aab.{16,}\\z', sample_token: "ab#{'a' * 16}")) }
        .to raise_error(described_class::InvalidDefinitionError, /must not quantify/)
    end

    it 'does not count a long quantifier over a catch-all class as a length constraint' do
      attrs = valid_attrs.merge(token_pattern: '\\A[\\s\\S]{16,}\\z', sample_token: 'a' * 16)

      expect { described_class.new(attrs) }
        .to raise_error(described_class::InvalidDefinitionError, /too broad/)
    end

    # Regression guard: token_pattern lands in generated source as a Regexp
    # literal, where #{...} would interpolate when the generated file loads.
    it 'rejects a token_pattern containing interpolation characters (source-injection guard)' do
      # rubocop:disable Lint/InterpolationCheck -- the literal #{} is the injection payload under test
      expect { described_class.new(valid_attrs.merge(token_pattern: '\\Awgt_#{1}\\z')) }
        .to raise_error(described_class::InvalidDefinitionError, /must not contain '#'/)
      # rubocop:enable Lint/InterpolationCheck
    end

    it 'rejects a class name that is not CamelCase ending in Client' do
      expect { described_class.new(valid_attrs.merge(class_name: 'widgets')) }
        .to raise_error(described_class::InvalidDefinitionError, /class_name/)
    end

    it 'rejects an unsupported auth style' do
      expect { described_class.new(valid_attrs.merge(auth_style: 'magic')) }
        .to raise_error(described_class::InvalidDefinitionError, /auth_style/)
    end

    it "requires auth_param when auth_style is 'header'" do
      expect { described_class.new(valid_attrs.merge(auth_style: 'header')) }
        .to raise_error(described_class::InvalidDefinitionError, /requires auth_param/)
    end

    context 'with an invalid auth_param' do
      where(:auth_param) { ['X-Api Key', "X-#{'a' * 39}"] }

      with_them do
        it 'rejects the header name' do
          expect { described_class.new(valid_attrs.merge(auth_style: 'header', auth_param: auth_param)) }
            .to raise_error(described_class::InvalidDefinitionError, /auth_param must be up to 40 characters/)
        end
      end
    end

    it 'accepts an auth_param at its length limit' do
      definition = described_class.new(valid_attrs.merge(auth_style: 'header', auth_param: "X-#{'a' * 38}"))

      expect(definition.auth_param).to eq("X-#{'a' * 38}")
    end

    it 'accepts basic_password with a fixed username in auth_param' do
      expect { described_class.new(valid_attrs.merge(auth_style: 'basic_password', auth_param: 'api')) }
        .not_to raise_error
    end

    it 'accepts basic_password without auth_param' do
      expect { described_class.new(valid_attrs.merge(auth_style: 'basic_password')) }
        .not_to raise_error
    end

    context 'with an auth style that ignores auth_param' do
      where(:auth_style) { %w[bearer basic_username] }

      with_them do
        it 'rejects the definition instead of silently dropping the value' do
          expect { described_class.new(valid_attrs.merge(auth_style: auth_style, auth_param: 'api')) }
            .to raise_error(described_class::InvalidDefinitionError, /auth_param is ignored by auth_style/)
        end
      end
    end

    it 'rejects unsafe characters in token_type' do
      expect { described_class.new(valid_attrs.merge(token_type: "Widgets'; end")) }
        .to raise_error(described_class::InvalidDefinitionError, /token_type/)
    end

    it 'accepts a slash in token_type' do
      definition = described_class.new(valid_attrs.merge(token_type: 'Hashicorp Terraform user/org API token'))

      expect(definition.token_type).to eq('Hashicorp Terraform user/org API token')
    end

    it 'rejects a rate_limit_key that is not a lowercase symbol name' do
      expect { described_class.new(valid_attrs.merge(rate_limit_key: 'Partner-Widgets')) }
        .to raise_error(described_class::InvalidDefinitionError, /rate_limit_key/)
    end

    it 'rejects unsafe characters in partner_name' do
      expect { described_class.new(valid_attrs.merge(partner_name: 'Widgets#')) }
        .to raise_error(described_class::InvalidDefinitionError, /partner_name/)
    end

    it 'rejects a default status of inactive (unknown-never-inactive)' do
      map = valid_attrs[:status_map].merge('default' => 'inactive')
      expect { described_class.new(valid_attrs.merge(status_map: map)) }
        .to raise_error(described_class::InvalidDefinitionError, /never be inactive/)
    end

    it "rejects a default status other than 'unknown'" do
      map = valid_attrs[:status_map].merge('default' => 'active')
      expect { described_class.new(valid_attrs.merge(status_map: map)) }
        .to raise_error(described_class::InvalidDefinitionError, /default can only be 'unknown'/)
    end

    it "accepts a default of 'unknown' and keeps it out of the compiled status map" do
      map = valid_attrs[:status_map].merge('default' => 'unknown')
      definition = described_class.new(valid_attrs.merge(status_map: map))

      expect(definition.compiled_status_map.keys).to match_array([200, 401, 429, 500])
    end

    it 'rejects an empty status_map' do
      expect { described_class.new(valid_attrs.merge(status_map: {})) }
        .to raise_error(described_class::InvalidDefinitionError, /status_map is required/)
    end

    it 'rejects a status_map that can never confirm a live token' do
      expect { described_class.new(valid_attrs.merge(status_map: { '401' => 'inactive' })) }
        .to raise_error(described_class::InvalidDefinitionError, /never yields active/)
    end

    it 'rejects a status_map that can never confirm a dead token' do
      expect { described_class.new(valid_attrs.merge(status_map: { '200' => 'active' })) }
        .to raise_error(described_class::InvalidDefinitionError, /never yields inactive/)
    end

    it 'rejects an unknown outcome value' do
      expect { described_class.new(valid_attrs.merge(status_map: { '200' => 'alive' })) }
        .to raise_error(described_class::InvalidDefinitionError, /outcome/)
    end

    it 'rejects a status_map key that is not an HTTP status code' do
      expect { described_class.new(valid_attrs.merge(status_map: { '2xx' => 'active' })) }
        .to raise_error(described_class::InvalidDefinitionError, /must be an HTTP status code/)
    end

    it 'rejects a status_map key that is not an assigned HTTP status code' do
      expect { described_class.new(valid_attrs.merge(status_map: { '999' => 'active' })) }
        .to raise_error(described_class::InvalidDefinitionError, /must be an HTTP status code/)
    end

    # Regression guard: doc_url lands verbatim in a `#` comment line in
    # generated source (see ClientGenerator#client_source). A newline there
    # would end the comment early and let whatever follows run as real Ruby
    # in the generated, loaded verifier file.
    it 'rejects a doc_url containing a newline (source-injection guard)' do
      unsafe_doc_url = "https://docs.widgets.example\nEVIL_CONSTANT = 1"

      expect { described_class.new(valid_attrs.merge(doc_url: unsafe_doc_url)) }
        .to raise_error(described_class::InvalidDefinitionError, /doc_url/)
    end

    it 'rejects a doc_url containing other control characters' do
      expect { described_class.new(valid_attrs.merge(doc_url: "https://docs.widgets.example\t")) }
        .to raise_error(described_class::InvalidDefinitionError, /doc_url/)
    end

    it 'accepts a blank doc_url' do
      expect { described_class.new(valid_attrs.merge(doc_url: nil)) }.not_to raise_error
    end

    describe 'extra_headers' do
      using RSpec::Parameterized::TableSyntax

      it 'defaults to no extra headers' do
        expect(described_class.new(valid_attrs).extra_headers).to eq({})
      end

      it 'accepts a fixed header with string names and values' do
        definition = described_class.new(valid_attrs.merge(extra_headers: { 'GoCardless-Version': '2015-07-06' }))

        expect(definition.extra_headers).to eq('GoCardless-Version' => '2015-07-06')
      end

      it 'accepts a name and a value at their length limits' do
        headers = { "X-#{'a' * 38}" => 'a' * 48 }

        expect(described_class.new(valid_attrs.merge(extra_headers: headers)).extra_headers).to eq(headers)
      end

      where(:extra_headers, :message) do
        'Version: 1'                         | /must be a map/
        { 1 => '1' }                         | /name must be a string/
        { 'Bad Header' => '1' }              | /valid HTTP header name/
        { "X-#{'a' * 39}" => '1' }           | /valid HTTP header name/
        { 'accept' => 'text/plain' }         | /cannot set "accept"/
        { 'Authorization' => 'Bearer x' }    | /cannot set "Authorization"/
        { 'X-Version' => 1.1 }               | /must be a quoted string/
        { 'X-Version' => true }              | /must be a quoted string/
        { 'X-Version' => '' }                | /must be 1 to 48/
        { 'X-Version' => 'a' * 49 }          | /must be 1 to 48/
        { 'X-Version' => '1"; system("x")' } | /must be 1 to 48/
        { 'X-Version' => 'v#1' }             | /must be 1 to 48/
        { 'X-Version' => 'a\\b' }            | /must be 1 to 48/
        { 'X-Version' => "1\nfoo" }          | /must be 1 to 48/
        { 'X-Version' => 'vé' }              | /must be 1 to 48/
        { 'X-Version' => '   ' }             | /must be 1 to 48/
        { 'X-Version' => ' 1' }              | /must be 1 to 48/
        { 'X-V' => '1', 'x-v' => '2' }       | /repeats a header name: x-v/
      end

      with_them do
        it 'rejects the header' do
          expect { described_class.new(valid_attrs.merge(extra_headers: extra_headers)) }
            .to raise_error(described_class::InvalidDefinitionError, message)
        end
      end

      it 'rejects a header that repeats the auth_param header' do
        attrs = valid_attrs.merge(auth_style: 'header', auth_param: 'X-Api-Key', extra_headers: { 'x-api-key' => '1' })

        expect { described_class.new(attrs) }
          .to raise_error(described_class::InvalidDefinitionError, /cannot set "x-api-key"/)
      end

      it 'allows a header named like the auth_param when the auth style sends no such header' do
        attrs = valid_attrs.merge(auth_style: 'basic_password', auth_param: 'X-Api-Key',
          extra_headers: { 'X-Api-Key' => '1' })

        expect(described_class.new(attrs).extra_headers).to eq('X-Api-Key' => '1')
      end
    end

    describe 'auth_prefix' do
      let(:header_attrs) { valid_attrs.merge(auth_style: 'header', auth_param: 'Authorization') }

      it 'defaults to no prefix' do
        expect(described_class.new(header_attrs).auth_prefix).to be_nil
      end

      context 'with a valid prefix' do
        where(:auth_prefix) do
          ['AccessKey ', 'Token token=', 'Api-Key ', "#{'a' * 29} "]
        end

        with_them do
          it 'accepts the prefix' do
            expect(described_class.new(header_attrs.merge(auth_prefix: auth_prefix)).auth_prefix).to eq(auth_prefix)
          end
        end
      end

      context 'with an invalid prefix' do
        where(:auth_prefix) do
          ['Key#', 'Key" ', 'Key\\ ', "Key\#{1} ", ' Key ', 'AccessKey', "#{'a' * 30} ", "Key\n ", '', 1]
        end

        with_them do
          it 'rejects the prefix' do
            expect { described_class.new(header_attrs.merge(auth_prefix: auth_prefix)) }
              .to raise_error(described_class::InvalidDefinitionError, /auth_prefix must be up to 30/)
          end
        end
      end

      context 'with an auth style other than header' do
        where(:auth_style) { %w[bearer basic_username] }

        with_them do
          it 'rejects the prefix' do
            expect { described_class.new(valid_attrs.merge(auth_style: auth_style, auth_prefix: 'AccessKey ')) }
              .to raise_error(described_class::InvalidDefinitionError, /auth_prefix needs auth_style 'header'/)
          end
        end
      end
    end
  end

  describe '.build_all' do
    let(:second_type_attrs) do
      valid_attrs.merge(
        token_type: 'Widgets OAuth token',
        class_name: 'WidgetsOauthClient',
        token_pattern: '\\Awgt_oauth_[a-z0-9]{24}\\z',
        sample_token: "wgt_oauth_#{'a' * 24}"
      )
    end

    it 'builds one definition per token type for a vendor with several token types' do
      definitions = described_class.build_all([valid_attrs, second_type_attrs])

      expect(definitions.map(&:class_name)).to contain_exactly('WidgetsClient', 'WidgetsOauthClient')
    end

    it 'rejects two token types emitting the same client class' do
      collision = second_type_attrs.merge(class_name: 'WidgetsClient')

      expect { described_class.build_all([valid_attrs, collision]) }
        .to raise_error(described_class::InvalidDefinitionError, /duplicate class_name/)
    end

    it 'rejects duplicate token types' do
      collision = valid_attrs.merge(class_name: 'OtherClient')

      expect { described_class.build_all([valid_attrs, collision]) }
        .to raise_error(described_class::InvalidDefinitionError, /duplicate token_type/)
    end
  end
end
