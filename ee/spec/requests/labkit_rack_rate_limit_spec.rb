# frozen_string_literal: true

require 'spec_helper'

# The EE incident-management throttle (throttle_incident_management_notification_web)
# fires only on alerts/notify requests, and alerts_notify? requires web_request?,
# so it always co-fires with the general web throttle. Rack::Attack counts such a
# request under both throttles independently, so the Labkit shadow must too: the
# incident throttle lives in its own limiter (rack_request_incident_management,
# counted by path) while the web throttle stays in rack_request (counted by ip).
#
# This proves one alerts/notify request increments both counters once, in disjoint
# keyspaces, rather than one masking the other (which a shared limiter would cause,
# since the middleware records only the first throttle that fires per limiter).
RSpec.describe 'Labkit::RateLimit rack middleware (EE throttles)', :clean_gitlab_redis_rate_limiting, feature_category: :rate_limiting do
  include RackAttackSpecHelpers
  using RSpec::Parameterized::TableSyntax

  let(:path) { '/group/project/alerts/notify' }

  before do
    stub_application_setting(
      throttle_unauthenticated_enabled: true,
      throttle_incident_management_notification_enabled: true,
      throttle_incident_management_notification_per_period: 100,
      throttle_incident_management_notification_period_in_seconds: 60
    )

    # spec/support/rate_limiter_labkit_rack_shadow.rb stubs all cohort flags to
    # false globally to keep the shadow out of unrelated specs; re-enable both
    # cohorts here so the middleware actually runs for the throttles under test.
    stub_feature_flags(
      rate_limiter_use_labkit_rack_cohort_1: true,
      rate_limiter_use_labkit_rack_cohort_2: true
    )
  end

  # Sum every labkit counter under a limiter's keyspace. The ':' delimiter after
  # the limiter name keeps rack_request from matching rack_request_protected_paths
  # or rack_request_incident_management, so each limiter is counted in isolation.
  def labkit_total_for(limiter)
    Gitlab::Redis::RateLimiting.with do |redis|
      keys = redis.scan_each(match: "labkit:rl:{#{limiter}:*").to_a
      keys.sum { |key| redis.get(key).to_i }
    end
  end

  # The same keyspace broken out per rule, as { rule_name => count }. Asserting the
  # whole hash says which rule counted and that nothing else did, which a total
  # cannot: a rule pair whose names share a prefix would otherwise be summed
  # together, and an unrelated throttle claiming the request would look identical.
  def labkit_counts_for(limiter)
    Gitlab::Redis::RateLimiting.with do |redis|
      redis.scan_each(match: "labkit:rl:{#{limiter}:*").to_a.each_with_object({}) do |key, counts|
        rule = key[/\{#{Regexp.escape(limiter)}:(.+?):/, 1]
        counts[rule] = counts.fetch(rule, 0) + redis.get(key).to_i
      end
    end
  end

  # Pre-load a rule's counter so an example can reach a 60-per-hour limit in two
  # requests rather than sixty-one. Writes the key layout labkit_counts_for reads
  # back, so a drift in it fails these examples rather than quietly skipping the
  # boundary: a key labkit does not recognise leaves the request counting from zero.
  # The anonymous per-IP 429: one name for both buckets and no count headers, so it
  # doesn't say whether the request matched a paid namespace.
  def expect_concealed_rejection
    yield

    expect(response).to have_gitlab_http_status(:too_many_requests)
    expect(response.headers.to_h).to include(
      'RateLimit-Name' => 'unauthenticated_traffic_per_ip',
      'RateLimit-Reset' => a_string_matching(/^\d+$/),
      'Retry-After' => a_string_matching(/^\d+$/)
    )
    expect(response.headers.to_h).not_to include('RateLimit-Limit', 'RateLimit-Observed', 'RateLimit-Remaining')
  end

  def seed_labkit_counter(limiter, rule, count, key: 'ip:127.0.0.1')
    Gitlab::Redis::RateLimiting.with do |redis|
      redis.set("labkit:rl:{#{limiter}:#{rule}:#{key}}", count)
    end
  end

  it 'counts one alerts/notify request in both the incident and web limiters' do
    post path

    expect(labkit_total_for('rack_request_incident_management')).to eq(1)
    expect(labkit_total_for('rack_request')).to eq(1)
  end

  # The tier-aware rollout must outlive the Rack::Attack migration flags.
  context 'with every migration cohort inactive' do
    before do
      stub_saas_features(gitlab_com_subscriptions: true)
      stub_feature_flags(
        rate_limiter_use_labkit_rack_cohort_1: false,
        rate_limiter_use_labkit_rack_cohort_2: false,
        rate_limiter_use_labkit_rack_cohort_3: false,
        rate_limiter_plan_limits_free_info: true
      )
    end

    it 'still evaluates the rules when a plan flag is on' do
      post path

      expect(labkit_total_for('rack_request')).to eq(1)
    end

    it 'evaluates nothing when the plan flags are off too' do
      stub_feature_flags(rate_limiter_plan_limits_free_info: false)

      post path

      expect(labkit_total_for('rack_request')).to eq(0)
    end

    # The state after the cohort flags are deleted: no cohort to enumerate, so no
    # cohort flag is read at all and the plan flags are the only thing running it.
    context 'when the registry declares no cohorts at all' do
      before do
        allow(Gitlab::RackAttack::LabkitRateLimit::ThrottleRegistry).to receive(:cohorts).and_return([])
      end

      it 'still evaluates the rules' do
        post path

        expect(labkit_total_for('rack_request')).to eq(1)
      end
    end
  end

  describe 'the unauthenticated per-IP throttle' do
    let(:anonymous_path) { '/api/v4/projects' }

    before do
      stub_saas_features(gitlab_com_subscriptions: true)
      stub_feature_flags(
        rate_limiter_use_labkit_rack_cohort_1: false,
        rate_limiter_use_labkit_rack_cohort_2: false,
        rate_limiter_use_labkit_rack_cohort_3: false
      )
      # for_limiter reads the SaaS gate at build time and the rule set is memoized,
      # so it must be rebuilt after the stub or an earlier example's build wins.
      Gitlab::RackAttack::LabkitRateLimit::Limiters.reset!
    end

    after do
      Gitlab::RackAttack::LabkitRateLimit::Limiters.reset!
    end

    it 'counts an anonymous request once the info flag is on' do
      stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)

      get anonymous_path

      expect(labkit_total_for('rack_request')).to eq(1)
    end

    it 'counts nothing while both flags are off' do
      get anonymous_path

      expect(labkit_total_for('rack_request')).to eq(0)
    end

    it 'counts nothing off GitLab.com even with the flag on' do
      stub_saas_features(gitlab_com_subscriptions: false)
      stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)

      get anonymous_path

      expect(labkit_total_for('rack_request')).to eq(0)
    end

    context 'with a pipeline trigger token' do
      let_it_be(:project) { create(:project, :public) }
      let_it_be(:trigger) { create(:ci_trigger, project: project) }

      let(:trigger_path) { "/api/v4/projects/#{project.id}/trigger/pipeline" }

      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
      end

      it 'counts the request under no plan rule' do
        post trigger_path, params: { token: trigger.token, ref: 'main' }

        expect(labkit_counts_for('rack_request')).to eq({})
      end

      # The middleware normalizes the path before classifying, so the doubled
      # slash reaches the rules as the plain path.
      where(:case_name, :path, :token_kind, :as) do
        'the ref route form' | '/api/v4/projects/%{id}/ref/main/trigger/pipeline' | :valid | nil
        'a URL-encoded path' | '/api/v4/projects/%{encoded_path}/trigger/pipeline' | :valid | nil
        'a doubled slash'    | '/api/v4//projects/%{id}/trigger/pipeline'          | :valid | nil
        'a JSON body'        | '/api/v4/projects/%{id}/trigger/pipeline'           | :valid | :json
        'a bad token'        | '/api/v4/projects/%{id}/trigger/pipeline'           | :bad   | nil
      end

      with_them do
        it 'counts the request under no plan rule' do
          token = token_kind == :valid ? trigger.token : 'glptt-not-a-real-token'
          url = format(path, id: project.id, encoded_path: CGI.escape(project.full_path))

          post url, params: { token: token, ref: 'main' }, as: as

          expect(labkit_counts_for('rack_request')).to eq({})
        end
      end

      it 'counts a token in the query string under no plan rule' do
        post "#{trigger_path}?#{{ token: trigger.token, ref: 'main' }.to_query}"

        expect(labkit_counts_for('rack_request')).to eq({})
      end

      it 'still serves a trigger once the IP has used up its unauthenticated allowance', :aggregate_failures do
        stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
        seed_labkit_counter('rack_request', 'unauthenticated_traffic_per_ip', 60)

        post trigger_path, params: { token: trigger.token, ref: 'main' }
        expect(response).not_to have_gitlab_http_status(:too_many_requests)

        expect_concealed_rejection { get anonymous_path }
      end
    end

    context 'with Unleash feature flag polling' do
      let_it_be(:project) { create(:project, :public) }
      let_it_be(:client) { create(:operations_feature_flags_client, project: project) }

      let(:headers) { { 'UNLEASH-INSTANCEID' => client.token, 'UNLEASH-APPNAME' => 'production' } }

      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
      end

      # The middleware normalizes the path before classifying, so the doubled
      # slash reaches the rules as the plain path.
      where(:method, :path) do
        :get  | '/api/v4/feature_flags/unleash/%{id}'
        :get  | '/api/v4/feature_flags/unleash/%{id}/features'
        :get  | '/api/v4/feature_flags/unleash/%{id}/client/features'
        :get  | '/api/v4//feature_flags/unleash/%{id}/client/features'
        :post | '/api/v4/feature_flags/unleash/%{id}/client/register'
        :post | '/api/v4/feature_flags/unleash/%{id}/client/metrics'
      end

      with_them do
        it 'serves the request and counts it under no plan rule', :aggregate_failures do
          public_send(method, format(path, id: project.id), headers: headers)

          expect(response).to have_gitlab_http_status(:ok)
          expect(labkit_counts_for('rack_request')).to eq({})
        end
      end

      it 'still serves a poll once the IP has used up its unauthenticated allowance', :aggregate_failures do
        stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
        seed_labkit_counter('rack_request', 'unauthenticated_traffic_per_ip', 60)

        get "/api/v4/feature_flags/unleash/#{project.id}/client/features", headers: headers
        expect(response).to have_gitlab_http_status(:ok)

        expect_concealed_rejection { get anonymous_path }
      end
    end

    context 'with the deprecated secure files installers' do
      let(:installer_path) do
        '/gitlab-org/incubation-engineering/mobile-devops/download-secure-files/-/raw/main/installer'
      end

      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
      end

      where(:project, :path) do
        [
          %w[download-secure-files /-/raw/main/installer],
          %w[download-secure-files /-/releases/permalink/latest/downloads/download-secure-files-linux-amd64],
          %w[download-secure-files /-/releases/v0.1.16/downloads/download-secure-files-linux-amd64],
          %w[download-secure-files /-/jobs/artifacts/main/raw/dist/download-secure-files-linux-amd64],
          %w[download-secure-files /-/jobs/11482053960/artifacts/raw/dist/download-secure-files-linux-amd64],
          %w[load-secure-files /-/raw/main/installer],
          %w[load-secure-files /-/releases/permalink/latest/downloads/load-secure-files-osx.tar.gz],
          %w[load-secure-files /-/releases/dfde2066/downloads/load-secure-files-osx.tar.gz],
          %w[load-secure-files /-/jobs/artifacts/main/raw/releases/load-secure-files-osx.tar.gz],
          %w[load-secure-files /-/jobs/3445347913/artifacts/raw/releases/load-secure-files-osx.tar.gz]
        ]
      end

      with_them do
        it 'counts the request under the web throttle but not the plan rule', :aggregate_failures do
          get "/gitlab-org/incubation-engineering/mobile-devops/#{project}#{path}"

          counts = labkit_counts_for('rack_request')
          expect(counts).not_to have_key('unauthenticated_traffic_per_ip_log')
          expect(counts).to include('unauthenticated_web' => 1)
        end
      end

      it 'still serves the installer once the IP has used up its unauthenticated allowance', :aggregate_failures do
        stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
        seed_labkit_counter('rack_request', 'unauthenticated_traffic_per_ip', 60)

        get installer_path
        expect(response).not_to have_gitlab_http_status(:too_many_requests)

        expect_concealed_rejection { get anonymous_path }
      end

      context 'with another path in those projects, or the same path in another project' do
        where(:other_path) do
          %w[
            /gitlab-org/incubation-engineering/mobile-devops/download-secure-files/-/issues
            /gitlab-org/incubation-engineering/mobile-devops/download-secure-files/-/raw/main/README.md
            /gitlab-org/incubation-engineering/mobile-devops/download-secure-files/-/releases
            /gitlab-org/incubation-engineering/mobile-devops/download-secure-files/-/jobs/artifacts/main/download
            /gitlab-org/incubation-engineering/mobile-devops/load-secure-files/-/jobs/3445347913/artifacts/download
            /gitlab-org/incubation-engineering/mobile-devops/load-secure-files/-/blob/main/installer
            /gitlab-org/gitlab/-/raw/main/installer
          ]
        end

        with_them do
          it 'still counts the request under the plan rule' do
            get other_path

            expect(labkit_counts_for('rack_request')).to include('unauthenticated_traffic_per_ip_log' => 1)
          end
        end
      end
    end

    context 'with runner router discovery' do
      let_it_be(:runner) { create(:ci_runner) }

      let(:discovery_path) { '/api/v4/runners/router/discovery' }

      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
      end

      it 'counts a request with a valid Runner-Token header under no plan rule' do
        get discovery_path, headers: { 'Runner-Token' => runner.token }

        expect(labkit_counts_for('rack_request')).to eq({})
      end

      it 'still counts a request with an unknown Runner-Token header per IP' do
        get discovery_path, headers: { 'Runner-Token' => 'glrt-not-a-real-token' }

        expect(labkit_counts_for('rack_request')).to eq({ 'unauthenticated_traffic_per_ip_log' => 1 })
      end
    end

    context 'with runner registration' do
      let_it_be(:project) { create(:project) }

      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
      end

      where(:case_name, :token) do
        'a registration token' | -> { project.runners_token }
        'a rejected token'     | -> { 'not-a-real-token' }
      end

      with_them do
        it 'counts the request under no plan rule' do
          post '/api/v4/runners', params: { token: instance_exec(&token) }

          expect(labkit_counts_for('rack_request')).to eq({})
        end
      end

      it 'still serves registration once the IP has used up its unauthenticated allowance', :aggregate_failures do
        stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
        seed_labkit_counter('rack_request', 'unauthenticated_traffic_per_ip', 60)

        post '/api/v4/runners', params: { token: project.runners_token }
        expect(response).not_to have_gitlab_http_status(:too_many_requests)

        expect_concealed_rejection { get anonymous_path }
      end
    end

    context 'with group SCIM provisioning' do
      let_it_be(:group) { create(:group) }
      let_it_be(:saml_provider) { create(:saml_provider, group: group) }
      let_it_be(:scim_token) { create(:group_scim_auth_access_token, group: group) }

      let(:headers) { { 'Authorization' => "Bearer #{scim_token.token}" } }

      before do
        stub_licensed_features(group_saml: true)
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
      end

      where(:path) do
        %w[
          /api/scim/v2/groups/%{group}/Users
          /api/scim/v2/groups/%{group}/Users.json
          /api/scim/v2/groups/%{group}/Users/
          /api/scim//v2/groups/%{group}/Users
        ]
      end

      with_them do
        it 'serves the request and counts it under no plan rule', :aggregate_failures do
          get format(path, group: group.full_path), headers: headers

          expect(response).to have_gitlab_http_status(:ok)
          expect(labkit_counts_for('rack_request')).to eq({})
        end
      end

      it 'still provisions once the IP has used up its unauthenticated allowance', :aggregate_failures do
        stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
        seed_labkit_counter('rack_request', 'unauthenticated_traffic_per_ip', 60)

        get "/api/scim/v2/groups/#{group.full_path}/Users", headers: headers
        expect(response).to have_gitlab_http_status(:ok)

        expect_concealed_rejection { get anonymous_path }
      end
    end

    context 'with the GitLab for Jira Cloud app' do
      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
      end

      # Jira Connect pages are web routes, so the legacy web throttle counts them too.
      where(:method, :path) do
        :get  | '/-/jira_connect/workspaces/search'
        :get  | '/-/jira_connect/repositories/search'
        :post | '/-/jira_connect/repositories/associate'
        :post | '/o/my-org/-/jira_connect/repositories/associate'
        :get  | '/-/jira_connect/branches/route'
        :get  | '/o/my-org/-/jira_connect/branches/route'
      end

      with_them do
        it 'counts the request under the web throttle but not the plan rule', :aggregate_failures do
          public_send(method, path)

          counts = labkit_counts_for('rack_request')
          expect(counts).not_to have_key('unauthenticated_traffic_per_ip_log')
          expect(counts).to include('unauthenticated_web' => 1)
        end
      end

      context 'on a lifecycle event or a browser-facing page' do
        where(:method, :path) do
          :post | '/-/jira_connect/events/installed'
          :get  | '/-/jira_connect/subscriptions'
        end

        with_them do
          it 'still counts the request under the plan rule' do
            public_send(method, path)

            expect(labkit_counts_for('rack_request')).to include('unauthenticated_traffic_per_ip_log' => 1)
          end
        end
      end
    end

    context 'with the dependency proxy' do
      let_it_be(:deploy_token) { create(:deploy_token, :group, :dependency_proxy_scopes) }

      let(:group) { deploy_token.groups.first }
      let(:manifest_path) { "/v2/#{group.full_path}/dependency_proxy/containers/alpine/manifests/latest" }

      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
      end

      # A pull starts with an anonymous request, which gets the 401 that tells the client where to authenticate.
      where(:path) do
        %w[
          /v2
          /v2/
          /v2/%{group}/dependency_proxy/containers/alpine/manifests/latest
        ]
      end

      with_them do
        it 'leaves the anonymous request out of the plan rule' do
          get format(path, group: group.full_path)

          expect(labkit_counts_for('rack_request')).not_to have_key('unauthenticated_traffic_per_ip_log')
        end
      end

      it 'counts a deploy token pull against the deploy token', :aggregate_failures do
        stub_feature_flags(rate_limiter_plan_limits_free_info: true)
        # Keeps the controller from fetching the image upstream; the middleware has counted the request by then.
        stub_config(dependency_proxy: { enabled: false })
        jwt = JSONWebToken::HMACToken.new(::Auth::ContainerProxyAuthenticationService.secret).tap do |token|
          token['deploy_token'] = deploy_token.token
          token.expire_time = token.issued_at + 1.minute
        end

        get manifest_path, headers: { 'Authorization' => "Bearer #{jwt.encoded}" }

        counts = labkit_counts_for('rack_request')
        expect(counts).to include('sustained_traffic_per_user_free_plan_log' => 1)
        expect(counts).not_to have_key('unauthenticated_traffic_per_ip_log')
      end
    end

    context 'with Git over HTTPS' do
      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
        stub_application_setting(throttle_unauthenticated_enabled: true)
      end

      # Rack::Attack excludes git paths from throttle_unauthenticated_web
      # unconditionally, so with throttle_unauthenticated_git_http off by default
      # nothing counts these. LFS is covered too, since repository_git_lfs_route_regex
      # nests inside the git one.
      where(:case_name, :path) do
        'a git path'  | '/group/project.git/info/refs'
        'an LFS path' | '/group/project.git/info/lfs/objects/batch'
      end

      with_them do
        it 'counts the request under no throttle at all' do
          get path

          expect(labkit_counts_for('rack_request')).to eq({})
        end
      end

      it 'still counts an unauthenticated non-git request under the plan rule' do
        get anonymous_path

        expect(labkit_counts_for('rack_request')).to eq({ 'unauthenticated_traffic_per_ip_log' => 1 })
      end
    end

    context 'with Git info/refs without the .git suffix' do
      let_it_be(:project) { create(:project, :public) }
      let_it_be(:user) { create(:user) }
      let_it_be(:token) { create(:personal_access_token, user: user) }

      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
      end

      # The middleware normalizes the path before classifying, so the trailing
      # slash reaches the rules as the plain path.
      where(:case_name, :path, :query) do
        'a bare request'      | '/%{project}/info/refs'  | ''
        'a trailing slash'    | '/%{project}/info/refs/' | ''
        'an upload-pack fetch' | '/%{project}/info/refs' | 'service=git-upload-pack'
        'a receive-pack push' | '/%{project}/info/refs'  | 'service=git-receive-pack'
      end

      with_them do
        let(:url) { [format(path, project: project.full_path), query.presence].compact.join('?') }
        let(:redirect) { ["/#{project.full_path}.git/info/refs", query.presence].compact.join('?') }

        it 'redirects to the .git URL and counts it under no throttle at all, like a .git path', :aggregate_failures do
          get url

          expect(response).to redirect_to(redirect)
          expect(labkit_counts_for('rack_request')).to eq({})
        end

        it 'counts it under no throttle at all when it carries Git credentials', :aggregate_failures do
          get url, headers: basic_auth_headers(user, token)

          expect(response).to redirect_to(redirect)
          expect(labkit_counts_for('rack_request')).to eq({})
        end
      end

      it 'still counts a file page ending in info/refs under the plan rule' do
        get "/#{project.full_path}/blob/main/info/refs"

        expect(labkit_counts_for('rack_request')).to include('unauthenticated_traffic_per_ip_log' => 1)
      end
    end

    context 'with alert notifications and Mailgun webhooks' do
      let_it_be(:project) { create(:project) }

      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
      end

      where(:path) do
        %w[
          /%{project}/alerts/notify
          /%{project}/alerts/notify.json
          /%{project}/alerts/notify/my-integration/a1b2c3d4e5f6
          /%{project}/prometheus/alerts/notify
          /%{project}/alerts/notify/
          /-/mailgun/webhooks
          /-/mailgun/webhooks/
          /-/members/mailgun/permanent_failures
        ]
      end

      with_them do
        it 'counts the request under the web throttle but not the plan rule', :aggregate_failures do
          post format(path, project: project.full_path)

          counts = labkit_counts_for('rack_request')
          expect(counts).not_to have_key('unauthenticated_traffic_per_ip_log')
          expect(counts).to include('unauthenticated_web' => 1)
        end
      end

      it 'keeps an alert under the per-path incident management throttle' do
        post "/#{project.full_path}/alerts/notify"

        expect(labkit_total_for('rack_request_incident_management')).to eq(1)
      end

      context 'with a blob page whose path ends in alerts/notify' do
        where(:blob_path) do
          %w[
            /%{project}/-/blob/main/alerts/notify
            /%{project}/blob/main/alerts/notify
          ]
        end

        with_them do
          it 'still counts the request under the plan rule' do
            get format(blob_path, project: project.full_path)

            expect(labkit_counts_for('rack_request')).to include('unauthenticated_traffic_per_ip_log' => 1)
          end
        end
      end
    end

    context 'with the HAProxy api health check' do
      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
      end

      where(:path) do
        %w[
          /-/k8s/api/-/readiness
          /-/k8s/api/-/readiness/
        ]
      end

      with_them do
        it 'counts the request under the web throttle but not the plan rule', :aggregate_failures do
          get path

          counts = labkit_counts_for('rack_request')
          expect(counts).not_to have_key('unauthenticated_traffic_per_ip_log')
          expect(counts).to include('unauthenticated_web' => 1)
        end
      end
    end

    context 'with the Slack app' do
      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
      end

      where(:path) do
        %w[
          /api/v4/slack/trigger
          /api/v4/slack/trigger.json
          /api/v4/slack/trigger/
          /api/v4//slack/trigger
          /api/v4/integrations/slack/events
          /api/v4/integrations/slack/interactions
          /api/v4/integrations/slack/options
        ]
      end

      with_them do
        it 'counts the request under the Slack rules instead of the unauthenticated pair' do
          post path

          expect(labkit_counts_for('rack_request')).to eq(
            'sustained_slack_app_traffic_per_ip_log' => 1, 'burst_slack_app_traffic_per_ip_log' => 1
          )
        end
      end
    end

    context 'with OAuth and sign-in', :with_current_organization do
      let_it_be(:group) { create(:group) }

      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
        # These are web pages, so the legacy web throttle would count them too.
        stub_application_setting(throttle_unauthenticated_enabled: false)
      end

      where(:method, :path) do
        :get  | '/'
        :get  | '//'
        :get  | '/users/sign_in'
        :get  | '/users/sign_in/'
        :get  | '/users//sign_in'
        :get  | '/users/sign_in?redirect_to_referer=yes'
        :get  | '/users/sign_up'
        :get  | '/users/john/exists'
        :get  | '/users/user.git/exists'
        :get  | '/users/identity_verification'
        :get  | '/-/arkose/data_exchange_payload'
        :get  | '/users/password/new'
        :get  | '/users/confirmation/new'
        :get  | '/users/unlock/new'
        :get  | '/users/confirmation?confirmation_token=abc'
        :get  | '/users/unlock?unlock_token=abc'
        :get  | '/-/trial_registrations/new'
        :get  | '/-/trial_registrations/new?glm_source=about.gitlab.com&glm_content=default-saas-trial/'
        :get  | '/groups/%{group}/-/saml/sso'
        :get  | '/oauth/authorize?client_id=abc&response_type=code'
        :post | '/oauth/token'
        :post | '/oauth/token/'
        :post | '/oauth//token'
        :post | '/oauth/authorize_device'
        :post | '/oauth/register'
        :post | '/oauth/register/'
        :post | '/oauth//register'
        :get  | '/.well-known/openid-configuration'
        :get  | '/.well-known/oauth-protected-resource/api/v4/mcp'
        :get  | '/.well-known/terraform.json'
        :get  | '/oauth/discovery/keys'
      end

      with_them do
        it 'counts the request under no plan rule' do
          public_send(method, format(path, group: group.full_path))

          expect(labkit_counts_for('rack_request')).to eq({})
        end
      end

      it 'counts a password sign-in under no plan rule' do
        post '/users/sign_in', params: { user: { login: 'nobody', password: 'wrong' } }

        expect(labkit_counts_for('rack_request')).to eq({})
      end

      it 'counts a sign-up and a trial sign-up under no plan rule', :aggregate_failures do
        post '/users/password/complexity', params: { user: { password: 'password' } }
        post '/users', params: { user: { username: 'new-user' } }
        post '/-/trial_registrations', params: { user: { username: 'new-user' } }

        expect(labkit_counts_for('rack_request')).to eq({})
      end

      it 'still counts a token info check under the unauthenticated pair', :aggregate_failures do
        get '/oauth/token/info'

        expect(response).to have_gitlab_http_status(:unauthorized)
        expect(labkit_counts_for('rack_request')).to eq({ 'unauthenticated_traffic_per_ip_log' => 1 })
      end

      it 'still serves sign-in and token requests once the IP has used up its allowance', :aggregate_failures do
        stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
        seed_labkit_counter('rack_request', 'unauthenticated_traffic_per_ip', 60)

        get '/users/sign_in'
        expect(response).to have_gitlab_http_status(:ok)

        post '/oauth/token'
        expect(response).not_to have_gitlab_http_status(:too_many_requests)

        post '/oauth/register'
        expect(response).not_to have_gitlab_http_status(:too_many_requests)

        expect_concealed_rejection { get '/oauth/token/info' }
      end

      it 'still serves the home page, sign-up and recovery once the IP has used up its allowance',
        :aggregate_failures do
        stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
        seed_labkit_counter('rack_request', 'unauthenticated_traffic_per_ip', 60)

        %w[/ /users/sign_up /users/almost_there /users/password/new /-/trial_registrations/new].each do |path|
          get path
          expect(response).not_to have_gitlab_http_status(:too_many_requests), "#{path} was rate limited"
        end

        expect_concealed_rejection { get '/oauth/token/info' }
      end
    end

    # Users behind one office IP open their company's pages anonymously to be sent to
    # sign-in, so a paid namespace gets its own bucket instead of the IP's shared 60.
    context 'with anonymous requests for a paid namespace', :with_current_organization,
      :saas_gitlab_com_subscriptions do
      let_it_be(:paid_group) { create(:group) }
      let_it_be(:paid_project) { create(:project, :private, group: paid_group) }
      let_it_be(:other_paid_group) { create(:group) }
      let_it_be(:other_paid_project) { create(:project, :private, group: other_paid_group) }
      let_it_be(:free_project) { create(:project, :private) }

      let(:per_ip) { 'unauthenticated_traffic_per_ip' }
      let(:paid) { 'unauthenticated_paid_namespace_traffic_per_ip' }

      before_all do
        create(:gitlab_subscription, :premium, namespace: paid_group)
        create(:gitlab_subscription, :ultimate, namespace: other_paid_group)
      end

      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
        # These are web pages, so the legacy web throttle would count them too.
        stub_application_setting(throttle_unauthenticated_enabled: false)
      end

      paid_rules = %w[unauthenticated_paid_namespace_traffic_per_ip_log]
      per_ip_rules = %w[unauthenticated_traffic_per_ip_log]

      where(:case_name, :path, :counted_by) do
        'a paid project page'       | '/%{paid}'               | paid_rules
        'a paid group page'         | '/%{paid_group}'         | paid_rules
        'a Free project page'       | '/%{free}'               | per_ip_rules
        'a paid project in the API' | '/api/v4/projects/%{id}' | paid_rules
        'a page with no namespace'  | '/explore/projects'      | per_ip_rules
      end

      with_them do
        it 'counts the request under the rules for its bucket' do
          get format(path, paid: paid_project.full_path, paid_group: paid_group.full_path,
            free: free_project.full_path, id: paid_project.id)

          expect(labkit_counts_for('rack_request')).to eq(counted_by.index_with(1))
        end
      end

      it 'counts every paid namespace in one bucket per IP' do
        2.times { get "/#{paid_project.full_path}" }
        get "/#{other_paid_project.full_path}"

        expect(labkit_counts_for('rack_request')).to eq({ "#{paid}_log" => 3 })
      end

      context 'when enforcing' do
        before do
          stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
        end

        it 'still sends a paid page load to sign-in once the IP has used up its allowance', :aggregate_failures do
          seed_labkit_counter('rack_request', per_ip, 60)

          get "/#{paid_project.full_path}"
          expect(response).to redirect_to(new_user_session_path)

          expect_concealed_rejection { get "/#{free_project.full_path}" }
        end

        it 'rejects anonymous requests to any paid namespace once the IP is past the paid limit',
          :aggregate_failures do
          seed_labkit_counter('rack_request', paid, 10_000)

          expect_concealed_rejection { get "/#{paid_project.full_path}" }
          expect_concealed_rejection { get "/api/v4/projects/#{other_paid_project.id}" }
        end

        # Proactive headers are only added once every cohort enforces.
        context 'when labkit sends the headers on responses it does not limit' do
          before do
            cohort_flags = Gitlab::RackAttack::LabkitRateLimit::ThrottleRegistry.cohorts.flat_map do |cohort|
              flag = :"rate_limiter_use_labkit_rack_cohort_#{cohort}"
              [flag, :"#{flag}_enforce"]
            end
            stub_feature_flags(cohort_flags.index_with(true))
            stub_application_setting(throttle_unauthenticated_enabled: true)
          end

          it 'sends a Free and a paid namespace the same rate limit headers', :freeze_time, :aggregate_failures do
            rate_limit_headers = -> { response.headers.to_h.select { |name, _| name.start_with?('RateLimit-') } }

            get "/#{free_project.full_path}"
            free_headers = rate_limit_headers.call

            Gitlab::Redis::RateLimiting.with(&:flushdb)
            get "/#{paid_project.full_path}"

            expect(response).to redirect_to(new_user_session_path)
            expect(free_headers).to include('RateLimit-Name' => 'throttle_unauthenticated_web')
            expect(rate_limit_headers.call).to eq(free_headers)
          end
        end

        it 'rejects a Free and a paid namespace with the same rate limit headers', :freeze_time do
          rate_limit_headers = -> { response.headers.to_h.select { |name, _| name.match?(/\ARateLimit-|Retry-After/) } }

          seed_labkit_counter('rack_request', per_ip, 60)
          get "/#{free_project.full_path}"
          free_headers = rate_limit_headers.call

          Gitlab::Redis::RateLimiting.with(&:flushdb)
          seed_labkit_counter('rack_request', paid, 10_000)
          get "/#{paid_project.full_path}"

          expect(rate_limit_headers.call).to eq(free_headers)
        end
      end
    end

    context 'with OAuth token checks', :with_current_organization do
      let_it_be(:user) { create(:user) }
      let_it_be(:token) { create(:oauth_access_token, resource_owner: user, scopes: [:openid]) }

      let(:valid_headers) { { 'Authorization' => "Bearer #{token.plaintext_token}" } }
      let(:invalid_headers) { { 'Authorization' => 'Bearer not-a-real-token' } }

      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true, rate_limiter_plan_limits_free_info: true)
      end

      where(:path) do
        %w[
          /oauth/token/info
          /oauth/token/info.json
          /oauth/userinfo
          /o/my-org/oauth/token/info
          /o/my-org/oauth/userinfo
        ]
      end

      with_them do
        it 'counts a valid token against its user' do
          get path, headers: valid_headers

          expect(labkit_counts_for('rack_request')).to include('sustained_traffic_per_user_free_plan_log' => 1)
          expect(labkit_counts_for('rack_request')).not_to have_key('unauthenticated_traffic_per_ip_log')
        end

        it 'still counts an invalid token per IP' do
          get path, headers: invalid_headers

          expect(labkit_counts_for('rack_request')).to include('unauthenticated_traffic_per_ip_log' => 1)
        end
      end

      it 'counts a valid token in a POST userinfo form body against its user' do
        post '/oauth/userinfo', params: { access_token: token.plaintext_token }

        expect(labkit_counts_for('rack_request')).to include('sustained_traffic_per_user_free_plan_log' => 1)
        expect(labkit_counts_for('rack_request')).not_to have_key('unauthenticated_traffic_per_ip_log')
      end

      it 'counts a valid personal access token against its user' do
        personal_access_token = create(:personal_access_token, user: user, scopes: [:read_user])

        get '/oauth/token/info', headers: { 'Authorization' => "Bearer #{personal_access_token.token}" }

        expect(labkit_counts_for('rack_request')).to include('sustained_traffic_per_user_free_plan_log' => 1)
        expect(labkit_counts_for('rack_request')).not_to have_key('unauthenticated_traffic_per_ip_log')
      end

      it 'still serves valid token checks once the IP has used up its allowance', :aggregate_failures do
        stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
        seed_labkit_counter('rack_request', 'unauthenticated_traffic_per_ip', 60)

        get '/oauth/token/info', headers: valid_headers
        expect(response).to have_gitlab_http_status(:ok)

        get '/oauth/userinfo', headers: valid_headers
        expect(response).to have_gitlab_http_status(:ok)

        expect_concealed_rejection { get '/oauth/token/info', headers: invalid_headers }
      end
    end

    context 'with an expired OAuth token', :with_current_organization do
      let_it_be(:user) { create(:user) }
      let_it_be(:expired_token) do
        create(:oauth_access_token, resource_owner: user, scopes: [:api], expires_in: 1.hour, created_at: 2.hours.ago)
      end

      let(:expired_path) { '/api/v4/user' }
      let(:expired_headers) { { 'Authorization' => "Bearer #{expired_token.plaintext_token}" } }

      before do
        stub_feature_flags(
          rate_limiter_unauthenticated_limits_info: true,
          rate_limiter_expired_oauth_token_per_token: true
        )
      end

      it 'observes the request per token and per IP, and still counts it under the unauthenticated rule' do
        get expired_path, headers: expired_headers

        expect(labkit_counts_for('rack_request')).to eq(
          'expired_oauth_token_traffic_per_token_log' => 1,
          'expired_oauth_token_traffic_per_ip_log' => 1,
          'unauthenticated_traffic_per_ip_log' => 1
        )
      end

      it 'still counts the request per IP while the flag is off' do
        stub_feature_flags(rate_limiter_expired_oauth_token_per_token: false)

        get expired_path, headers: expired_headers

        expect(labkit_counts_for('rack_request')).to eq({ 'unauthenticated_traffic_per_ip_log' => 1 })
      end

      where(:feed_path) { %w[/some-user.atom /some-group/oauth/-/issues.atom] }

      with_them do
        it 'still counts an expired token on a feed path per IP' do
          get feed_path, headers: expired_headers

          expect(labkit_counts_for('rack_request')).to include('unauthenticated_traffic_per_ip_log' => 1)
          expect(labkit_counts_for('rack_request')).not_to have_key('expired_oauth_token_traffic_per_token_log')
        end
      end

      it 'still counts an invalid token per IP' do
        get expired_path, headers: { 'Authorization' => 'Bearer not-a-real-token' }

        expect(labkit_counts_for('rack_request')).to eq({ 'unauthenticated_traffic_per_ip_log' => 1 })
      end

      it 'still counts an expired personal access token per IP' do
        personal_access_token = create(:personal_access_token, :expired, user: user, scopes: [:api])

        get expired_path, headers: { 'Authorization' => "Bearer #{personal_access_token.token}" }

        expect(labkit_counts_for('rack_request')).to eq({ 'unauthenticated_traffic_per_ip_log' => 1 })
      end

      context 'when the unauthenticated rules enforce but these only observe' do
        before do
          stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
        end

        it 'leaves the request under the enforcing per-IP rule, as before', :aggregate_failures do
          seed_labkit_counter('rack_request', 'unauthenticated_traffic_per_ip', 60)

          expect_concealed_rejection { get expired_path, headers: expired_headers }
          expect(labkit_counts_for('rack_request')).to include(
            'expired_oauth_token_traffic_per_token_log' => 1,
            'expired_oauth_token_traffic_per_ip_log' => 1
          )
        end
      end

      context 'when enforcing' do
        before do
          stub_feature_flags(
            rate_limiter_unauthenticated_limits_enforce: true,
            rate_limiter_expired_oauth_token_per_token_enforce: true
          )
        end

        it 'returns the 401 the client refreshes on once the IP has used up its allowance', :aggregate_failures do
          seed_labkit_counter('rack_request', 'unauthenticated_traffic_per_ip', 60)

          get expired_path, headers: expired_headers
          expect(response).to have_gitlab_http_status(:unauthorized)

          expect_concealed_rejection { get expired_path }
        end

        it 'still rejects the expired token per IP while the flag is off' do
          stub_feature_flags(rate_limiter_expired_oauth_token_per_token: false)
          seed_labkit_counter('rack_request', 'unauthenticated_traffic_per_ip', 60)

          expect_concealed_rejection { get expired_path, headers: expired_headers }
        end

        it 'rejects one expired token past 60 an hour', :aggregate_failures do
          seed_labkit_counter('rack_request', 'expired_oauth_token_traffic_per_token', 60,
            key: "expired_oauth_token_id:OauthAccessToken/#{expired_token.id}")

          get expired_path, headers: expired_headers

          expect(response).to have_gitlab_http_status(:too_many_requests)
          expect(response.headers['RateLimit-Name']).to eq('expired_oauth_token_traffic_per_token')
          # The block stops the walk, so a token past its own limit does not use up the per-IP cap.
          expect(labkit_counts_for('rack_request')).not_to have_key('expired_oauth_token_traffic_per_ip')
        end

        it 'rejects expired tokens from one IP past 1,200 an hour, across tokens', :aggregate_failures do
          seed_labkit_counter('rack_request', 'expired_oauth_token_traffic_per_ip', 1_200)

          get expired_path, headers: expired_headers

          expect(response).to have_gitlab_http_status(:too_many_requests)
          expect(response.headers['RateLimit-Name']).to eq('expired_oauth_token_traffic_per_ip')
        end
      end
    end

    # The plan rule carries no setting_* fact and sits above every registry rule, so
    # the admin toggle that governs the generic throttles cannot gate it either way.
    describe 'independence from the unauthenticated admin setting' do
      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
      end

      where(:setting) { [true, false] }

      with_them do
        it 'counts under the plan rule whether the setting is on or off' do
          stub_application_setting(throttle_unauthenticated_enabled: setting)

          get anonymous_path

          expect(labkit_counts_for('rack_request')).to include('unauthenticated_traffic_per_ip_log' => 1)
        end
      end
    end

    # The rule each flag combination selects, as the counter actually written. The
    # facts behind it are tabled in
    # ee/spec/lib/ee/gitlab/rack_attack/labkit_rate_limit/classified_request_spec.rb;
    # this is the rule those facts then select. Row 3 is the one worth having: enforce
    # without info counts nothing, so info alone is the off switch.
    describe 'the info and enforce flag combinations' do
      where(:info, :enforce, :counts) do
        false | false | {}
        true  | false | { 'unauthenticated_traffic_per_ip_log' => 1 }
        false | true  | {}
        true  | true  | { 'unauthenticated_traffic_per_ip' => 1 }
      end

      with_them do
        it 'counts under the rule the flags select' do
          stub_feature_flags(
            rate_limiter_unauthenticated_limits_info: info,
            rate_limiter_unauthenticated_limits_enforce: enforce
          )

          get anonymous_path

          expect(labkit_counts_for('rack_request')).to eq(counts)
        end
      end
    end

    describe 'enforcement at the published ceiling' do
      let(:limit) { 60 }
      let(:rule) { 'unauthenticated_traffic_per_ip' }

      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
      end

      it 'allows the request at the limit and rejects the one past it', :aggregate_failures do
        stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
        seed_labkit_counter('rack_request', rule, limit - 1)

        get anonymous_path
        expect(response).not_to have_gitlab_http_status(:too_many_requests)

        expect_concealed_rejection { get anonymous_path }
      end

      # The _log rule counts past its limit and never blocks, which is what makes
      # observe mode safe to leave on.
      it 'keeps counting past the limit without blocking while enforce is off', :aggregate_failures do
        seed_labkit_counter('rack_request', "#{rule}_log", limit)

        get anonymous_path

        expect(response).not_to have_gitlab_http_status(:too_many_requests)
        expect(labkit_counts_for('rack_request')).to eq({ "#{rule}_log" => limit + 1 })
      end
    end
  end

  describe 'enforcement and the admin setting toggle' do
    before do
      stub_feature_flags(
        rate_limiter_use_labkit_rack_cohort_1: true,
        rate_limiter_use_labkit_rack_cohort_1_enforce: true
      )
    end

    it 'rejects requests over the rate limit with the full RateLimit-* header set', :aggregate_failures do
      stub_application_setting(
        throttle_incident_management_notification_enabled: true,
        throttle_incident_management_notification_per_period: 1,
        throttle_incident_management_notification_period_in_seconds: 60
      )

      post path
      expect(response).not_to have_gitlab_http_status(:too_many_requests)

      expect_rejection('throttle_incident_management_notification_web') { post path }
    end

    it 'does not block requests over the same limit when the throttle setting is disabled', :aggregate_failures do
      stub_application_setting(
        throttle_incident_management_notification_enabled: false,
        throttle_incident_management_notification_per_period: 1,
        throttle_incident_management_notification_period_in_seconds: 60
      )

      3.times do
        post path
        expect(response).not_to have_gitlab_http_status(:too_many_requests)
      end
    end
  end

  # A plan-rule request is also counted by the general throttle below it: the
  # plan rules never claim, so evaluation continues into the registry rules.
  describe 'the per-plan throttles' do
    let_it_be(:project) { create(:project, :public) }
    let_it_be(:user) { create(:user) }
    let_it_be(:token) { create(:personal_access_token, user: user) }

    let(:path) { "/api/v4/projects/#{project.id}/issues" }
    let(:headers) { personal_access_token_headers(token) }

    before do
      stub_saas_features(gitlab_com_subscriptions: true)
      stub_application_setting(
        throttle_authenticated_api_enabled: true,
        throttle_authenticated_api_requests_per_period: 1000,
        throttle_authenticated_api_period_in_seconds: 60
      )
      stub_feature_flags(rate_limiter_plan_limits_free_info: true)
      # for_limiter reads the SaaS gate at build time and the rule set is memoized.
      Gitlab::RackAttack::LabkitRateLimit::Limiters.reset!
    end

    after do
      Gitlab::RackAttack::LabkitRateLimit::Limiters.reset!
    end

    def counter_for(rule_name)
      Gitlab::Redis::RateLimiting.with do |redis|
        keys = redis.scan_each(match: "labkit:rl:{rack_request:#{rule_name}:*").to_a
        keys.sum { |key| redis.get(key).to_i }
      end
    end

    it 'counts one request in the Free log rules and in the general throttle', :aggregate_failures do
      get path, headers: headers

      expect(response).to have_gitlab_http_status(:ok)
      expect(counter_for('authenticated_api')).to eq(1)
      expect(counter_for('sustained_traffic_per_user_free_plan_log')).to eq(1)
      expect(counter_for('burst_traffic_per_user_free_plan_log')).to eq(1)
      expect(counter_for('burst_traffic_per_user_free_plan')).to eq(0)
    end

    context 'with client telemetry over OAuth' do
      let_it_be(:oauth_token) { create(:oauth_access_token, resource_owner: user, scopes: 'api') }

      let(:headers) { { 'Authorization' => "Bearer #{oauth_token.plaintext_token}" } }
      let(:event) { 'i_code_review_user_create_mr' }

      # The middleware normalizes the path before classifying, so the slash variants
      # Grape also serves reach the rules as the plain path.
      where(:path, :batch) do
        '/api/v4/usage_data/track_event'            | false
        '/api/v4/usage_data/track_event.json'       | false
        '/api/v4/usage_data/track_event/'           | false
        '/api/v4/usage_data//track_event'           | false
        '/api/v4/usage_data/track_events'           | true
        '/api/v4/usage_data/increment_counter'      | false
        '/api/v4/usage_data/increment_unique_users' | false
      end

      with_them do
        it 'leaves the request out of the plan rules but not the general throttle', :aggregate_failures do
          params = batch ? { events: [{ event: event }] } : { event: event }

          post path, params: params, headers: headers, as: :json

          expect(response).to have_gitlab_http_status(:ok)
          expect(counter_for('authenticated_api')).to eq(1)
          expect(counter_for('sustained_traffic_per_user_free_plan_log')).to eq(0)
          expect(counter_for('burst_traffic_per_user_free_plan_log')).to eq(0)
        end
      end

      it 'still counts the neighbouring metric_definitions in the plan rules', :aggregate_failures do
        get '/api/v4/usage_data/metric_definitions', headers: headers

        expect(response).to have_gitlab_http_status(:ok)

        expect(counter_for('sustained_traffic_per_user_free_plan_log')).to eq(1)
        expect(counter_for('burst_traffic_per_user_free_plan_log')).to eq(1)
      end
    end

    context 'with Git over HTTPS' do
      let(:headers) { basic_auth_headers(user, token) }
      let(:repo) { "/#{project.full_path}.git" }
      let(:lfs_oid) { Digest::SHA256.hexdigest('lfs object') }

      def free_plan_counts
        %w[sustained_traffic_per_user_free_plan_log burst_git_and_dependency_proxy_traffic_per_user_free_plan_log]
          .map { |rule| counter_for(rule) }
      end

      where(:method, :path, :counts) do
        :get  | '/info/refs?service=git-upload-pack'            | [1, 1]
        :post | '/git-upload-pack'                              | [0, 0]
        :post | '//git-upload-pack'                             | [0, 0]
        :post | '/git-receive-pack'                             | [0, 0]
        :post | '/info/lfs/objects/batch'                       | [1, 1]
        :post | '/info/lfs/locks/verify'                        | [1, 1]
        :get  | '/gitlab-lfs/objects/%{lfs_oid}'                | [0, 0]
        :put  | '/gitlab-lfs/objects/%{lfs_oid}/1024/authorize' | [0, 0]
        :put  | '/gitlab-lfs/objects/%{lfs_oid}/1024'           | [0, 0]
      end

      with_them do
        it 'counts only the request that starts the operation' do
          public_send(method, repo + format(path, lfs_oid: lfs_oid), headers: headers)

          expect(free_plan_counts).to eq(counts)
        end
      end

      it 'lets a clone in progress finish once the user reaches the burst limit', :aggregate_failures do
        stub_feature_flags(rate_limiter_plan_limits_free_enforce: true)
        seed_labkit_counter(
          'rack_request', 'burst_git_and_dependency_proxy_traffic_per_user_free_plan', 100,
          key: "requester_type:user:requester_id:#{user.id}"
        )

        post "#{repo}/git-upload-pack", headers: headers
        expect(response).not_to have_gitlab_http_status(:too_many_requests)

        expect_rejection('burst_git_and_dependency_proxy_traffic_per_user_free_plan') do
          get "#{repo}/info/refs?service=git-upload-pack", headers: headers
        end
      end
    end

    context 'with a CI job token' do
      let_it_be(:job) { create(:ci_build, :running, project: project, user: user) }
      let_it_be(:state) { create(:terraform_state, :with_version, project: project) }

      before_all do
        project.add_maintainer(user)
      end

      before do
        stub_feature_flags(rate_limiter_unauthenticated_limits_info: true)
        stub_application_setting(throttle_unauthenticated_api_enabled: true)
      end

      shared_examples 'a request counted against the job user' do
        it 'counts the request in the Free plan rules and none of the unauthenticated ones', :aggregate_failures do
          get request_path, headers: request_headers

          expect(response).to have_gitlab_http_status(:ok)
          expect(counter_for('sustained_traffic_per_user_free_plan_log')).to eq(1)
          expect(counter_for('burst_traffic_per_user_free_plan_log')).to eq(1)
          expect(counter_for('authenticated_api')).to eq(1)
          expect(counter_for('unauthenticated_traffic_per_ip_log')).to eq(0)
          expect(counter_for('unauthenticated_api')).to eq(0)
        end
      end

      shared_examples 'a job token audited once per request' do
        it 'streams the job token audit event once, from the endpoint' do
          allow(::Gitlab::Audit::Auditor).to receive(:audit).and_call_original

          get request_path, headers: request_headers

          expect(::Gitlab::Audit::Auditor).to have_received(:audit)
            .with(hash_including(name: 'user_authenticated_using_job_token')).once
        end
      end

      context 'when sent as basic auth to the Terraform state API' do
        let(:request_path) { "/api/v4/projects/#{project.id}/terraform/state/#{state.name}" }
        let(:request_headers) do
          { 'Authorization' => ActionController::HttpAuthentication::Basic.encode_credentials(
            Gitlab::Auth::CI_JOB_USER, job.token
          ) }
        end

        it_behaves_like 'a request counted against the job user'
        it_behaves_like 'a job token audited once per request'

        it 'still serves the request once the IP has used up its unauthenticated allowance' do
          stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
          limit = Gitlab::RateLimit::PlanRules::UNAUTHENTICATED_RULES
            .find { |rule| rule.name == 'unauthenticated_traffic_per_ip' }.limit
          seed_labkit_counter('rack_request', 'unauthenticated_traffic_per_ip', limit)

          get request_path, headers: request_headers

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when sent as a JOB-TOKEN header to the job API' do
        let(:request_path) { '/api/v4/job' }
        let(:request_headers) { { 'JOB-TOKEN' => job.token } }

        it_behaves_like 'a request counted against the job user'
        it_behaves_like 'a job token audited once per request'
      end

      context 'when sent as a bearer token to the job API' do
        let(:request_path) { '/api/v4/job' }
        let(:request_headers) { { 'Authorization' => "Bearer #{job.token}" } }

        it_behaves_like 'a request counted against the job user'
      end
    end

    context 'when the requester reaches an Ultimate project only through a group share',
      :saas_gitlab_com_subscriptions do
      let_it_be(:ultimate_group) { create(:group) }
      let_it_be(:shared_project) { create(:project, :private, group: ultimate_group) }
      let_it_be(:invited_group) { create(:group) }
      let_it_be(:shared_user) { create(:user) }
      let_it_be(:shared_token) { create(:personal_access_token, user: shared_user) }

      let(:path) { "/api/v4/projects/#{shared_project.id}/issues" }
      let(:headers) { personal_access_token_headers(shared_token) }

      before_all do
        create(:gitlab_subscription, :ultimate, namespace: ultimate_group)
        create(:group_member, :developer, group: invited_group, user: shared_user)
        create(:group_group_link, shared_group: ultimate_group, shared_with_group: invited_group)
        shared_user.refresh_authorized_projects
      end

      before do
        stub_feature_flags(rate_limiter_plan_limits_ultimate_info: true)
      end

      it 'counts the request in the Ultimate log rules, not the Free ones', :aggregate_failures do
        get path, headers: headers

        expect(response).to have_gitlab_http_status(:ok)
        expect(counter_for('burst_traffic_per_user_ultimate_plan_log')).to eq(1)
        expect(counter_for('sustained_traffic_per_user_ultimate_plan_log')).to eq(1)
        expect(counter_for('burst_traffic_per_user_free_plan_log')).to eq(0)
      end

      it 'lets the request past the Free ceiling while Free is enforced' do
        stub_feature_flags(rate_limiter_plan_limits_free_enforce: true)
        seed_labkit_counter('rack_request', 'burst_traffic_per_user_free_plan', 100,
          key: "requester_type:user:requester_id:#{shared_user.id}")

        get path, headers: headers

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'with a signed-in GraphQL query without a valid CSRF token',
      :allow_forgery_protection, :saas_gitlab_com_subscriptions do
      let_it_be(:free_user) { create(:user) }
      let_it_be(:ultimate_user) { create(:user) }
      let_it_be(:ultimate_group) { create(:group) }

      before_all do
        create(:gitlab_subscription, :ultimate, namespace: ultimate_group)
        ultimate_group.add_developer(ultimate_user)
      end

      before do
        stub_feature_flags(
          rate_limiter_unauthenticated_limits_info: true,
          rate_limiter_plan_limits_ultimate_info: true
        )
      end

      def post_query_as(session_user)
        login_as(session_user)
        post '/api/graphql', params: { query: '{ currentUser { id } }' }, as: :json
      end

      def user_key(session_user)
        "requester_type:user:requester_id:#{session_user.id}"
      end

      it 'counts a Free user in the per-user Free rules, not the per-IP rule', :aggregate_failures do
        post_query_as(free_user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(counter_for('burst_traffic_per_user_free_plan_log')).to eq(1)
        expect(counter_for('sustained_traffic_per_user_free_plan_log')).to eq(1)
        expect(counter_for('unauthenticated_traffic_per_ip_log')).to eq(0)
      end

      it 'counts an Ultimate user in the per-user Ultimate rules, not the Free ones', :aggregate_failures do
        post_query_as(ultimate_user)

        expect(counter_for('burst_traffic_per_user_ultimate_plan_log')).to eq(1)
        expect(counter_for('sustained_traffic_per_user_ultimate_plan_log')).to eq(1)
        expect(counter_for('burst_traffic_per_user_free_plan_log')).to eq(0)
        expect(counter_for('unauthenticated_traffic_per_ip_log')).to eq(0)
      end

      it 'still serves the query once the IP has used up its unauthenticated allowance' do
        stub_feature_flags(rate_limiter_unauthenticated_limits_enforce: true)
        seed_labkit_counter('rack_request', 'unauthenticated_traffic_per_ip', 60)

        post_query_as(free_user)

        expect(response).to have_gitlab_http_status(:ok)
      end

      context 'when the plan limits are enforced' do
        before do
          stub_feature_flags(
            rate_limiter_plan_limits_free_enforce: true,
            rate_limiter_plan_limits_ultimate_enforce: true
          )
        end

        it 'rejects a Free user past the Free per-user burst limit', :aggregate_failures do
          seed_labkit_counter('rack_request', 'burst_traffic_per_user_free_plan', 100, key: user_key(free_user))

          post_query_as(free_user)

          expect(response).to have_gitlab_http_status(:too_many_requests)
          expect(response.headers['RateLimit-Name']).to eq('burst_traffic_per_user_free_plan')
          expect(response.headers['RateLimit-Limit']).to eq('100')
        end

        it 'lets an Ultimate user past the Free burst limit, counting it under Ultimate', :aggregate_failures do
          seed_labkit_counter('rack_request', 'burst_traffic_per_user_free_plan', 100, key: user_key(ultimate_user))

          post_query_as(ultimate_user)

          expect(response).to have_gitlab_http_status(:ok)
          expect(counter_for('burst_traffic_per_user_ultimate_plan')).to eq(1)
        end
      end
    end

    context 'with a signed-in GraphQL query with a valid CSRF token',
      :allow_forgery_protection, :saas_gitlab_com_subscriptions do
      before do
        login_as(user)
        get '/'
      end

      it 'counts the query in the Free web burst rule, not the API one', :aggregate_failures do
        expect do
          post '/api/graphql', params: { query: '{ currentUser { id } }' },
            headers: { 'X-CSRF-Token' => session['_csrf_token'] }, as: :json
        end.to change { counter_for('burst_web_traffic_per_user_free_plan_log') }.by(1)

        expect(response).to have_gitlab_http_status(:ok)
        expect(counter_for('burst_traffic_per_user_free_plan_log')).to eq(0)
      end

      it 'still counts the home page for a signed-in user' do
        expect { get '/' }.to change { counter_for('burst_web_traffic_per_user_free_plan_log') }.by(1)
      end
    end

    context 'with a signed-in web request', :saas_gitlab_com_subscriptions do
      let(:web_path) { '/-/autocomplete/users.json' }
      let(:user_key) { "requester_type:user:requester_id:#{user.id}" }

      before do
        login_as(user)
      end

      it 'counts the request in the Free web burst rule, not the API one', :aggregate_failures do
        get web_path

        expect(response).to have_gitlab_http_status(:ok)
        expect(counter_for('burst_web_traffic_per_user_free_plan_log')).to eq(1)
        expect(counter_for('burst_traffic_per_user_free_plan_log')).to eq(0)
        expect(counter_for('sustained_traffic_per_user_free_plan_log')).to eq(1)
      end

      context 'with a repository file under uploads/ through the deprecated raw route' do
        let_it_be(:project) { create(:project, :public, :repository) }

        before_all do
          project.repository.create_file(project.creator, 'uploads/2024/logo.png', 'logo',
            message: 'Add logo', branch_name: 'master')
        end

        it 'counts the request in the Free web burst rule, not the upload one', :aggregate_failures do
          get "/#{project.full_path}/raw/master/uploads/2024/logo.png"

          expect(response).to have_gitlab_http_status(:ok)
          expect(counter_for('burst_web_traffic_per_user_free_plan_log')).to eq(1)
          expect(counter_for('burst_upload_and_pwa_manifest_traffic_per_user_free_plan_log')).to eq(0)
        end
      end

      context 'when the Free limits are enforced' do
        before do
          stub_feature_flags(rate_limiter_plan_limits_free_enforce: true)
        end

        it 'still serves web requests once the user has used up the API burst limit', :aggregate_failures do
          seed_labkit_counter('rack_request', 'burst_traffic_per_user_free_plan', 100, key: user_key)

          get web_path

          expect(response).to have_gitlab_http_status(:ok)
          expect(counter_for('burst_web_traffic_per_user_free_plan')).to eq(1)
        end

        it 'rejects a web request past the web burst limit of 300', :aggregate_failures do
          seed_labkit_counter('rack_request', 'burst_web_traffic_per_user_free_plan', 300, key: user_key)

          get web_path

          expect(response).to have_gitlab_http_status(:too_many_requests)
          expect(response.headers['RateLimit-Name']).to eq('burst_web_traffic_per_user_free_plan')
          expect(response.headers['RateLimit-Limit']).to eq('300')
        end

        it 'still serves the PWA manifest once the user has used up the web burst limit', :aggregate_failures do
          seed_labkit_counter('rack_request', 'burst_web_traffic_per_user_free_plan', 300, key: user_key)

          get '/-/manifest.json'

          expect(response).to have_gitlab_http_status(:ok)
          expect(counter_for('burst_upload_and_pwa_manifest_traffic_per_user_free_plan')).to eq(1)
        end

        it 'rejects an upload or PWA manifest request past its burst limit of 300', :aggregate_failures do
          seed_labkit_counter('rack_request', 'burst_upload_and_pwa_manifest_traffic_per_user_free_plan', 300,
            key: user_key)

          get '/-/manifest.json'

          expect(response).to have_gitlab_http_status(:too_many_requests)
          expect(response.headers['RateLimit-Name']).to eq('burst_upload_and_pwa_manifest_traffic_per_user_free_plan')
          expect(response.headers['RateLimit-Limit']).to eq('300')
        end

        it 'still rejects an API request past the API burst limit of 100' do
          seed_labkit_counter('rack_request', 'burst_traffic_per_user_free_plan', 100, key: user_key)

          expect_rejection('burst_traffic_per_user_free_plan') do
            get path, headers: headers
          end
        end
      end
    end

    it 'counts nothing in the plan rules while the flag is off' do
      stub_feature_flags(rate_limiter_plan_limits_free_info: false)

      get path, headers: headers

      expect(counter_for('sustained_traffic_per_user_free_plan_log')).to eq(0)
      expect(counter_for('authenticated_api')).to eq(1)
    end
  end

  describe 'the per-plan MCP throttles', :saas_gitlab_com_subscriptions do
    let_it_be(:user) { create(:user) }
    let_it_be(:token) { create(:oauth_access_token, user: user, scopes: [:mcp]) }
    let_it_be(:ultimate_group) { create(:group) }
    let_it_be(:ultimate_user) { create(:user) }
    let_it_be(:ultimate_token) { create(:oauth_access_token, user: ultimate_user, scopes: [:mcp]) }

    let(:path) { '/api/v4/mcp' }
    let(:headers) { { 'Authorization' => "Bearer #{token.plaintext_token}" } }
    let(:ultimate_headers) { { 'Authorization' => "Bearer #{ultimate_token.plaintext_token}" } }

    before_all do
      create(:gitlab_subscription, :ultimate, namespace: ultimate_group)
      create(:group_member, :developer, group: ultimate_group, user: ultimate_user)
    end

    before do
      stub_saas_features(gitlab_com_subscriptions: true)
      stub_application_setting(throttle_authenticated_mcp_enabled: false)
      stub_feature_flags(
        rate_limiter_mcp_limits_free_info: true,
        rate_limiter_mcp_limits_free_enforce: true,
        rate_limiter_mcp_limits_premium_info: true,
        rate_limiter_mcp_limits_premium_enforce: true,
        rate_limiter_mcp_limits_ultimate_info: true,
        rate_limiter_mcp_limits_ultimate_enforce: true
      )
      Gitlab::RackAttack::LabkitRateLimit::Limiters.reset!
    end

    after do
      Gitlab::RackAttack::LabkitRateLimit::Limiters.reset!
    end

    it 'counts a free requester in the free rule with the setting off', :aggregate_failures do
      post path, headers: headers

      counts = labkit_counts_for('rack_request')

      expect(counts['burst_mcp_traffic_per_user_free_plan']).to eq(1)
      expect(counts['burst_mcp_traffic_per_user_premium_plan']).to be_nil
      expect(labkit_counts_for('rack_request_mcp')['authenticated_mcp']).to be_nil
    end

    it 'counts an ultimate requester in the ultimate rule, not the free one', :aggregate_failures do
      post path, headers: ultimate_headers

      counts = labkit_counts_for('rack_request')

      expect(counts['burst_mcp_traffic_per_user_ultimate_plan']).to eq(1)
      expect(counts['burst_mcp_traffic_per_user_free_plan']).to be_nil
    end

    it 'lets an ultimate requester past the free ceiling' do
      seed_labkit_counter('rack_request', 'burst_mcp_traffic_per_user_ultimate_plan', 60,
        key: "requester_type:user:requester_id:#{ultimate_user.id}")

      post path, headers: ultimate_headers

      expect(response).not_to have_gitlab_http_status(:too_many_requests)
    end

    it 'rejects an ultimate requester past 600 a minute', :aggregate_failures do
      seed_labkit_counter('rack_request', 'burst_mcp_traffic_per_user_ultimate_plan', 600,
        key: "requester_type:user:requester_id:#{ultimate_user.id}")

      post path, headers: ultimate_headers

      expect(response).to have_gitlab_http_status(:too_many_requests)
      expect(response.headers['RateLimit-Name']).to eq('burst_mcp_traffic_per_user_ultimate_plan')
      expect(response.headers['RateLimit-Limit']).to eq('600')
    end

    context 'when the general plan rules are also counting' do
      before do
        stub_feature_flags(rate_limiter_plan_limits_free_info: true)
        Gitlab::RackAttack::LabkitRateLimit::Limiters.reset!
      end

      it 'counts the request in the MCP rule and the general plan rules', :aggregate_failures do
        post path, headers: headers

        counts = labkit_counts_for('rack_request')

        expect(counts['burst_mcp_traffic_per_user_free_plan']).to eq(1)
        expect(counts['burst_traffic_per_user_free_plan_log']).to eq(1)
        expect(counts['sustained_traffic_per_user_free_plan_log']).to eq(1)
      end
    end

    it 'rejects a free requester past 60 a minute' do
      seed_labkit_counter('rack_request', 'burst_mcp_traffic_per_user_free_plan', 60,
        key: "requester_type:user:requester_id:#{user.id}")

      post path, headers: headers

      expect(response).to have_gitlab_http_status(:too_many_requests)
      expect(response.headers['RateLimit-Name']).to eq('burst_mcp_traffic_per_user_free_plan')
      expect(response.headers['RateLimit-Limit']).to eq('60')
    end

    it 'counts the MCP rules on the general limiter', :aggregate_failures do
      post path, headers: headers

      expect(labkit_counts_for('rack_request').keys).to include('burst_mcp_traffic_per_user_free_plan')
      expect(labkit_counts_for('rack_request_mcp').keys.grep(/burst_mcp/)).to be_empty
    end

    context 'when an admin enables the MCP throttle setting' do
      before do
        stub_application_setting(
          throttle_authenticated_mcp_enabled: true,
          throttle_authenticated_mcp_requests_per_period: 1000,
          throttle_authenticated_mcp_period_in_seconds: 60
        )
      end

      it 'counts in the plan rule and the setting-driven rule', :aggregate_failures do
        post path, headers: headers

        expect(labkit_counts_for('rack_request')['burst_mcp_traffic_per_user_free_plan']).to eq(1)
        expect(labkit_counts_for('rack_request_mcp')['authenticated_mcp']).to eq(1)
      end
    end

    context 'when the plan enforce flag is off' do
      before do
        stub_feature_flags(rate_limiter_mcp_limits_free_enforce: false)
      end

      it 'counts in the log twin and never rejects', :aggregate_failures do
        seed_labkit_counter('rack_request', 'burst_mcp_traffic_per_user_free_plan_log', 60,
          key: "requester_type:user:requester_id:#{user.id}")

        post path, headers: headers

        expect(response).not_to have_gitlab_http_status(:too_many_requests)
        expect(labkit_counts_for('rack_request')['burst_mcp_traffic_per_user_free_plan_log']).to eq(61)
      end
    end

    context 'when the plan info flag is off' do
      before do
        stub_feature_flags(rate_limiter_mcp_limits_free_info: false)
      end

      it 'counts in neither the free rule nor its twin', :aggregate_failures do
        post path, headers: headers

        counts = labkit_counts_for('rack_request')

        expect(counts['burst_mcp_traffic_per_user_free_plan']).to be_nil
        expect(counts['burst_mcp_traffic_per_user_free_plan_log']).to be_nil
      end
    end

    it 'counts no sustained MCP rule while its flags are off' do
      post path, headers: headers

      expect(labkit_counts_for('rack_request').keys.grep(/sustained_mcp/)).to be_empty
    end

    context 'when the sustained MCP flags are on' do
      let_it_be(:premium_group) { create(:group) }
      let_it_be(:premium_user) { create(:user) }
      let_it_be(:premium_token) { create(:oauth_access_token, user: premium_user, scopes: [:mcp]) }

      let(:premium_headers) { { 'Authorization' => "Bearer #{premium_token.plaintext_token}" } }

      before_all do
        create(:gitlab_subscription, :premium, namespace: premium_group)
        create(:group_member, :developer, group: premium_group, user: premium_user)
      end

      before do
        stub_feature_flags(
          rate_limiter_mcp_sustained_limits_free_info: true,
          rate_limiter_mcp_sustained_limits_free_enforce: true,
          rate_limiter_mcp_sustained_limits_premium_info: true,
          rate_limiter_mcp_sustained_limits_premium_enforce: true,
          rate_limiter_mcp_sustained_limits_ultimate_info: true,
          rate_limiter_mcp_sustained_limits_ultimate_enforce: true
        )
        Gitlab::RackAttack::LabkitRateLimit::Limiters.reset!
      end

      it 'rejects a premium requester past 5,000 an hour', :aggregate_failures do
        seed_labkit_counter('rack_request', 'sustained_mcp_traffic_per_user_premium_plan', 5_000,
          key: "requester_type:user:requester_id:#{premium_user.id}")

        post path, headers: premium_headers

        expect(response).to have_gitlab_http_status(:too_many_requests)
        expect(response.headers['RateLimit-Name']).to eq('sustained_mcp_traffic_per_user_premium_plan')
      end

      it 'lets a premium requester past the free hourly ceiling' do
        seed_labkit_counter('rack_request', 'sustained_mcp_traffic_per_user_premium_plan', 3_600,
          key: "requester_type:user:requester_id:#{premium_user.id}")

        post path, headers: premium_headers

        expect(response).not_to have_gitlab_http_status(:too_many_requests)
      end

      it 'rejects an ultimate requester past 5,000 an hour', :aggregate_failures do
        seed_labkit_counter('rack_request', 'sustained_mcp_traffic_per_user_ultimate_plan', 5_000,
          key: "requester_type:user:requester_id:#{ultimate_user.id}")

        post path, headers: ultimate_headers

        expect(response).to have_gitlab_http_status(:too_many_requests)
        expect(response.headers['RateLimit-Name']).to eq('sustained_mcp_traffic_per_user_ultimate_plan')
      end

      it 'lets an ultimate requester past the free hourly ceiling' do
        seed_labkit_counter('rack_request', 'sustained_mcp_traffic_per_user_ultimate_plan', 3_600,
          key: "requester_type:user:requester_id:#{ultimate_user.id}")

        post path, headers: ultimate_headers

        expect(response).not_to have_gitlab_http_status(:too_many_requests)
      end

      context 'when the general plan rules are also counting' do
        before do
          stub_feature_flags(rate_limiter_plan_limits_ultimate_info: true)
          Gitlab::RackAttack::LabkitRateLimit::Limiters.reset!
        end

        it 'counts an allowed request in the MCP and general rules', :aggregate_failures do
          post path, headers: ultimate_headers

          counts = labkit_counts_for('rack_request')

          expect(counts['sustained_mcp_traffic_per_user_ultimate_plan']).to eq(1)
          expect(counts['burst_mcp_traffic_per_user_ultimate_plan']).to eq(1)
          expect(counts['sustained_traffic_per_user_ultimate_plan_log']).to eq(1)
        end

        it 'does not count a rejected request in the general hourly rule' do
          seed_labkit_counter('rack_request', 'sustained_mcp_traffic_per_user_ultimate_plan', 5_000,
            key: "requester_type:user:requester_id:#{ultimate_user.id}")

          post path, headers: ultimate_headers

          expect(labkit_counts_for('rack_request')['sustained_traffic_per_user_ultimate_plan_log']).to be_nil
        end
      end

      context 'when the sustained enforce flag is off' do
        before do
          stub_feature_flags(rate_limiter_mcp_sustained_limits_free_enforce: false)
        end

        it 'counts in the log twin and never rejects', :aggregate_failures do
          seed_labkit_counter('rack_request', 'sustained_mcp_traffic_per_user_free_plan_log', 3_600,
            key: "requester_type:user:requester_id:#{user.id}")

          post path, headers: headers

          expect(response).not_to have_gitlab_http_status(:too_many_requests)
          expect(labkit_counts_for('rack_request')['sustained_mcp_traffic_per_user_free_plan_log']).to eq(3_601)
          expect(labkit_counts_for('rack_request')['sustained_mcp_traffic_per_user_free_plan']).to be_nil
        end
      end
    end

    context 'when not on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        stub_application_setting(
          throttle_authenticated_mcp_enabled: true,
          throttle_authenticated_mcp_requests_per_period: 1000,
          throttle_authenticated_mcp_period_in_seconds: 60
        )
        Gitlab::RackAttack::LabkitRateLimit::Limiters.reset!
      end

      it 'counts in the setting-driven rule only', :aggregate_failures do
        post path, headers: headers

        expect(labkit_counts_for('rack_request')['burst_mcp_traffic_per_user_free_plan']).to be_nil
        expect(labkit_counts_for('rack_request_mcp')['authenticated_mcp']).to eq(1)
      end
    end
  end
end
