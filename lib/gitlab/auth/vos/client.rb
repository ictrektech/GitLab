# frozen_string_literal: true

module Gitlab
  module Auth
    module Vos
      # Verify an application token online. VOS remains authoritative for revocation and user state.
      class Client
        InvalidIdentity = Class.new(StandardError)
        MAX_TOKEN_BYTES = 8192

        def initialize(endpoint:, client_id:)
          @endpoint = endpoint.to_s.delete_suffix('/')
          @client_id = client_id
        end

        def verify(token)
          raise InvalidIdentity unless token.is_a?(String) && token.bytesize.between?(1, MAX_TOKEN_BYTES)

          introspection = request(:post, 'introspect', body: {
            token: token, token_type_hint: 'access_token', client_id: @client_id
          })
          unless introspection['active'] == true && introspection['client_id'] == @client_id &&
              introspection['aud'] == @client_id && introspection['token_type'] == 'Bearer' &&
              introspection['scope'].to_s.split.include?('openid') &&
              introspection['exp'].is_a?(Integer) && introspection['exp'] > Time.now.to_i
            raise InvalidIdentity
          end

          claims = request(:get, 'userinfo', headers: { 'Authorization' => "Bearer #{token}" })
          subject = claims['sub']
          unless subject.is_a?(String) && subject.length.between?(1, 255) &&
              subject == introspection['sub'] && claims['enable'] == 1 &&
              claims['preferred_username'].is_a?(String) && !claims['preferred_username'].strip.empty?
            raise InvalidIdentity
          end

          digest = Digest::SHA256.hexdigest(subject)
          {
            uid: digest,
            name: claims['nickname'].to_s.strip.presence || claims['preferred_username'].strip,
            nickname: "vos_#{digest.first(24)}",
            email: "vos-#{digest}@users.invalid"
          }
        rescue Gitlab::HTTP::Error, JSON::ParserError, URI::InvalidURIError
          raise InvalidIdentity, 'VOS identity verification failed'
        end

        private

        def request(method, path, **options)
          uri = URI.parse(@endpoint)
          unless %w[http https].include?(uri.scheme) && uri.host.present? && !uri.userinfo && !uri.query && !uri.fragment
            raise InvalidIdentity
          end

          # Only the administrator-configured VOS endpoint may receive credentials.
          response = Gitlab::HTTP.public_send(method, "#{@endpoint}/#{path}", **options,
            allow_local_requests: true, follow_redirects: false, timeout: 10)
          raise InvalidIdentity unless response.code == 200

          result = Gitlab::Json::SafeParser.parse(response.body)
          raise InvalidIdentity unless result.is_a?(Hash)
          raise InvalidIdentity if result.key?('code') && result['code'] != 0

          result['data'].is_a?(Hash) ? result['data'] : result
        end
      end
    end
  end
end
