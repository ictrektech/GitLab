# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::RateLimit::PlanRules, feature_category: :rate_limiting do
  using RSpec::Parameterized::TableSyntax

  describe '.flags' do
    it 'is every flag the rules match on' do
      expect(described_class.flags).to contain_exactly(
        :rate_limiter_plan_limits_free_info,
        :rate_limiter_plan_limits_free_enforce,
        :rate_limiter_plan_limits_premium_info,
        :rate_limiter_plan_limits_premium_enforce,
        :rate_limiter_plan_limits_ultimate_info,
        :rate_limiter_plan_limits_ultimate_enforce,
        :rate_limiter_unauthenticated_limits_info,
        :rate_limiter_unauthenticated_limits_enforce,
        :rate_limiter_mcp_limits_free_info,
        :rate_limiter_mcp_limits_free_enforce,
        :rate_limiter_mcp_limits_premium_info,
        :rate_limiter_mcp_limits_premium_enforce,
        :rate_limiter_mcp_limits_ultimate_info,
        :rate_limiter_mcp_limits_ultimate_enforce,
        :rate_limiter_mcp_sustained_limits_free_info,
        :rate_limiter_mcp_sustained_limits_free_enforce,
        :rate_limiter_mcp_sustained_limits_premium_info,
        :rate_limiter_mcp_sustained_limits_premium_enforce,
        :rate_limiter_mcp_sustained_limits_ultimate_info,
        :rate_limiter_mcp_sustained_limits_ultimate_enforce,
        :rate_limiter_expired_oauth_token_per_token,
        :rate_limiter_expired_oauth_token_per_token_enforce
      )
    end

    # An unmatched name silently leaves the real flag on across the suite.
    it 'names only flags with a definition' do
      described_class.flags.each do |flag|
        expect(Feature::Definition.get(flag)).to be_present, "#{flag} has no definition file"
      end
    end
  end

  describe '.active?' do
    # Their rules also need rate_limiter_unauthenticated_limits_info, so on their own they cannot change a result.
    # A local, not a let, so the example loop below can read it when the file loads.
    dependent_flags = %i[rate_limiter_expired_oauth_token_per_token rate_limiter_expired_oauth_token_per_token_enforce]

    context 'on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'is false while every flag is off' do
        expect(described_class.active?).to be(false)
      end

      # Driven off .flags so a flag added there without a matching read fails here.
      (described_class.flags - dependent_flags).each do |flag|
        it "is true when #{flag} alone is on" do
          stub_feature_flags(flag => true)

          expect(described_class.active?).to be(true)
        end
      end

      it 'is false when only the expired OAuth token flags are on' do
        stub_feature_flags(dependent_flags.index_with(true))

        expect(described_class.active?).to be(false)
      end

      it 'reflects a flag flip rather than memoizing' do
        expect(described_class.active?).to be(false)

        stub_feature_flags(rate_limiter_plan_limits_free_info: true)

        expect(described_class.active?).to be(true)
      end

      it 'reads every flag with the request as actor and the derisk type' do
        allow(::Feature).to receive(:enabled?).and_return(false)

        described_class.active?

        (described_class.flags - dependent_flags).each do |flag|
          expect(::Feature).to have_received(:enabled?)
            .with(flag, ::Feature.current_request, type: :gitlab_com_derisk)
        end
      end
    end

    context 'when not on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        stub_feature_flags(described_class.flags.index_with(true))
      end

      it 'is false even with every flag on' do
        expect(described_class.active?).to be(false)
      end

      it 'rules the limits out before reading any flag' do
        expect(::Feature).not_to receive(:enabled?)

        described_class.active?
      end
    end
  end

  describe '.concealed_rules' do
    let(:rules) { described_class::RULES.index_by(&:name) }

    it 'names :limit rules that share one period, so Retry-After cannot tell them apart', :aggregate_failures do
      concealed = described_class.concealed_rules.keys.map { |name| rules.fetch(name) }

      expect(concealed.map(&:action)).to all(eq(:limit))
      expect(concealed.map(&:period).uniq.size).to eq(1)
    end

    it 'gives every rule in a group the same header name' do
      expect(described_class.concealed_rules.values.uniq).to eq(['unauthenticated_traffic_per_ip'])
    end
  end

  describe '.for_limiter' do
    let(:general) { ::Gitlab::RackAttack::LabkitRateLimit::ThrottleRegistry::GENERAL }
    let(:protected_paths) { ::Gitlab::RackAttack::LabkitRateLimit::ThrottleRegistry::PROTECTED }
    let(:mcp) { ::Gitlab::RackAttack::LabkitRateLimit::ThrottleRegistry::MCP }

    # Spelled out rather than interpolated so every rule name is greppable.
    let(:expected_names) do
      %w[
        sustained_slack_app_traffic_per_ip
        sustained_slack_app_traffic_per_ip_log
        burst_slack_app_traffic_per_ip
        burst_slack_app_traffic_per_ip_log

        expired_oauth_token_traffic_per_token
        expired_oauth_token_traffic_per_token_log
        expired_oauth_token_traffic_per_ip
        expired_oauth_token_traffic_per_ip_log

        unauthenticated_traffic_per_ip
        unauthenticated_traffic_per_ip_log
        unauthenticated_paid_namespace_traffic_per_ip
        unauthenticated_paid_namespace_traffic_per_ip_log

        sustained_mcp_traffic_per_user_free_plan
        sustained_mcp_traffic_per_user_free_plan_log
        burst_mcp_traffic_per_user_free_plan
        burst_mcp_traffic_per_user_free_plan_log

        sustained_mcp_traffic_per_user_premium_plan
        sustained_mcp_traffic_per_user_premium_plan_log
        burst_mcp_traffic_per_user_premium_plan
        burst_mcp_traffic_per_user_premium_plan_log

        sustained_mcp_traffic_per_user_ultimate_plan
        sustained_mcp_traffic_per_user_ultimate_plan_log
        burst_mcp_traffic_per_user_ultimate_plan
        burst_mcp_traffic_per_user_ultimate_plan_log

        sustained_traffic_per_user_free_plan
        sustained_traffic_per_user_free_plan_log
        burst_traffic_per_user_free_plan
        burst_traffic_per_user_free_plan_log
        burst_git_and_dependency_proxy_traffic_per_user_free_plan
        burst_git_and_dependency_proxy_traffic_per_user_free_plan_log
        burst_web_traffic_per_user_free_plan
        burst_web_traffic_per_user_free_plan_log
        burst_upload_and_pwa_manifest_traffic_per_user_free_plan
        burst_upload_and_pwa_manifest_traffic_per_user_free_plan_log

        sustained_traffic_per_user_premium_plan
        sustained_traffic_per_user_premium_plan_log
        burst_traffic_per_user_premium_plan
        burst_traffic_per_user_premium_plan_log

        sustained_traffic_per_user_ultimate_plan
        sustained_traffic_per_user_ultimate_plan_log
        burst_traffic_per_user_ultimate_plan
        burst_traffic_per_user_ultimate_plan_log
      ]
    end

    def rule(name)
      described_class.for_limiter(general).find { |candidate| candidate.name == name } ||
        raise("no rule named #{name}")
    end

    context 'on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'returns every rule in the design document order' do
        expect(described_class.for_limiter(general).map(&:name)).to eq(expected_names)
      end

      it 'counts every enforcing plan rule by requester, never by namespace', :aggregate_failures do
        enforcing = (described_class::PLAN_RULES + described_class::MCP_RULES)
                      .select { |rule| rule.action == :limit }

        expect(enforcing).not_to be_empty
        enforcing.each do |rule|
          expect(rule.characteristics).to eq(%i[requester_type requester_id]), rule.name
        end
      end

      it 'is empty for the protected paths limiter' do
        expect(described_class.for_limiter(protected_paths)).to be_empty
      end

      it 'is empty for the MCP limiter' do
        expect(described_class.for_limiter(mcp)).to be_empty
      end

      describe 'the MCP rules' do
        let(:mcp_rules) { described_class.for_limiter(general).select { |r| r.name.include?('_mcp_') } }

        def mcp_rule(name)
          mcp_rules.find { |candidate| candidate.name == name } || raise("no rule named #{name}")
        end

        it 'is an enforcing rule and a log twin per tier' do
          expect(mcp_rules.map(&:name)).to eq(
            %w[
              sustained_mcp_traffic_per_user_free_plan
              sustained_mcp_traffic_per_user_free_plan_log
              burst_mcp_traffic_per_user_free_plan
              burst_mcp_traffic_per_user_free_plan_log
              sustained_mcp_traffic_per_user_premium_plan
              sustained_mcp_traffic_per_user_premium_plan_log
              burst_mcp_traffic_per_user_premium_plan
              burst_mcp_traffic_per_user_premium_plan_log
              sustained_mcp_traffic_per_user_ultimate_plan
              sustained_mcp_traffic_per_user_ultimate_plan_log
              burst_mcp_traffic_per_user_ultimate_plan
              burst_mcp_traffic_per_user_ultimate_plan_log
            ]
          )
        end

        where(:name, :plan, :limit, :period, :action, :enforce, :family) do
          # rubocop:disable Layout/LineLength -- TableSyntax
          'sustained_mcp_traffic_per_user_free_plan'         | 'free'     | 3_600 | 1.hour   | :limit | true  | 'mcp_sustained_limits'
          'sustained_mcp_traffic_per_user_free_plan_log'     | 'free'     | 3_600 | 1.hour   | :log   | false | 'mcp_sustained_limits'
          'burst_mcp_traffic_per_user_free_plan'             | 'free'     | 60    | 1.minute | :limit | true  | 'mcp_limits'
          'burst_mcp_traffic_per_user_free_plan_log'         | 'free'     | 60    | 1.minute | :log   | false | 'mcp_limits'
          'sustained_mcp_traffic_per_user_premium_plan'      | 'premium'  | 5_000 | 1.hour   | :limit | true  | 'mcp_sustained_limits'
          'sustained_mcp_traffic_per_user_premium_plan_log'  | 'premium'  | 5_000 | 1.hour   | :log   | false | 'mcp_sustained_limits'
          'burst_mcp_traffic_per_user_premium_plan'          | 'premium'  | 600   | 1.minute | :limit | true  | 'mcp_limits'
          'burst_mcp_traffic_per_user_premium_plan_log'      | 'premium'  | 600   | 1.minute | :log   | false | 'mcp_limits'
          'sustained_mcp_traffic_per_user_ultimate_plan'     | 'ultimate' | 5_000 | 1.hour   | :limit | true  | 'mcp_sustained_limits'
          'sustained_mcp_traffic_per_user_ultimate_plan_log' | 'ultimate' | 5_000 | 1.hour   | :log   | false | 'mcp_sustained_limits'
          'burst_mcp_traffic_per_user_ultimate_plan'         | 'ultimate' | 600   | 1.minute | :limit | true  | 'mcp_limits'
          'burst_mcp_traffic_per_user_ultimate_plan_log'     | 'ultimate' | 600   | 1.minute | :log   | false | 'mcp_limits'
          # rubocop:enable Layout/LineLength
        end

        with_them do
          it 'is the ceiling for that tier and period, counted per requester',
            :aggregate_failures do
            candidate = mcp_rule(name)

            expect(candidate.action).to eq(action)
            expect(candidate.limit).to eq(limit)
            expect(candidate.period).to eq(period)
            expect(candidate.characteristics).to eq(%i[requester_type requester_id])
            expect(candidate.match[:requester_plan].value).to eq(plan)
          end

          it 'matches only an authenticated request on an MCP path, whatever the setting',
            :aggregate_failures do
            match = mcp_rule(name).match

            expect(match[:requester_id].match?(nil)).to be(false)
            expect(match[:requester_id].match?('42')).to be(true)
            expect(match).not_to have_key(:setting_authenticated_mcp)
            expect(match[:path].match?('/api/v4/mcp')).to be(true)
            expect(match[:path].match?('/api/v4/projects')).to be(false)
          end

          it 'pairs the info gate with its own enforce state', :aggregate_failures do
            match = mcp_rule(name).match

            expect(match[:"#{family}_#{plan}_info"].match?(true)).to be(true)
            expect(match[:"#{family}_#{plan}_info"].match?(false)).to be(false)
            expect(match[:"#{family}_#{plan}_enforce"].match?(enforce)).to be(true)
            expect(match[:"#{family}_#{plan}_enforce"].match?(!enforce)).to be(false)
          end

          it 'is gated only by its own flag family' do
            expect(mcp_rule(name).match.keys.grep(/_limits_/))
              .to contain_exactly(:"#{family}_#{plan}_info", :"#{family}_#{plan}_enforce")
          end
        end
      end

      it 'ends every :log rule name with _log and nothing else', :aggregate_failures do
        described_class.for_limiter(general).each do |candidate|
          expect(candidate.name.end_with?('_log')).to be(candidate.action == :log), candidate.name
        end
      end

      describe 'the unauthenticated pair' do
        let(:enforcing) { rule('unauthenticated_traffic_per_ip') }
        let(:logging) { rule('unauthenticated_traffic_per_ip_log') }

        it 'is 60 an hour per IP on both, the published unauthenticated ceiling', :aggregate_failures do
          [enforcing, logging].each do |candidate|
            expect(candidate.limit).to eq(60)
            expect(candidate.period).to eq(1.hour)
            expect(candidate.characteristics).to eq(%i[ip])
          end
        end

        it 'matches only a request with no requester and no runner', :aggregate_failures do
          [enforcing, logging].each do |candidate|
            expect(candidate.match[:requester_id].match?(nil)).to be(true)
            expect(candidate.match[:requester_id].match?('42')).to be(false)
            expect(candidate.match[:runner_id].match?(nil)).to be(true)
            expect(candidate.match[:runner_id].match?('7')).to be(false)
          end
        end

        it 'splits on unauthenticated_enforced', :aggregate_failures do
          expect(enforcing.match[:unauthenticated_enforced].match?(true)).to be(true)
          expect(enforcing.match[:unauthenticated_enforced].match?(false)).to be(false)
          expect(logging.match[:unauthenticated_enforced].match?(false)).to be(true)
          expect(logging.match[:unauthenticated_enforced].match?(true)).to be(false)
        end

        it 'requires unauthenticated_limits_active on both', :aggregate_failures do
          [enforcing, logging].each do |candidate|
            expect(candidate.match[:unauthenticated_limits_active].match?(true)).to be(true)
            expect(candidate.match[:unauthenticated_limits_active].match?(false)).to be(false)
          end
        end

        it 'leaves paid namespaces to the paid namespace pair', :aggregate_failures do
          [enforcing, logging].each do |candidate|
            expect(candidate.match[:target_namespace_plan].match?(nil)).to be(true)
            expect(candidate.match[:target_namespace_plan].match?('free')).to be(true)
            expect(candidate.match[:target_namespace_plan].match?('premium')).to be(false)
            expect(candidate.match[:target_namespace_plan].match?('ultimate')).to be(false)
          end
        end

        it 'excludes the sign-in flow, OAuth token grants, registration and discovery on both, but not token info',
          :aggregate_failures do
          [enforcing, logging].each do |candidate|
            expect(candidate.match[:path].match?('/users/sign_in')).to be(false)
            expect(candidate.match[:path].match?('/oauth/token')).to be(false)
            expect(candidate.match[:path].match?('/oauth/register')).to be(false)
            expect(candidate.match[:path].match?('/.well-known/openid-configuration')).to be(false)
            expect(candidate.match[:path].match?('/.well-known/terraform.json')).to be(false)
            expect(candidate.match[:path].match?('/oauth/token/info')).to be(true)
          end
        end

        it 'excludes Git over HTTPS on both, including info/refs without .git', :aggregate_failures do
          [enforcing, logging].each do |rule|
            expect(rule.match[:path].match?('/group/project.git/info/refs')).to be(false)
            expect(rule.match[:path].match?('/group/project.git/info/lfs/objects/batch')).to be(false)
            expect(rule.match[:path].match?('/group/project/info/refs')).to be(false)
          end
        end

        it 'excludes group SCIM provisioning paths on both', :aggregate_failures do
          [enforcing, logging].each do |rule|
            expect(rule.match[:path].match?('/api/scim/v2/groups/my-group/Users')).to be(false)
          end
        end

        it 'excludes the Jira Connect server routes and the create-branch redirect on both', :aggregate_failures do
          [enforcing, logging].each do |rule|
            expect(rule.match[:path].match?('/-/jira_connect/workspaces/search')).to be(false)
            expect(rule.match[:path].match?('/-/jira_connect/branches/route')).to be(false)
            expect(rule.match[:path].match?('/-/jira_connect/subscriptions')).to be(true)
          end
        end

        it 'excludes the dependency proxy on both, but not virtual registries', :aggregate_failures do
          [enforcing, logging].each do |candidate|
            expect(candidate.match[:path].match?('/v2')).to be(false)
            expect(candidate.match[:path].match?('/v2/group/dependency_proxy/containers/alpine/manifests/latest'))
              .to be(false)
            expect(candidate.match[:path].match?('/v2/virtual_registries/container/1/alpine/manifests/latest'))
              .to be(true)
          end
        end

        it 'excludes Slack app paths on both', :aggregate_failures do
          [enforcing, logging].each do |rule|
            expect(rule.match[:path].match?('/group/project')).to be(true)
            expect(rule.match[:path].match?('/api/v4/slack/trigger')).to be(false)
          end
        end

        it 'excludes Unleash feature flag paths on both', :aggregate_failures do
          [enforcing, logging].each do |rule|
            expect(rule.match[:path].match?('/api/v4/feature_flags/unleash/42/client/features')).to be(false)
          end
        end

        it 'excludes runner registration on both', :aggregate_failures do
          [enforcing, logging].each do |rule|
            expect(rule.match[:path].match?('/api/v4/runners')).to be(false)
            expect(rule.match[:path].match?('/api/v4/runners/verify')).to be(true)
          end
        end

        it 'excludes the pipeline trigger API on both', :aggregate_failures do
          [enforcing, logging].each do |rule|
            expect(rule.match[:path].match?('/api/v4/projects/42/trigger/pipeline')).to be(false)
          end
        end

        it 'excludes the deprecated secure files installers on both', :aggregate_failures do
          installer = '/gitlab-org/incubation-engineering/mobile-devops/download-secure-files/-/raw/main/installer'

          [enforcing, logging].each do |rule|
            expect(rule.match[:path].match?(installer)).to be(false)
          end
        end

        it 'excludes alert notifications and Mailgun webhooks on both', :aggregate_failures do
          [enforcing, logging].each do |rule|
            expect(rule.match[:path].match?('/group/project/alerts/notify')).to be(false)
            expect(rule.match[:path].match?('/-/mailgun/webhooks')).to be(false)
          end
        end

        it 'excludes the HAProxy api health check on both', :aggregate_failures do
          [enforcing, logging].each do |rule|
            expect(rule.match[:path].match?('/-/k8s/api/-/readiness')).to be(false)
          end
        end
      end

      describe 'the expired OAuth token rules' do
        let(:per_token) { described_class::EXPIRED_OAUTH_TOKEN_RULES.first(2) }
        let(:per_ip) { described_class::EXPIRED_OAUTH_TOKEN_RULES.last(2) }

        it 'is 60 an hour per expired token, then 1,200 an hour per IP', :aggregate_failures do
          expect(per_token.map(&:name))
            .to eq(%w[expired_oauth_token_traffic_per_token expired_oauth_token_traffic_per_token_log])
          expect(per_ip.map(&:name))
            .to eq(%w[expired_oauth_token_traffic_per_ip expired_oauth_token_traffic_per_ip_log])

          per_token.each do |candidate|
            expect(candidate.limit).to eq(60)
            expect(candidate.period).to eq(1.hour)
            expect(candidate.characteristics).to eq(%i[expired_oauth_token_id])
          end

          per_ip.each do |candidate|
            expect(candidate.limit).to eq(1_200)
            expect(candidate.period).to eq(1.hour)
            expect(candidate.characteristics).to eq(%i[ip])
          end
        end

        it 'matches only a request with an expired token and no requester or runner', :aggregate_failures do
          (per_token + per_ip).each do |candidate|
            expect(candidate.match[:expired_oauth_token_id].match?('OauthAccessToken/7')).to be(true)
            expect(candidate.match[:expired_oauth_token_id].match?(nil)).to be(false)
            expect(candidate.match[:requester_id].match?('42')).to be(false)
            expect(candidate.match[:runner_id].match?('7')).to be(false)
          end
        end

        it 'splits each pair on expired_oauth_token_enforced behind unauthenticated_limits_active',
          :aggregate_failures do
          [per_token, per_ip].each do |(enforcing, logging)|
            expect(enforcing.match[:expired_oauth_token_enforced].match?(true)).to be(true)
            expect(enforcing.match[:expired_oauth_token_enforced].match?(false)).to be(false)
            expect(logging.match[:expired_oauth_token_enforced].match?(false)).to be(true)
            expect(logging.match[:expired_oauth_token_enforced].match?(true)).to be(false)
          end

          (per_token + per_ip).each do |candidate|
            expect(candidate.match[:unauthenticated_limits_active].match?(false)).to be(false)
          end
        end

        it 'covers the same paths as the unauthenticated pair', :aggregate_failures do
          (per_token + per_ip).each do |candidate|
            expect(candidate.match[:path].match?('/oauth/token/info')).to be(true)
            expect(candidate.match[:path].match?('/api/v4/ai/third_party_agents/direct_access')).to be(true)
            expect(candidate.match[:path].match?('/oauth/token')).to be(false)
          end
        end

        it 'leaves the request out of every per-IP unauthenticated rule only once these enforce',
          :aggregate_failures do
          described_class::UNAUTHENTICATED_RULES.each do |candidate|
            expect(candidate.match[:expired_oauth_token_enforced].match?(true)).to be(false), candidate.name
            expect(candidate.match[:expired_oauth_token_enforced].match?(false)).to be(true), candidate.name
          end
        end

        context 'when evaluated against a request' do
          let(:expired) { { expired_oauth_token_id: 'OauthAccessToken/7' } }

          before do
            stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
          end

          it 'counts a request without an expired token per IP only' do
            expect(matching_rule_names('/oauth/token/info')).to eq(%w[unauthenticated_traffic_per_ip_log])
          end

          it 'observes an expired token alongside the per-IP rule while nothing enforces' do
            expect(matching_rule_names('/oauth/token/info', **expired, expired_oauth_token_enforced: false))
              .to eq(%w[expired_oauth_token_traffic_per_token_log expired_oauth_token_traffic_per_ip_log
                unauthenticated_traffic_per_ip_log])
          end

          it 'keeps an observed expired token under the enforcing per-IP rule' do
            stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)

            expect(matching_rule_names('/oauth/token/info', **expired, expired_oauth_token_enforced: false))
              .to eq(%w[expired_oauth_token_traffic_per_token_log expired_oauth_token_traffic_per_ip_log
                unauthenticated_traffic_per_ip])
          end

          it 'moves an expired token to the enforcing per-token and per-IP rules once they enforce' do
            stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)

            expect(matching_rule_names('/oauth/token/info', **expired, expired_oauth_token_enforced: true))
              .to eq(%w[expired_oauth_token_traffic_per_token expired_oauth_token_traffic_per_ip])
          end
        end
      end

      describe 'the paid namespace pair' do
        let(:enforcing) { rule('unauthenticated_paid_namespace_traffic_per_ip') }
        let(:logging) { rule('unauthenticated_paid_namespace_traffic_per_ip_log') }

        it 'is 10,000 an hour per IP on both, across all paid namespaces', :aggregate_failures do
          [enforcing, logging].each do |candidate|
            expect(candidate.limit).to eq(10_000)
            expect(candidate.period).to eq(1.hour)
            expect(candidate.characteristics).to eq(%i[ip])
            expect(candidate.count_distinct).to be_nil
          end
        end

        it 'matches only Premium and Ultimate namespaces', :aggregate_failures do
          [enforcing, logging].each do |candidate|
            expect(candidate.match[:target_namespace_plan].match?('premium')).to be(true)
            expect(candidate.match[:target_namespace_plan].match?('ultimate')).to be(true)
            expect(candidate.match[:target_namespace_plan].match?('free')).to be(false)
            expect(candidate.match[:target_namespace_plan].match?(nil)).to be(false)
          end
        end

        it 'matches only a request with no requester and no runner', :aggregate_failures do
          [enforcing, logging].each do |candidate|
            expect(candidate.match[:requester_id].match?(nil)).to be(true)
            expect(candidate.match[:requester_id].match?('42')).to be(false)
            expect(candidate.match[:runner_id].match?(nil)).to be(true)
            expect(candidate.match[:runner_id].match?('7')).to be(false)
          end
        end

        it 'splits on unauthenticated_enforced behind unauthenticated_limits_active', :aggregate_failures do
          expect(enforcing.match[:unauthenticated_enforced].match?(true)).to be(true)
          expect(logging.match[:unauthenticated_enforced].match?(false)).to be(true)

          [enforcing, logging].each do |candidate|
            expect(candidate.match[:unauthenticated_limits_active].match?(false)).to be(false)
          end
        end
      end

      describe 'the Slack app rules' do
        where(:kind, :limit, :period) do
          'sustained' | 1_000 | 1.hour
          'burst'     | 100   | 1.minute
        end

        with_them do
          let(:enforcing) { rule("#{kind}_slack_app_traffic_per_ip") }
          let(:logging) { rule("#{kind}_slack_app_traffic_per_ip_log") }

          it 'counts per IP at the agreed budget', :aggregate_failures do
            [enforcing, logging].each do |candidate|
              expect(candidate.limit).to eq(limit), candidate.name
              expect(candidate.period).to eq(period), candidate.name
              expect(candidate.characteristics).to eq(%i[ip]), candidate.name
            end
          end

          it 'splits on the same enforce flag as the unauthenticated pair', :aggregate_failures do
            expect(enforcing.match[:unauthenticated_enforced].match?(true)).to be(true)
            expect(logging.match[:unauthenticated_enforced].match?(false)).to be(true)
          end
        end
      end

      # The matchers above only prove the gate is declared. These evaluate the rules
      # against the facts a real request carries, the way Labkit's evaluator does.
      def matching_rule_names(path, method: 'GET', **requester_facts)
        facts = ::Gitlab::RackAttack::LabkitRateLimit::ClassifiedRequest
                  .new(Rack::MockRequest.env_for(path, method: method)).labkit_facts.merge(requester_facts)

        described_class.for_limiter(general)
          .select { |rule| rule.match.all? { |key, matcher| matcher.match?(facts[key]) } }
          .map(&:name)
      end

      describe 'the Slack app exclusion' do
        before do
          stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
        end

        where(:path) do
          %w[
            /api/v4/slack/trigger
            /api/v4/integrations/slack/events
            /api/v4/integrations/slack/interactions
            /api/v4/integrations/slack/options
          ]
        end

        with_them do
          it 'counts under the Slack rules instead of the unauthenticated pair' do
            expect(matching_rule_names(path, method: 'POST')).to eq(
              %w[sustained_slack_app_traffic_per_ip_log burst_slack_app_traffic_per_ip_log]
            )
          end
        end

        it 'leaves a non-Slack integrations path to the unauthenticated pair' do
          expect(matching_rule_names('/api/v4/integrations/jira_connect/subscriptions'))
            .to eq(%w[unauthenticated_traffic_per_ip_log])
        end

        context 'when enforcing' do
          before do
            stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
          end

          it 'counts a Slack path under the enforcing Slack rules only' do
            expect(matching_rule_names('/api/v4/slack/trigger', method: 'POST'))
              .to eq(%w[sustained_slack_app_traffic_per_ip burst_slack_app_traffic_per_ip])
          end

          it 'still counts a non-Slack path under the enforcing unauthenticated rule' do
            expect(matching_rule_names('/api/v4/integrations/jira_connect/subscriptions'))
              .to eq(%w[unauthenticated_traffic_per_ip])
          end
        end
      end

      describe 'the runner registration exclusion' do
        before do
          stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
        end

        where(:path) do
          %w[/api/v4/runners /api/v4/runners.json]
        end

        with_them do
          it 'leaves a registration token request to the existing unauthenticated_api throttle' do
            expect(matching_rule_names(path, method: 'POST')).to be_empty
          end

          context 'when enforcing' do
            before do
              stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
            end

            it 'still leaves the request out of every rule' do
              expect(matching_rule_names(path, method: 'POST')).to be_empty
            end
          end
        end

        it 'still counts an unresolved runner token on verify under the unauthenticated pair' do
          expect(matching_rule_names('/api/v4/runners/verify', method: 'POST'))
            .to eq(%w[unauthenticated_traffic_per_ip_log])
        end
      end

      describe 'the pipeline trigger exclusion' do
        before do
          stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
        end

        where(:path) do
          %w[
            /api/v4/projects/42/trigger/pipeline
            /api/v4/projects/group%2Fproject/trigger/pipeline
            /api/v4/projects/42/ref/main/trigger/pipeline
            /api/v4/projects/42/trigger/pipeline?token=glptt-abc&ref=main
          ]
        end

        with_them do
          it 'leaves a trigger token request to the existing unauthenticated_api throttle' do
            expect(matching_rule_names(path, method: 'POST')).to be_empty
          end

          context 'when enforcing' do
            before do
              stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
            end

            it 'still leaves the request out of every rule' do
              expect(matching_rule_names(path, method: 'POST')).to be_empty
            end
          end
        end

        it 'still counts the neighbouring triggers API under the unauthenticated pair' do
          expect(matching_rule_names('/api/v4/projects/42/triggers'))
            .to eq(%w[unauthenticated_traffic_per_ip_log])
        end

        it 'still counts a CI_JOB_TOKEN trigger under the job user plan rules' do
          stub_feature_flags(rate_limiter_plan_limits_free_info: true)

          expect(matching_rule_names('/api/v4/projects/42/trigger/pipeline', method: 'POST',
            requester_type: 'user', requester_id: '42', requester_plan: 'free'))
            .to eq(%w[sustained_traffic_per_user_free_plan_log burst_traffic_per_user_free_plan_log])
        end
      end

      describe 'the alert notification and Mailgun webhook exclusion' do
        before do
          stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
        end

        where(:path) do
          %w[
            /group/project/alerts/notify
            /group/project/alerts/notify.json
            /group/project/alerts/notify/my-integration/a1b2c3d4e5f6
            /group/project/prometheus/alerts/notify
            /-/mailgun/webhooks
            /-/members/mailgun/permanent_failures
          ]
        end

        with_them do
          it 'leaves the request out of every rule' do
            expect(matching_rule_names(path, method: 'POST')).to be_empty
          end

          context 'when enforcing' do
            before do
              stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
            end

            it 'still leaves the request out of every rule' do
              expect(matching_rule_names(path, method: 'POST')).to be_empty
            end
          end
        end

        it 'still counts a blob page whose path ends in alerts/notify under the unauthenticated pair' do
          expect(matching_rule_names('/group/project/-/blob/main/alerts/notify'))
            .to eq(%w[unauthenticated_traffic_per_ip_log])
        end
      end

      describe 'the HAProxy api health check exclusion' do
        before do
          stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
        end

        it 'leaves the request out of every rule' do
          expect(matching_rule_names('/-/k8s/api/-/readiness')).to be_empty
        end

        context 'when enforcing' do
          before do
            stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
          end

          it 'still leaves the request out of every rule' do
            expect(matching_rule_names('/-/k8s/api/-/readiness')).to be_empty
          end
        end

        it 'still counts another path under /-/k8s/api under the unauthenticated pair' do
          expect(matching_rule_names('/-/k8s/api/-/liveness')).to eq(%w[unauthenticated_traffic_per_ip_log])
        end
      end

      describe 'the Unleash feature flag exclusion' do
        before do
          stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
        end

        where(:method, :path) do
          'GET'  | '/api/v4/feature_flags/unleash/42'
          'GET'  | '/api/v4/feature_flags/unleash/42/features'
          'GET'  | '/api/v4/feature_flags/unleash/42/client/features'
          'POST' | '/api/v4/feature_flags/unleash/42/client/register'
          'POST' | '/api/v4/feature_flags/unleash/42/client/metrics'
        end

        with_them do
          it 'leaves the request to the existing unauthenticated_api throttle' do
            expect(matching_rule_names(path, method: method)).to be_empty
          end

          context 'when enforcing' do
            before do
              stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
            end

            it 'still leaves the request out of every rule' do
              expect(matching_rule_names(path, method: method)).to be_empty
            end
          end
        end

        it 'leaves a poll carrying the instance ID in the query string out of every rule' do
          expect(matching_rule_names('/api/v4/feature_flags/unleash/42/client/features?instance_id=abc&app_name=prod'))
            .to be_empty
        end

        it 'still counts a neighbouring feature flags path under the unauthenticated pair' do
          expect(matching_rule_names('/api/v4/projects/42/feature_flags'))
            .to eq(%w[unauthenticated_traffic_per_ip_log])
        end

        it 'still counts the bare unleash path, which is not a route' do
          expect(matching_rule_names('/api/v4/feature_flags/unleash'))
            .to eq(%w[unauthenticated_traffic_per_ip_log])
        end
      end

      describe 'the group SCIM provisioning exclusion' do
        before do
          stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
        end

        where(:method, :path) do
          'GET'    | '/api/scim/v2/groups/my-group/Users'
          'GET'    | '/api/scim/v2/groups/my-group/Users?filter=userName%20eq%20%22jane%22'
          'GET'    | '/api/scim/v2/groups/my-group/Users/42'
          'POST'   | '/api/scim/v2/groups/my-group/Users'
          'PATCH'  | '/api/scim/v2/groups/my-group/Users/42'
          'DELETE' | '/api/scim/v2/groups/my-group/Users/42'
        end

        with_them do
          it 'leaves the request out of every rule' do
            expect(matching_rule_names(path, method: method)).to be_empty
          end

          context 'when enforcing' do
            before do
              stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
            end

            it 'still leaves the request out of every rule' do
              expect(matching_rule_names(path, method: method)).to be_empty
            end
          end
        end

        it 'still counts a non-SCIM group API path under the unauthenticated pair' do
          expect(matching_rule_names('/api/v4/groups/my-group'))
            .to eq(%w[unauthenticated_traffic_per_ip_log])
        end

        it 'still counts an authenticated user on a SCIM path under the plan rules' do
          stub_feature_flags(rate_limiter_plan_limits_free_info: true)

          expect(matching_rule_names('/api/scim/v2/groups/my-group/Users',
            requester_type: 'user', requester_id: '42', requester_plan: 'free'))
            .to eq(%w[sustained_traffic_per_user_free_plan_log burst_traffic_per_user_free_plan_log])
        end
      end

      describe 'the Jira Connect exclusion' do
        before do
          stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
        end

        where(:method, :path) do
          'GET'  | '/-/jira_connect/workspaces/search?searchQuery=gitlab&page=1&limit=10'
          'GET'  | '/-/jira_connect/repositories/search?searchQuery=gitlab&workspaceId=42'
          'POST' | '/-/jira_connect/repositories/associate'
          'POST' | '/o/my-org/-/jira_connect/repositories/associate'
          'GET'  | '/-/jira_connect/branches/route?issue_key=GL-1&issue_summary=Fix&jwt=token&addonkey=gitlab-jira'
          'GET'  | '/o/my-org/-/jira_connect/branches/route?issue_key=GL-1&jwt=token'
        end

        with_them do
          it 'leaves the request out of every rule' do
            expect(matching_rule_names(path, method: method)).to be_empty
          end

          context 'when enforcing' do
            before do
              stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
            end

            it 'still leaves the request out of every rule' do
              expect(matching_rule_names(path, method: method)).to be_empty
            end
          end
        end

        context 'on a lifecycle event or a browser-facing Jira Connect page' do
          where(:method, :path) do
            'POST' | '/-/jira_connect/events/installed'
            'POST' | '/-/jira_connect/events/uninstalled'
            'GET'  | '/-/jira_connect/subscriptions'
            'GET'  | '/-/jira_connect/oauth_callbacks'
            'GET'  | '/-/jira_connect/branches/new'
          end

          with_them do
            it 'still counts the request under the unauthenticated pair' do
              expect(matching_rule_names(path, method: method)).to eq(%w[unauthenticated_traffic_per_ip_log])
            end
          end
        end
      end

      describe 'the dependency proxy exclusion' do
        before do
          stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
        end

        where(:method, :path) do
          'GET'  | '/v2'
          'GET'  | '/v2/group/dependency_proxy/containers/alpine/manifests/latest'
          'GET'  | '/v2/group/sub/dependency_proxy/containers/alpine/blobs/sha256:abc123'
          'POST' | '/v2/group/dependency_proxy/containers/alpine/blobs/sha256:abc123/upload/authorize'
          'POST' | '/v2/group/dependency_proxy/containers/alpine/manifests/latest/upload'
        end

        with_them do
          it 'leaves an anonymous request, such as a 401 challenge, out of every rule' do
            expect(matching_rule_names(path, method: method)).to be_empty
          end

          context 'when enforcing' do
            before do
              stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
            end

            it 'still leaves the request out of every rule' do
              expect(matching_rule_names(path, method: method)).to be_empty
            end
          end
        end

        it 'still counts a deploy token pull under the plan rules' do
          stub_feature_flags(rate_limiter_plan_limits_free_info: true)

          expect(matching_rule_names('/v2/group/dependency_proxy/containers/alpine/manifests/latest',
            requester_type: 'deploy_token', requester_id: '7', requester_plan: 'free'))
            .to eq(%w[
              sustained_traffic_per_user_free_plan_log
              burst_git_and_dependency_proxy_traffic_per_user_free_plan_log
            ])
        end
      end

      describe 'the Git over HTTPS exclusion' do
        before do
          stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
        end

        it 'leaves a git and an LFS request to throttle_unauthenticated_git_http', :aggregate_failures do
          expect(matching_rule_names('/group/project.git/info/refs')).to be_empty
          expect(matching_rule_names('/group/project.git/info/lfs/objects/batch')).to be_empty
        end

        it 'still counts an unauthenticated non-git request' do
          expect(matching_rule_names('/group/project')).to eq(%w[unauthenticated_traffic_per_ip_log])
        end
      end

      describe 'the OAuth and sign-in exclusion' do
        before do
          stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
        end

        where(:method, :path) do
          'GET'     | '/'
          'GET'     | '/users/sign_in'
          'HEAD'    | '/users/sign_in'
          'POST'    | '/users/sign_in'
          'GET'     | '/users/sign_in?redirect_to_referer=yes'
          'GET'     | '/o/my-org/users/sign_in'
          'GET'     | '/groups/my-group/-/saml/sso'
          'GET'     | '/groups/my-group/-/saml/sso?token=abc'
          'POST'    | '/groups/my-group/-/saml/sso'
          'POST'    | '/groups/my-group/-/saml/callback'
          'GET'     | '/oauth/authorize?client_id=abc&redirect_uri=https%3A%2F%2Fexample.com&response_type=code'
          'POST'    | '/oauth/authorize'
          'GET'     | '/o/my-org/oauth/authorize'
          'POST'    | '/oauth/token'
          'POST'    | '/oauth/token.json'
          'OPTIONS' | '/oauth/token'
          'POST'    | '/o/my-org/oauth/token'
          'POST'    | '/oauth/authorize_device'
          'POST'    | '/oauth/register'
          'POST'    | '/oauth/register.json'
          'OPTIONS' | '/oauth/register'
          'POST'    | '/o/my-org/oauth/register'
          'GET'     | '/.well-known/openid-configuration'
          'GET'     | '/.well-known/oauth-authorization-server'
          'GET'     | '/.well-known/oauth-protected-resource/api/v4/mcp'
          'GET'     | '/.well-known/openid-configuration/api/v4/orbit/mcp'
          'GET'     | '/.well-known/terraform.json'
          'GET'     | '/oauth/discovery/keys'
          'GET'     | '/users/sign_up'
          'GET'     | '/users/user.git/exists'
          'GET'     | '/users/identity_verification/verification_state'
          'GET'     | '/users/sign_in_path?login=someone'
          'POST'    | '/users/passkeys/sign_in'
          'POST'    | '/users/resend_verification_code'
          'POST'    | '/users/fallback_to_email_otp'
          'POST'    | '/users/skip_verification_for_now'
          'GET'     | '/users/skip_verification_confirmation'
          'GET'     | '/users/successful_verification'
          'GET'     | '/users/almost_there'
          'GET'     | '/-/subscriptions/payment_form?id=abc'
          'POST'    | '/-/subscriptions/validate_payment_method'
          'GET'     | '/-/invites/AbC_123-xyz'
          'GET'     | '/users/password/new'
          'GET'     | '/users/password/edit?reset_password_token=abc'
          'POST'    | '/users/password'
          'PUT'     | '/users/password'
          'GET'     | '/users/confirmation?confirmation_token=abc'
          'POST'    | '/users/unlock'
          'GET'     | '/-/trial_registrations/new?glm_source=about.gitlab.com'
          'POST'    | '/users'
          'POST'    | '/-/trial_registrations'
        end

        with_them do
          it 'leaves the request out of every rule' do
            expect(matching_rule_names(path, method: method)).to be_empty
          end

          context 'when enforcing' do
            before do
              stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
            end

            it 'still leaves the request out of every rule' do
              expect(matching_rule_names(path, method: method)).to be_empty
            end
          end
        end

        context 'on a neighbouring path' do
          where(:method, :path) do
            'GET'  | '/oauth/token/info'
            'GET'  | '/oauth/token/info.json'
            'POST' | '/oauth/revoke'
            'POST' | '/oauth/introspect'
            'GET'  | '/oauth/authorize/native'
            'GET'  | '/groups/my-group/-/saml'
            'GET'  | '/groups/parent/child/-/saml/sso'
            'GET'  | '/users/auth/projects'
            'GET'  | '/oauth/userinfo'
            'GET'  | '/.well-known/webfinger'
            'GET'  | '/.well-known/oauth-protected-resource/group/project/api/v4/mcp'
            'GET'  | '/users/sign_up/welcome'
            'GET'  | '/users/password/complexity/extra'
            'GET'  | '/o/my-org'
            'GET'  | '/-/subscriptions/new'
            'POST' | '/-/invites/AbC_123-xyz/accept'
          end

          with_them do
            it 'still counts the request under the unauthenticated pair' do
              expect(matching_rule_names(path, method: method)).to eq(%w[unauthenticated_traffic_per_ip_log])
            end
          end
        end

        it 'still counts an authenticated user on these paths under the plan rules', :aggregate_failures do
          stub_feature_flags(rate_limiter_plan_limits_free_info: true)

          %w[/users/sign_in /groups/my-group/-/saml/sso].each do |path|
            expect(matching_rule_names(path, requester_type: 'user', requester_id: '42', requester_plan: 'free'))
              .to eq(%w[sustained_traffic_per_user_free_plan_log burst_web_traffic_per_user_free_plan_log]), path
          end

          %w[/oauth/authorize /oauth/token /oauth/register].each do |path|
            expect(matching_rule_names(path, requester_type: 'user', requester_id: '42', requester_plan: 'free'))
              .to eq(%w[sustained_traffic_per_user_free_plan_log burst_traffic_per_user_free_plan_log]), path
          end
        end
      end

      describe 'the client telemetry exclusion' do
        it 'is declared on every plan rule, so a new tier cannot leave it out', :aggregate_failures do
          described_class::PLAN_RULES.each do |rule|
            expect(rule.match[:path]&.match?('/api/v4/usage_data/track_event')).to be(false), rule.name
          end
        end

        where(:tier, :enforce) do
          ::GitlabSubscriptions::SystemDefined::Plan::TIERS.product([false, true])
        end

        with_them do
          let(:requester) { { requester_type: 'user', requester_id: '42', requester_plan: tier } }
          let(:suffix) { enforce ? '' : '_log' }

          before do
            stub_feature_flags(
              "rate_limiter_plan_limits_#{tier}_info": true,
              "rate_limiter_plan_limits_#{tier}_enforce": enforce
            )
          end

          it 'counts the telemetry endpoints under no plan rule', :aggregate_failures do
            %w[
              /api/v4/usage_data/track_event
              /api/v4/usage_data/track_event.json
              /api/v4/usage_data/track_event?source=ide
              /api/v4/usage_data/track_events
              /api/v4/usage_data/increment_counter
              /api/v4/usage_data/increment_unique_users
            ].each do |path|
              expect(matching_rule_names(path, method: 'POST', **requester)).to be_empty, path
            end
          end

          it 'still counts the neighbouring metric_definitions' do
            expect(matching_rule_names('/api/v4/usage_data/metric_definitions', **requester)).to eq(
              ["sustained_traffic_per_user_#{tier}_plan#{suffix}", "burst_traffic_per_user_#{tier}_plan#{suffix}"]
            )
          end
        end
      end

      describe 'the Git operation counting' do
        let(:lfs_oid) { Digest::SHA256.hexdigest('lfs object') }

        it 'skips the continuation requests on every plan rule', :aggregate_failures do
          described_class::PLAN_RULES.each do |rule|
            expect(rule.match[:path].match?('/group/project.git/git-upload-pack')).to be(false), rule.name
          end
        end

        where(:tier, :enforce) do
          ::GitlabSubscriptions::SystemDefined::Plan::TIERS.product([false, true])
        end

        with_them do
          let(:requester) { { requester_type: 'user', requester_id: '42', requester_plan: tier } }
          let(:counted) do
            suffix = enforce ? '' : '_log'
            ["sustained_traffic_per_user_#{tier}_plan#{suffix}", "burst_traffic_per_user_#{tier}_plan#{suffix}"]
          end

          def counted_in(bucket)
            counted.map { |name| name.sub('burst_traffic_per_user_free', "burst_#{bucket}_traffic_per_user_free") }
          end

          before do
            stub_feature_flags(
              "rate_limiter_plan_limits_#{tier}_info": true,
              "rate_limiter_plan_limits_#{tier}_enforce": enforce
            )
          end

          it 'counts the request that starts each operation', :aggregate_failures do
            [
              ['GET', '/group/project.git/info/refs?service=git-upload-pack'],
              ['GET', '/group/project.git/info/refs?service=git-receive-pack'],
              ['POST', '/group/project.git/info/lfs/objects/batch'],
              ['POST', '/group/project.git/info/lfs/locks/verify']
            ].each do |method, path|
              expect(matching_rule_names(path, method: method, **requester))
                .to eq(counted_in('git_and_dependency_proxy')), path
            end
          end

          it 'skips the requests that continue it', :aggregate_failures do
            [
              ['POST', '/group/project.git/git-upload-pack'],
              ['POST', '/group/project.git/git-receive-pack'],
              ['POST', '/group/project.wiki.git/git-upload-pack'],
              ['POST', '/gitlab-org/gitlab-foss.git/git-upload-pack'],
              ['POST', '/snippets/1.git/git-upload-pack'],
              ['GET', "/group/project.git/gitlab-lfs/objects/#{lfs_oid}"],
              ['PUT', "/group/project.git/gitlab-lfs/objects/#{lfs_oid}/1024/authorize"],
              ['PUT', "/group/project.git/gitlab-lfs/objects/#{lfs_oid}/1024"]
            ].each do |method, path|
              expect(matching_rule_names(path, method: method, **requester)).to be_empty, path
            end
          end

          it 'still counts a web request whose path ends like a continuation' do
            expect(matching_rule_names('/group/project/-/raw/main/file.git/git-upload-pack', **requester))
              .to eq(counted_in('web'))
          end
        end
      end

      describe 'the Free web burst split' do
        let(:user) { { requester_type: 'user', requester_id: '42', requester_plan: 'free' } }
        let(:api_burst) { %w[sustained_traffic_per_user_free_plan burst_traffic_per_user_free_plan] }
        let(:git_burst) do
          %w[sustained_traffic_per_user_free_plan burst_git_and_dependency_proxy_traffic_per_user_free_plan]
        end

        let(:web_burst) { %w[sustained_traffic_per_user_free_plan burst_web_traffic_per_user_free_plan] }
        let(:upload_burst) do
          %w[sustained_traffic_per_user_free_plan burst_upload_and_pwa_manifest_traffic_per_user_free_plan]
        end

        before do
          stub_feature_flags(rate_limiter_plan_limits_free_info: true, rate_limiter_plan_limits_free_enforce: true)
        end

        it 'counts web pages and their JSON endpoints in the web bucket', :aggregate_failures do
          %w[
            /group/project/-/merge_requests/1
            /group/project/-/merge_requests/1/widget.json
            /group/project/-/merge_requests/1/discussions.json
            /group/project/-/blob/main/uploads/0123abcd/image.png
            /user/user.gitlab.io/-/merge_requests/1
          ].each do |path|
            expect(matching_rule_names(path, **user)).to eq(web_burst), path
          end
        end

        it 'counts images, attachments and the PWA manifest in their own bucket', :aggregate_failures do
          %w[
            /-/project/1/uploads/0123abcd/image.png
            /group/project/uploads/0123abcd/image.png
            /groups/group/-/uploads/0123abcd/image.png
            /group/project/-/wikis/uploads/0123abcd/image.png
            /uploads/-/system/user/avatar/1/avatar.png
            /-/manifest.json
          ].each do |path|
            expect(matching_rule_names(path, **user)).to eq(upload_burst), path
          end
        end

        def frontend_rule_names(path, method: 'POST')
          allow(Gitlab::RequestForgeryProtection).to receive(:verified?).and_return(true)

          facts = ::Gitlab::RackAttack::LabkitRateLimit::ClassifiedRequest.new(
            Rack::MockRequest.env_for(path, method: method,
              'HTTP_X_CSRF_TOKEN' => 'token', 'rack.session' => { _csrf_token: 'token' })
          ).labkit_facts.merge(user)

          described_class.for_limiter(general)
            .select { |rule| rule.match.all? { |key, matcher| matcher.match?(facts[key]) } }
            .map(&:name)
        end

        it 'counts GraphQL from the web UI in the web bucket' do
          expect(frontend_rule_names('/api/graphql')).to eq(web_burst)
        end

        it 'keeps a Git request with a valid CSRF token in the Git bucket' do
          expect(frontend_rule_names('/group/project.git/info/refs?service=git-upload-pack', method: 'GET'))
            .to eq(git_burst)
        end

        it 'counts API requests and GraphQL without a session in the API bucket', :aggregate_failures do
          [
            ['GET', '/api/v4/projects/1/pipelines'],
            ['POST', '/api/graphql'],
            ['POST', '/oauth/token']
          ].each do |method, path|
            expect(matching_rule_names(path, method: method, **user)).to eq(api_burst), path
          end
        end

        # API_PATH_REGEX matches /oauth/ anywhere, so a subgroup named oauth makes its Git paths API paths too.
        it 'counts Git under a subgroup named oauth in the Git bucket only', :aggregate_failures do
          %w[
            /group/oauth/project.git/info/refs
            /group/oauth/info/refs
          ].each do |path|
            expect(matching_rule_names(path, **user)).to eq(git_burst), path
          end
        end

        it 'counts uploads under a subgroup named oauth in the upload bucket only' do
          expect(matching_rule_names('/group/oauth/project/uploads/0123abcd/image.png', **user)).to eq(upload_burst)
        end

        it 'counts Git, LFS and dependency proxy requests in the Git bucket', :aggregate_failures do
          [
            ['GET', '/group/project.git/info/refs?service=git-upload-pack'],
            ['GET', '/group/project/info/refs?service=git-upload-pack'],
            ['POST', '/group/project.git/info/lfs/objects/batch'],
            ['GET', '/v2'],
            ['GET', '/v2/group/dependency_proxy/containers/alpine/manifests/latest'],
            ['GET', '/group/uploads/info/refs?service=git-upload-pack'],
            ['GET', '/v2/group/dependency_proxy/containers/uploads/blobs/sha256:abc']
          ].each do |method, path|
            expect(matching_rule_names(path, method: method, **user)).to eq(git_burst), path
          end
        end

        it 'keeps the same split in the log rules while the limits are not enforced', :aggregate_failures do
          stub_feature_flags(rate_limiter_plan_limits_free_enforce: false)

          {
            '/group/project/-/merge_requests/1' => web_burst,
            '/-/project/1/uploads/0123abcd/image.png' => upload_burst,
            '/api/v4/projects/1/pipelines' => api_burst,
            '/group/project.git/info/refs' => git_burst,
            '/group/uploads/info/refs' => git_burst,
            '/group/oauth/project.git/info/refs' => git_burst
          }.each do |path, names|
            expect(matching_rule_names(path, **user)).to eq(names.map { |name| "#{name}_log" }), path
          end
        end

        it 'leaves Premium and Ultimate with one burst bucket', :aggregate_failures do
          %w[premium ultimate].each do |plan|
            stub_feature_flags("rate_limiter_plan_limits_#{plan}_info": true)

            expect(matching_rule_names('/group/project/-/merge_requests/1', **user, requester_plan: plan))
              .to eq(["sustained_traffic_per_user_#{plan}_plan_log", "burst_traffic_per_user_#{plan}_plan_log"]), plan
          end
        end
      end

      # The design document's Limits table, one row per plan budget. Ultimate burst
      # per user is the revised 2,000.
      describe 'the plan budgets' do
        where(:plan, :kind, :limit, :period) do
          'free'     | 'sustained_traffic_per_user'                      | 5_000  | 1.hour
          'free'     | 'burst_traffic_per_user'                          | 100    | 1.minute
          'free'     | 'burst_git_and_dependency_proxy_traffic_per_user' | 100    | 1.minute
          'free'     | 'burst_web_traffic_per_user'                      | 300    | 1.minute
          'free'     | 'burst_upload_and_pwa_manifest_traffic_per_user'  | 300    | 1.minute
          'premium'  | 'sustained_traffic_per_user'                      | 15_000 | 1.hour
          'premium'  | 'burst_traffic_per_user'                          | 1_250  | 1.minute
          'ultimate' | 'sustained_traffic_per_user'                      | 25_000 | 1.hour
          'ultimate' | 'burst_traffic_per_user'                          | 2_000  | 1.minute
        end

        with_them do
          let(:enforcing) { rule("#{kind}_#{plan}_plan") }
          let(:logging) { rule("#{kind}_#{plan}_plan_log") }
          let(:info_fact) { :"plan_limits_#{plan}_info" }
          let(:enforce_fact) { :"plan_limits_#{plan}_enforce" }

          it 'carries the limit, period and counter key from the Limits table', :aggregate_failures do
            [enforcing, logging].each do |candidate|
              expect(candidate.limit).to eq(limit), candidate.name
              expect(candidate.period).to eq(period), candidate.name
              expect(candidate.characteristics).to eq(%i[requester_type requester_id]), candidate.name
            end
          end

          it 'matches its own plan and a present requester only', :aggregate_failures do
            expect(logging.match[:requester_plan].match?(plan)).to be(true)
            expect(logging.match[:requester_plan].match?(nil)).to be(false)
            expect(logging.match[:requester_plan].match?('bronze')).to be(false)
            expect(logging.match[:requester_id].match?('42')).to be(true)
            expect(logging.match[:requester_id].match?(nil)).to be(false)
          end

          # Every rule states info-gates-enforce itself now, rather than reading a
          # boolean FlagPolicy had already combined.
          it 'requires its own info flag' do
            expect(logging.match[info_fact].match?(true)).to be(true)
            expect(logging.match[info_fact].match?(false)).to be(false)
          end

          it 'splits the pair on the enforce flag', :aggregate_failures do
            expect(enforcing.action).to eq(:limit)
            expect(enforcing.match[enforce_fact].match?(true)).to be(true)
            expect(enforcing.match[enforce_fact].match?(false)).to be(false)
            expect(logging.action).to eq(:log)
            expect(logging.match[enforce_fact].match?(false)).to be(true)
            expect(logging.match[enforce_fact].match?(true)).to be(false)
          end
        end
      end
    end

    context 'when not on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'is empty for the general limiter' do
        expect(described_class.for_limiter(general)).to be_empty
      end
    end
  end

  # The tiers the rules are keyed by are the ones SystemDefined::Plan.tier_for can return, and
  # that mapping is the design document's Plan Name Mapping table.
  describe 'plan name mapping' do
    let(:rule_tiers) do
      described_class::PLAN_RULES.filter_map { |rule| rule.name[/_([^_]+)_plan(?:_log)?\z/, 1] }.uniq
    end

    where(:plan_name, :tier) do
      nil                            | 'free'
      'default'                      | 'free'
      'free'                         | 'free'
      'early_adopter'                | 'free'
      'bronze'                       | 'premium'
      'silver'                       | 'premium'
      'premium'                      | 'premium'
      'premium_trial'                | 'premium'
      'opensource'                   | 'ultimate'
      'gold'                         | 'ultimate'
      'ultimate'                     | 'ultimate'
      'ultimate_trial'               | 'ultimate'
      'ultimate_trial_paid_customer' | 'ultimate'
    end

    with_them do
      it 'collapses the plan name onto a tier the rules know' do
        expect(::GitlabSubscriptions::SystemDefined::Plan.tier_for(plan_name)).to eq(tier)
        expect(rule_tiers).to include(tier)
      end
    end

    it 'has rules for every tier, in rank order' do
      expect(rule_tiers).to eq(::GitlabSubscriptions::SystemDefined::Plan::TIERS)
    end
  end
end
