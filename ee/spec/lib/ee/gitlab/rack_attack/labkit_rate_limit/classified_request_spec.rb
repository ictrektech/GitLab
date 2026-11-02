# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::RackAttack::LabkitRateLimit::ClassifiedRequest, feature_category: :rate_limiting do
  using RSpec::Parameterized::TableSyntax

  let(:request) { described_class.new(Rack::MockRequest.env_for('/')) }

  describe '#labkit_facts' do
    describe 'incident management notification enable setting' do
      it 'exposes the enable setting the incident rule matches on' do
        stub_application_setting(throttle_incident_management_notification_enabled: true)

        expect(request.labkit_facts).to include(setting_incident_management_notification: true)
      end

      it 'reflects the disabled setting' do
        stub_application_setting(throttle_incident_management_notification_enabled: false)

        expect(request.labkit_facts).to include(setting_incident_management_notification: false)
      end
    end

    # The geo-JWT skips are exposed as an EE fact for the should_be_skipped
    # path/JWT decomposition (the EE geo skip rule matches it). It lives in the EE
    # classifier (not CE) because the two predicates are EE-only - referencing them
    # from CE would raise under FOSS.
    describe 'the verified_geo_request fact' do
      it 'is true for a verified Geo request' do
        allow(request).to receive(:verified_geo_request?).and_return(true)

        expect(request.labkit_facts).to include(verified_geo_request: true)
      end

      it 'is true for a geo-proxy workhorse request' do
        allow(request).to receive_messages(verified_geo_request?: false, geo_proxy_workhorse_request?: true)

        expect(request.labkit_facts).to include(verified_geo_request: true)
      end

      it 'is false for a normal request' do
        allow(request).to receive_messages(verified_geo_request?: false, geo_proxy_workhorse_request?: false)

        expect(request.labkit_facts).to include(verified_geo_request: false)
      end
    end

    describe 'the unauthenticated throttle facts' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      # Row 3: enforce alone does nothing, so info is the single off switch.
      where(:info, :enforce, :active_fact, :enforced_fact) do
        false | false | false | false
        true  | false | true  | false
        false | true  | false | false
        true  | true  | true  | true
      end

      with_them do
        it 'matches the flag state table for the unauthenticated throttle', :aggregate_failures do
          stub_feature_flags(
            rate_limiter_unauthenticated_limits_info: info,
            rate_limiter_unauthenticated_limits_enforce: enforce
          )

          expect(request.labkit_facts).to include(
            unauthenticated_limits_active: active_fact,
            unauthenticated_enforced: enforced_fact
          )
        end
      end

      it 'is strictly false rather than nil while both flags are off', :aggregate_failures do
        stub_feature_flags(
          rate_limiter_unauthenticated_limits_info: false,
          rate_limiter_unauthenticated_limits_enforce: false
        )

        facts = request.labkit_facts

        expect(facts[:unauthenticated_limits_active]).to be(false)
        expect(facts[:unauthenticated_enforced]).to be(false)
      end
    end

    describe 'the expired_oauth_token_id fact' do
      let(:request) { described_class.new(Rack::MockRequest.env_for('/oauth/token/info')) }

      # Resolving the requester records the failure this way; the request spec covers that recording.
      def facts_with_auth_failure(reason:, token_id:)
        failure = Gitlab::Auth::AuthFailure.new(reason: reason, token_id: token_id)

        Gitlab::ApplicationContext.with_context(auth_fail: failure) { request.labkit_facts }
      end

      before do
        stub_saas_features(gitlab_com_subscriptions: true)
        stub_feature_flags(rate_limiter_expired_oauth_token_per_token: true)
      end

      it 'is the token for an expired OAuth token' do
        expect(facts_with_auth_failure(reason: 'token_expired', token_id: 'OauthAccessToken/7'))
          .to include(expired_oauth_token_id: 'OauthAccessToken/7')
      end

      it 'is nil for an expired personal access token' do
        expect(facts_with_auth_failure(reason: 'token_expired', token_id: 'PersonalAccessToken/7'))
          .to include(expired_oauth_token_id: nil)
      end

      it 'is nil when the failure carries no token id' do
        expect(facts_with_auth_failure(reason: 'token_expired', token_id: nil))
          .to include(expired_oauth_token_id: nil)
      end

      where(:reason) { %w[token_revoked insufficient_scope impersonation_disabled] }

      with_them do
        it 'is nil for an OAuth token that failed for another reason' do
          expect(facts_with_auth_failure(reason: reason, token_id: 'OauthAccessToken/7'))
            .to include(expired_oauth_token_id: nil)
        end
      end

      it 'is nil without an auth failure' do
        expect(request.labkit_facts).to include(expired_oauth_token_id: nil)
      end

      it 'is nil when another credential resolved a requester' do
        authenticator = instance_double(Gitlab::Auth::RequestAuthenticator,
          find_authenticated_requester: instance_double(User, id: 42), runner: nil, job_from_token: nil)
        allow(request).to receive(:request_authenticator).and_return(authenticator)
        allow(::Gitlab::RateLimit::TierResolver).to receive(:tier_for).and_return('free')

        expect(facts_with_auth_failure(reason: 'token_expired', token_id: 'OauthAccessToken/7'))
          .to include(expired_oauth_token_id: nil)
      end

      where(:path, :expected) do
        '/api/v4/user'                    | 'OauthAccessToken/7'
        '/oauth/token/info'               | 'OauthAccessToken/7'
        '/o/my-org/oauth/userinfo'        | 'OauthAccessToken/7'
        '/group/project.atom'             | nil
        '/some-group/oauth/-/issues.atom' | nil
      end

      with_them do
        it 'is set only on a path that answers an expired token with a 401' do
          request = described_class.new(Rack::MockRequest.env_for(path))
          failure = Gitlab::Auth::AuthFailure.new(reason: 'token_expired', token_id: 'OauthAccessToken/7')

          facts = Gitlab::ApplicationContext.with_context(auth_fail: failure) { request.labkit_facts }

          expect(facts).to include(expired_oauth_token_id: expected)
        end
      end

      describe 'the expired_oauth_token_enforced fact' do
        let(:enforce_flags) do
          {
            rate_limiter_expired_oauth_token_per_token_enforce: true,
            rate_limiter_unauthenticated_limits_info: true,
            rate_limiter_unauthenticated_limits_enforce: true
          }
        end

        it 'is true for an expired OAuth token once every enforce flag is on' do
          stub_feature_flags(enforce_flags)

          expect(facts_with_auth_failure(reason: 'token_expired', token_id: 'OauthAccessToken/7'))
            .to include(expired_oauth_token_enforced: true)
        end

        it 'is false while its own enforce flag is off, so the request stays on the per-IP rules' do
          stub_feature_flags(enforce_flags.merge(rate_limiter_expired_oauth_token_per_token_enforce: false))

          expect(facts_with_auth_failure(reason: 'token_expired', token_id: 'OauthAccessToken/7'))
            .to include(expired_oauth_token_enforced: false)
        end

        it 'is false without an expired OAuth token, even with every enforce flag on' do
          stub_feature_flags(enforce_flags)

          expect(request.labkit_facts).to include(expired_oauth_token_enforced: false)
        end
      end

      it 'is nil while the flag is off' do
        stub_feature_flags(rate_limiter_expired_oauth_token_per_token: false)

        expect(facts_with_auth_failure(reason: 'token_expired', token_id: 'OauthAccessToken/7'))
          .to include(expired_oauth_token_id: nil)
      end

      it 'is absent off GitLab.com' do
        stub_saas_features(gitlab_com_subscriptions: false)

        expect(facts_with_auth_failure(reason: 'token_expired', token_id: 'OauthAccessToken/7'))
          .not_to have_key(:expired_oauth_token_id)
      end
    end

    # The dependency_proxy fact routes the Labkit rule through
    # #dependency_proxy_path?, so EE's virtual-registry exclusion applies to both
    # enforcement stacks from one definition rather than a mirrored path regex.
    describe 'the dependency_proxy fact' do
      def facts_for(path)
        described_class.new(Rack::MockRequest.env_for(path)).labkit_facts
      end

      it 'is true for a dependency proxy manifest path' do
        expect(facts_for('/v2/mygroup/dependency_proxy/containers/alpine/manifests/latest'))
          .to include(dependency_proxy: true)
      end

      it 'is false for a virtual registry container path' do
        expect(facts_for('/v2/virtual_registries/container/1/dependency_proxy/containers/img/manifests/latest'))
          .to include(dependency_proxy: false)
      end

      it 'is false for an unrelated path' do
        expect(facts_for('/dashboard/projects')).to include(dependency_proxy: false)
      end
    end

    describe 'the plan facts' do
      let(:tier_resolver) { ::Gitlab::RateLimit::TierResolver }
      let(:target_namespace) { ::Gitlab::RateLimit::TargetNamespace }
      let(:path) { '/api/v4/projects/278964/issues' }
      let(:user) { instance_double(User, id: 42) }
      let(:request) { request_with(path: path, requester: user) }

      def request_with(path:, requester: nil, job: nil)
        request = described_class.new(Rack::MockRequest.env_for(path))
        authenticator = instance_double(Gitlab::Auth::RequestAuthenticator,
          find_authenticated_requester: requester, runner: nil, job_from_token: job)
        allow(request).to receive(:request_authenticator).and_return(authenticator)
        request
      end

      before do
        stub_saas_features(gitlab_com_subscriptions: true)
        # Mirrors TierResolver#tier_for, which resolves a tier for a user requester
        # only, so a non-user requester gets no user plan for the reason the real
        # resolver gives rather than a per-example stub.
        allow(tier_resolver).to receive(:tier_for) { |type, _id| 'free' if type == 'user' }
        allow(tier_resolver).to receive(:namespace_tier_for).and_return('free')
        allow(target_namespace).to receive_messages(id_for_path: '9970', id_for_project: '9970', id_for_group: '9970')
      end

      # The point of the separate fact flag: the facts are observable before any
      # throttle flag moves, so no rule can match on them yet.
      context 'when every plan flag is off' do
        it 'still emits the plan facts, with every rule gate false', :aggregate_failures do
          facts = request.labkit_facts

          expect(facts).to include(
            requester_plan: 'free',
            target_namespace_plan: 'free',
            target_root_namespace_id: '9970'
          )
          expect(facts[:plan_limits_free_info]).to be(false)
          expect(facts[:plan_limits_free_enforce]).to be(false)
        end
      end

      context 'when not on GitLab.com' do
        before do
          stub_saas_features(gitlab_com_subscriptions: false)
          stub_feature_flags(rate_limiter_plan_limits_free_info: true)
        end

        it 'reads no flag and emits no plan fact', :aggregate_failures do
          expect(::Feature).not_to receive(:enabled?)
            .with(:rate_limiter_plan_limits_free_info, anything, anything)

          facts = request.labkit_facts

          expect(facts).not_to have_key(:requester_plan)
          expect(facts).not_to have_key(:target_namespace_plan)
          expect(facts).not_to have_key(:target_root_namespace_id)
        end
      end

      context 'with the Free info flag on' do
        before do
          stub_feature_flags(rate_limiter_plan_limits_free_info: true)
        end

        it 'emits the plan as a String and the flag facts as strict booleans', :aggregate_failures do
          facts = request.labkit_facts

          expect(facts).to include(
            requester_plan: 'free',
            target_namespace_plan: 'free',
            target_root_namespace_id: '9970'
          )
          expect(facts[:plan_limits_free_info]).to be(true)
          expect(facts[:plan_limits_free_enforce]).to be(false)
        end

        it 'resolves the user tier from the requester type and id' do
          request.labkit_facts

          expect(tier_resolver).to have_received(:tier_for).with('user', '42').once
        end

        it 'derives the namespace from the raw path, leaving the root prefix to TargetKey' do
          allow(Gitlab.config.gitlab).to receive(:relative_url_root).and_return('/gitlab')
          request = request_with(path: '/gitlab/gitlab-org/gitlab/-/issues/1', requester: user)

          request.labkit_facts

          expect(target_namespace).to have_received(:id_for_path).with('/gitlab/gitlab-org/gitlab/-/issues/1')
        end

        it 'derives the namespace without reading params directly' do
          expect(request).not_to receive(:params)

          expect(request.send(:target_root_namespace_id)).to eq('9970')
        end

        it 'emits a plan whose own info flag is off, leaving that gate to the rules' do
          allow(tier_resolver).to receive_messages(tier_for: 'premium', namespace_tier_for: 'premium')

          expect(request.labkit_facts).to include(
            requester_plan: 'premium',
            target_namespace_plan: 'premium'
          )
        end

        # The target describes what the request addresses, so an anonymous request resolves
        # it the same way as a signed-in one. Which rule applies is left to the matchers.
        context 'with an anonymous request' do
          before do
            allow(tier_resolver).to receive(:namespace_tier_for).with('9970').and_return('premium')
          end

          def anonymous_request(path, method: 'GET')
            request = described_class.new(Rack::MockRequest.env_for(path, method: method))
            authenticator = instance_double(Gitlab::Auth::RequestAuthenticator,
              find_authenticated_requester: nil, runner: nil, job_from_token: nil)
            allow(request).to receive(:request_authenticator).and_return(authenticator)
            request
          end

          where(:case_name, :path, :method) do
            'a page load'    | '/acme-corp/project/-/merge_requests/1' | 'GET'
            'an API request' | '/api/v4/projects/acme-corp%2Fproject'  | 'GET'
            'a POST'         | '/acme-corp/project'                    | 'POST'
          end

          with_them do
            it 'resolves the namespace and its plan, but no requester plan', :aggregate_failures do
              facts = anonymous_request(path, method: method).labkit_facts

              expect(facts).to include(
                requester_plan: nil,
                target_namespace_plan: 'premium',
                target_root_namespace_id: '9970'
              )
              expect(tier_resolver).not_to have_received(:tier_for)
              expect(target_namespace).to have_received(:id_for_path).with(path)
            end
          end

          it 'resolves no plan when the path names no namespace' do
            allow(target_namespace).to receive(:id_for_path).and_return(nil)

            expect(anonymous_request('/-/readiness').labkit_facts)
              .to include(target_namespace_plan: nil, target_root_namespace_id: nil)
          end
        end

        context 'with a CI job token' do
          let(:job) { instance_double(Ci::Build, project_id: 7) }
          let(:request) { request_with(path: path, requester: user, job: job) }

          # The job's own project no longer feeds the namespace fact: a job token can
          # reach another namespace through the allowlist, so the fact follows the path.
          it 'resolves the plan from the job user and the namespace from the path', :aggregate_failures do
            facts = request.labkit_facts

            expect(facts).to include(
              requester_plan: 'free',
              target_namespace_plan: 'free',
              target_root_namespace_id: '9970'
            )
            expect(target_namespace).to have_received(:id_for_path).with(path)
            expect(target_namespace).not_to have_received(:id_for_project)
          end

          it 'asks TierResolver for the job user, not the job project' do
            request.labkit_facts

            expect(tier_resolver).to have_received(:tier_for).with('user', '42')
          end
        end

        # A runner token sets runner_id and no requester, so it reaches none of the
        # plan resolution. Runners fetch jobs and must not be limited here.
        context 'with a runner token' do
          it 'emits no plan and resolves no tier', :aggregate_failures do
            request = request_with(path: path)

            expect(tier_resolver).not_to receive(:tier_for)

            expect(request.labkit_facts).to include(requester_plan: nil)
          end
        end

        context 'with a deploy token' do
          let(:token) { instance_double(DeployToken, id: 5, project_id: 7, group_id: nil) }
          let(:request) { request_with(path: path, requester: token) }

          before do
            allow(token).to receive(:is_a?) { |klass| klass == DeployToken }
            # Distinct ids so neither fact can pass by sharing one source: the token
            # belongs to 5555, the path addresses 9970.
            allow(target_namespace).to receive(:id_for_project).with(7).and_return('5555')
            allow(tier_resolver).to receive(:namespace_tier_for).with('5555').and_return('premium')
            allow(tier_resolver).to receive(:namespace_tier_for).with('9970').and_return('free')
          end

          it 'takes its own plan from the namespace it belongs to, not the path', :aggregate_failures do
            facts = request.labkit_facts

            expect(facts).to include(
              requester_plan: 'premium',
              target_namespace_plan: 'free',
              target_root_namespace_id: '9970'
            )
          end

          # TierResolver is never asked for a user tier: it would have to reload the
          # token to reach the namespace the token already carries.
          it 'reads each namespace from its own source', :aggregate_failures do
            request.labkit_facts

            expect(tier_resolver).not_to have_received(:tier_for)
            expect(target_namespace).to have_received(:id_for_project).with(7)
            expect(target_namespace).to have_received(:id_for_path).with(path)
          end

          it 'derives its own namespace from the token group when it has no project' do
            allow(token).to receive_messages(project_id: nil, group_id: 9970)

            request.labkit_facts

            expect(target_namespace).to have_received(:id_for_group).with(9970)
          end
        end

        # Only requester_plan reads it, and only for a deploy token, so the guard
        # is unreachable through labkit_facts. Held so a future caller cannot load
        # a token that is not there.
        it 'resolves no requester namespace for a user' do
          expect(request.send(:requester_root_namespace_id)).to be_nil
        end
      end

      # One fact per flag, uncoupled: each reports its own flag and nothing
      # combines them. A rule that wants info-gates-enforce says so in its match.
      # The plan facts are independent of all four: they answer what the requester
      # and the target are, not what any throttle is doing about it.
      describe 'the flag facts' do
        where(:info, :enforce) do
          false | false
          true  | false
          false | true
          true  | true
        end

        with_them do
          it 'reports each flag as it is, and the plan whatever they say', :aggregate_failures do
            stub_feature_flags(
              rate_limiter_plan_limits_free_info: info,
              rate_limiter_plan_limits_free_enforce: enforce
            )

            facts = request.labkit_facts

            expect(facts).to include(requester_plan: 'free', target_namespace_plan: 'free')
            expect(facts[:plan_limits_free_info]).to be(info)
            expect(facts[:plan_limits_free_enforce]).to be(enforce)
          end
        end

        it 'emits a fact for every tier whatever the flags say', :aggregate_failures do
          facts = request.labkit_facts

          ::GitlabSubscriptions::SystemDefined::Plan::TIERS.each do |tier|
            expect(facts).to have_key(:"plan_limits_#{tier}_info"), tier
            expect(facts).to have_key(:"plan_limits_#{tier}_enforce"), tier
          end
        end

        it 'emits the MCP facts on an MCP path only', :aggregate_failures do
          stub_feature_flags(rate_limiter_mcp_limits_free_info: true, rate_limiter_mcp_sustained_limits_free_info: true)

          mcp = request_with(path: '/api/v4/mcp', requester: user).labkit_facts
          other = request.labkit_facts

          expect(mcp[:mcp_limits_free_info]).to be(true)
          expect(mcp[:mcp_limits_free_enforce]).to be(false)
          expect(mcp[:mcp_sustained_limits_free_info]).to be(true)
          expect(mcp[:mcp_sustained_limits_free_enforce]).to be(false)

          ::GitlabSubscriptions::SystemDefined::Plan::TIERS.product(%w[mcp_limits mcp_sustained_limits])
            .each do |tier, family|
            expect(mcp).to have_key(:"#{family}_#{tier}_info"), tier
            expect(mcp).to have_key(:"#{family}_#{tier}_enforce"), tier
            expect(other).not_to have_key(:"#{family}_#{tier}_info"), tier
            expect(other).not_to have_key(:"#{family}_#{tier}_enforce"), tier
          end
        end

        it 'no longer emits the combined enforced facts', :aggregate_failures do
          facts = request.labkit_facts

          expect(facts).not_to have_key(:user_plan_enforced)
          expect(facts).not_to have_key(:namespace_plan_enforced)
        end
      end
    end
  end
end
