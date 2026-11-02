# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Auth::AuthFinders, feature_category: :system_access do
  include described_class
  include ::EE::GeoHelpers

  let(:request) { ActionDispatch::Request.new(env) }
  let_it_be_with_reload(:user) { create(:user) }
  let(:env) do
    {
      'rack.input' => ''
    }
  end

  def set_header(key, value)
    env[key] = value
  end

  describe '#find_user_from_geo_token' do
    subject { find_user_from_geo_token }

    let_it_be(:primary) { create(:geo_node, :primary) }

    let(:path) { '/api/v4/geo/graphql' }
    let(:authorization_header) do
      ::Gitlab::Geo::JsonRequest
        .new(scope: ::Gitlab::Geo::API_SCOPE, authenticating_user_id: user.id)
        .headers['Authorization']
    end

    before do
      stub_current_geo_node(primary)

      env['SCRIPT_NAME'] = path
      request.headers['Authorization'] = authorization_header
    end

    it { is_expected.to eq(user) }

    context 'when the path is not Geo specific' do
      let(:path) { '/api/v4/test' }

      it { is_expected.to be_nil }
    end

    context 'when the Authorization header is invalid' do
      let(:authorization_header) { 'invalid' }

      it { is_expected.to be_nil }
    end

    context 'when the Authorization header is nil' do
      let(:authorization_header) { '' }

      it { is_expected.to be_nil }
    end

    context 'when the Authorization header is a Geo header' do
      it 'does not authenticate when the token expired' do
        travel_to(2.minutes.from_now) { expect { subject }.to raise_error(::Gitlab::Auth::UnauthorizedError) }
      end

      it 'does not authenticate when clocks are not in sync' do
        travel_to(2.minutes.ago) { expect { subject }.to raise_error(::Gitlab::Auth::UnauthorizedError) }
      end

      it 'does not authenticate with invalid decryption key error' do
        allow_next_instance_of(::Gitlab::Geo::JwtRequestDecoder) do |instance|
          expect(instance).to receive(:decode).and_raise(Gitlab::Geo::InvalidDecryptionKeyError)
        end

        expect { subject }.to raise_error(::Gitlab::Auth::UnauthorizedError)
      end

      context 'when the scope is not API' do
        let(:authorization_header) do
          ::Gitlab::Geo::JsonRequest
            .new(scope: 'invalid', authenticating_user_id: user.id)
            .headers['Authorization']
        end

        it 'does not authenticate' do
          expect { subject }.to raise_error(::Gitlab::Auth::UnauthorizedError)
        end
      end

      context 'when it does not contain a user id' do
        let(:authorization_header) do
          ::Gitlab::Geo::JsonRequest
            .new(scope: ::Gitlab::Geo::API_SCOPE)
            .headers['Authorization']
        end

        it 'raises an unauthorize error' do
          expect { subject }.to raise_error(::Gitlab::Auth::UnauthorizedError)
        end
      end
    end

    context 'when the user does not exist' do
      let(:user) { create(:user) }

      it 'raises an unauthorized error' do
        user.delete

        expect { subject }.to raise_error(::Gitlab::Auth::UnauthorizedError)
      end
    end
  end

  describe '#find_user_from_bearer_token' do
    context 'with a personal access token' do
      before do
        env[described_class::PRIVATE_TOKEN_HEADER] = create(:personal_access_token, user: user).token
      end

      it 'returns user' do
        expect(find_user_from_bearer_token).to eq user
      end

      context 'when personal access tokens are disabled on instance level' do
        before do
          stub_licensed_features(disable_personal_access_tokens: true)
          stub_application_setting(disable_personal_access_tokens: true)
        end

        it 'raises unauthorized error' do
          expect { find_user_from_bearer_token }.to raise_error(Gitlab::Auth::UnauthorizedError)
        end
      end

      context 'when personal access tokens are disabled by enterprise group' do
        let_it_be(:enterprise_group) do
          create(:group, namespace_settings: create(:namespace_settings, disable_personal_access_tokens: true))
        end

        let_it_be(:enterprise_user_of_the_group) { create(:enterprise_user, enterprise_group: enterprise_group) }
        let_it_be(:enterprise_user_of_another_group) { create(:enterprise_user) }

        before do
          stub_saas_features(disable_personal_access_tokens: true)
          stub_licensed_features(disable_personal_access_tokens: true)
        end

        context 'for non-enterprise users of the group' do
          let(:user) { enterprise_user_of_another_group }

          it 'returns user' do
            expect(find_user_from_bearer_token).to eq user
          end
        end

        context 'for enterprise users of the group' do
          let(:user) { enterprise_user_of_the_group }

          it 'raises unauthorized error' do
            expect { find_user_from_bearer_token }.to raise_error(Gitlab::Auth::UnauthorizedError)
          end
        end

        context 'for service accounts of the group' do
          let(:user) { create(:service_account, provisioned_by_group: enterprise_group) }

          it 'returns user' do
            expect(find_user_from_bearer_token).to eq user
          end
        end
      end
    end
  end

  describe '#find_user_from_access_token' do
    before do
      env[described_class::PRIVATE_TOKEN_HEADER] = create(:personal_access_token, user: user).token
    end

    context 'when validate_access_token! returns valid' do
      it 'returns user' do
        expect(find_user_from_access_token).to eq user
      end

      context 'when personal access tokens are disabled on instance level' do
        before do
          stub_licensed_features(disable_personal_access_tokens: true)
          stub_application_setting(disable_personal_access_tokens: true)
        end

        it 'raised unauthorized error' do
          expect { find_user_from_access_token }.to raise_error(Gitlab::Auth::UnauthorizedError)
        end
      end

      context 'when personal access tokens are disabled by enterprise group' do
        let_it_be(:enterprise_group) do
          create(:group, namespace_settings: create(:namespace_settings, disable_personal_access_tokens: true))
        end

        let_it_be(:enterprise_user_of_the_group) { create(:enterprise_user, enterprise_group: enterprise_group) }
        let_it_be(:enterprise_user_of_another_group) { create(:enterprise_user) }

        before do
          stub_saas_features(disable_personal_access_tokens: true)
          stub_licensed_features(disable_personal_access_tokens: true)
        end

        context 'for non-enterprise users of the group' do
          let(:user) { enterprise_user_of_another_group }

          it 'returns user' do
            expect(find_user_from_access_token).to eq user
          end
        end

        context 'for enterprise users of the group' do
          let(:user) { enterprise_user_of_the_group }

          it 'raises unauthorized error' do
            expect { find_user_from_access_token }.to raise_error(Gitlab::Auth::UnauthorizedError)
          end
        end

        context 'for service accounts of the group' do
          let(:user) { create(:service_account, provisioned_by_group: enterprise_group) }

          it 'returns user' do
            expect(find_user_from_access_token).to eq user
          end
        end
      end
    end
  end

  describe '#find_user_from_feed_token' do
    context 'when the request format is atom' do
      before do
        env['SCRIPT_NAME'] = 'url.atom'
        env['HTTP_ACCEPT'] = 'application/atom+xml'
      end

      context 'when feed_token param is provided' do
        context 'when the feed token is valid' do
          before do
            request.update_param(:feed_token, user.feed_token)
          end

          context 'when personal access tokens are disabled' do
            before do
              stub_application_setting(disable_personal_access_tokens: true)
            end

            it 'returns user' do
              expect(find_user_from_feed_token(:rss)).to eq user
            end

            context 'when disable_personal_access_tokens feature is licensed' do
              before do
                stub_licensed_features(disable_personal_access_tokens: true)
              end

              it 'returns nil' do
                expect(find_user_from_feed_token(:rss)).to be_nil
              end
            end
          end
        end
      end
    end
  end

  describe '#find_user_from_job_token', :request_store do
    let_it_be(:project) { create(:project, :private, developers: user) }
    let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
    let_it_be(:job) { create(:ci_build, :running, pipeline: pipeline, user: user) }
    let_it_be(:route_authentication_setting) { { job_token_allowed: true } }

    subject { find_user_from_job_token }

    context 'when token is valid' do
      let(:token) { job.token }

      before do
        set_header(described_class::JOB_TOKEN_HEADER, token)
        allow(::Gitlab::Audit::Auditor).to receive(:audit)
      end

      it 'returns user and streams audit event',
        quarantine: 'https://gitlab.com/gitlab-org/quality/test-failure-issues/-/issues/18776' do
        expect(subject).to eq(user)

        expect(::Gitlab::Audit::Auditor).to have_received(:audit).with(
          name: "user_authenticated_using_job_token",
          author: user,
          scope: job.project,
          target: job,
          target_details: job.id.to_s,
          message: "#{user.name} authenticated using job token of job id: #{job.id}"
        )
      end
    end

    context 'when token is invalid' do
      let(:token) { "invalid token" }

      before do
        set_header(described_class::JOB_TOKEN_HEADER, token)
        allow(::Gitlab::Audit::Auditor).to receive(:audit)
      end

      it 'returns user' do
        expect { subject }.to raise_error(Gitlab::Auth::UnauthorizedError)
        expect(::Gitlab::Audit::Auditor).not_to have_received(:audit)
      end
    end
  end

  describe '#access_token (StatelessAccessToken path)', :request_store do
    let_it_be(:cloud_connector_key) { create(:cloud_connector_keys) }
    let_it_be(:organization) { create(:organization) }
    let_it_be(:human_user) { create(:user, organizations: [organization]) }
    let_it_be(:service_account) { create(:user, :service_account, composite_identity_enforced: true) }

    subject(:oauth_token) { access_token }

    before do
      stub_feature_flags(duo_workflow_use_token_issuer: [human_user, service_account])
      allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk).and_return(cloud_connector_key.to_jwk)
      allow(::CloudConnector::Keys).to receive(:valid).and_return([cloud_connector_key])
    end

    def issue_jwt(user: service_account, identities: [])
      ::Authn::Tokens::StatelessAccessToken.issue(
        user: user, organization: organization, ttl: 1.hour.to_i, scopes: ['ai_workflows'], identities: identities
      ).plaintext_token
    end

    context 'with a composite identity StatelessAccessToken JWT carrying the human identity' do
      let(:jwt) { issue_jwt(identities: [{ kind: 'user', local_id: human_user.id }]) }

      before do
        request.headers['Authorization'] = "Bearer #{jwt}"
      end

      it 'returns a StatelessAccessToken instance' do
        expect(oauth_token).to be_a(::Authn::Tokens::StatelessAccessToken)
      end

      it 'sets current_token' do
        oauth_token

        expect(current_token).to eq(jwt)
      end

      context 'when the JWT is sent as an access_token query parameter instead of a header' do
        before do
          env.delete('HTTP_AUTHORIZATION')
          env['QUERY_STRING'] = "access_token=#{jwt}"
        end

        it 'ignores it, so it never leaks into access/proxy logs or the Referer header' do
          expect(::Authn::Tokens::StatelessAccessToken).not_to receive(:from_jwt)

          expect { oauth_token }.to raise_error(::Gitlab::Auth::UnauthorizedError)
        end
      end

      context 'when the request is for the Kubernetes internal API' do
        before do
          env['SCRIPT_NAME'] = '/api/v4/internal/kubernetes/modules/starboard_vulnerability/policies_configuration'
        end

        it 'ignores the JWT entirely, without ever trying to decode it' do
          expect(::Authn::Tokens::StatelessAccessToken).not_to receive(:from_jwt)

          expect(oauth_token).to be_nil
        end
      end

      context 'when the request is a SCIM API request' do
        before do
          env['SCRIPT_NAME'] = '/api/scim/v2/groups/mygroup/Users'
        end

        it 'ignores the JWT entirely, without ever trying to decode it' do
          expect(::Authn::Tokens::StatelessAccessToken).not_to receive(:from_jwt)

          expect { oauth_token }.to raise_error(::Gitlab::Auth::UnauthorizedError)
        end
      end

      context 'when the endpoint declared its own authenticate_with allowlist' do
        before do
          strategies = { bearer: [:personal_access_token] }
          inheritable_setting = Struct.new(:namespace_inheritable).new({ authentication: strategies })
          allow(self).to receive_messages(
            inheritable_setting: inheritable_setting,
            access_token_from_namespace_inheritable: nil
          )
        end

        it 'ignores the JWT entirely, deferring to the endpoint allowlist' do
          expect(::Authn::Tokens::StatelessAccessToken).not_to receive(:from_jwt)

          expect(oauth_token).to be_nil
        end
      end
    end

    context 'with a composite-identity-enforced StatelessAccessToken JWT missing the identities claim' do
      before do
        request.headers['Authorization'] = "Bearer #{issue_jwt(identities: [])}"
      end

      it 'raises UnauthorizedError because the composite identity link is missing' do
        expect { oauth_token }.to raise_error(::Gitlab::Auth::UnauthorizedError)
      end
    end

    context 'with a non-StatelessAccessToken bearer token' do
      before do
        request.headers['Authorization'] = "Bearer not-a-duo-workflow-token"
      end

      it 'falls through to the Doorkeeper/IAM path and raises UnauthorizedError' do
        expect { oauth_token }.to raise_error(::Gitlab::Auth::UnauthorizedError)
      end
    end

    context 'when the feature flag is disabled for the gating user' do
      let(:jwt) { issue_jwt(identities: [{ kind: 'user', local_id: human_user.id }]) }

      before do
        stub_feature_flags(duo_workflow_use_token_issuer: false)
        request.headers['Authorization'] = "Bearer #{jwt}"
      end

      it 'falls through to the Doorkeeper/IAM path and raises UnauthorizedError' do
        expect { oauth_token }.to raise_error(::Gitlab::Auth::UnauthorizedError)
      end
    end
  end

  # Exercises the full pipeline (access_token -> validate_and_save_access_token! ->
  # AccessTokenValidationService), not just the finder in isolation, since revocation is enforced
  # downstream rather than inside access_token itself.
  describe '#find_user_from_bearer_token (StatelessAccessToken JWT)',
    :request_store, :clean_gitlab_redis_shared_state do
    let_it_be(:cloud_connector_key) { create(:cloud_connector_keys) }
    let_it_be(:organization) { create(:organization) }
    let_it_be(:human_user) { create(:user, organizations: [organization]) }

    subject(:found_user) { find_user_from_bearer_token }

    before do
      stub_feature_flags(duo_workflow_use_token_issuer: human_user)
      allow(::CloudConnector::CachingKeyLoader).to receive(:private_jwk).and_return(cloud_connector_key.to_jwk)
      allow(::CloudConnector::Keys).to receive(:valid).and_return([cloud_connector_key])
    end

    def issue_jwt
      ::Authn::Tokens::StatelessAccessToken.issue(
        user: human_user, organization: organization, ttl: 1.hour.to_i, scopes: ['ai_workflows']
      ).plaintext_token
    end

    context 'with a valid StatelessAccessToken JWT' do
      before do
        request.headers['Authorization'] = "Bearer #{issue_jwt}"
      end

      it 'authenticates the user' do
        expect(found_user).to eq(human_user)
      end
    end

    context 'with a revoked StatelessAccessToken JWT' do
      before do
        jwt = issue_jwt
        token = ::Authn::Tokens::StatelessAccessToken.from_jwt(jwt)
        ::Authn::Tokens::StatelessAccessToken::Denylist.deny!(token)
        request.headers['Authorization'] = "Bearer #{jwt}"
      end

      it 'raises RevokedError' do
        expect { found_user }.to raise_error(::Gitlab::Auth::RevokedError)
      end
    end

    context 'with an expired StatelessAccessToken JWT' do
      before do
        jwt = ::Authn::Tokens::StatelessAccessToken.issue(
          user: human_user, organization: organization, ttl: -1, scopes: ['ai_workflows']
        ).plaintext_token
        request.headers['Authorization'] = "Bearer #{jwt}"
      end

      it 'falls through to the Doorkeeper/IAM path and raises UnauthorizedError' do
        expect { found_user }.to raise_error(::Gitlab::Auth::UnauthorizedError)
      end
    end

    context 'when the token lacks the requested scope' do
      before do
        request.headers['Authorization'] = "Bearer #{issue_jwt}"
      end

      it 'raises InsufficientScopeError, so this credential cannot be replayed against the full API' do
        expect(access_token).to be_present

        expect { validate_and_save_access_token!(scopes: [:api]) }
          .to raise_error(::Gitlab::Auth::InsufficientScopeError)
      end
    end
  end

  describe '#runner_controller_token_from_authorization_token' do
    let_it_be_with_reload(:runner_controller_token) { create(:ci_runner_controller_token) }

    subject { runner_controller_token_from_authorization_token }

    context 'when route_setting is empty' do
      it { is_expected.to be_nil }
    end

    context 'when route_setting does not allow runner controller token' do
      let(:route_authentication_setting) { { runner_controller_token_allowed: false } }

      context 'and Gitlab-Agent-Api-Request header is empty' do
        it { is_expected.to be_nil }
      end

      context 'and Gitlab-Agent-Api-Request header does not matches the runner controller token' do
        before do
          request.headers['Gitlab-Agent-Api-Request'] = 'ABCD'
        end

        it { is_expected.to be_nil }
      end

      context 'and Gitlab-Agent-Api-Request header matches runner controller token' do
        before do
          request.headers['Gitlab-Agent-Api-Request'] = runner_controller_token.token
        end

        it { is_expected.to be_nil }
      end
    end

    context 'when route_setting allows runner controller token' do
      let(:route_authentication_setting) { { runner_controller_token_allowed: true } }

      context 'and Gitlab-Agent-Api-Request header is empty' do
        it { is_expected.to be_nil }
      end

      context 'and Gitlab-Agent-Api-Request header does not matches the runner controller token' do
        before do
          request.headers['Gitlab-Agent-Api-Request'] = 'ABCD'
        end

        it { is_expected.to be_nil }
      end

      context 'and Gitlab-Agent-Api-Request header matches runner controller token' do
        before do
          request.headers['Gitlab-Agent-Api-Request'] = runner_controller_token.token
        end

        it { is_expected.to eq(runner_controller_token) }

        context 'when the token has been revoked' do
          before do
            runner_controller_token.revoke!
          end

          it { is_expected.to be_nil }
        end
      end

      context 'and Gitlab-Agent-Api-Request header matches a token whose runner controller has been deleted' do
        let(:token_value) { runner_controller_token.token }

        before do
          request.headers['Gitlab-Agent-Api-Request'] = token_value
          runner_controller_token.runner_controller.destroy!
        end

        it { is_expected.to be_nil }
      end
    end
  end
end
