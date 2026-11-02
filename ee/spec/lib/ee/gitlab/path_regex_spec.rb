# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::PathRegex, feature_category: :virtual_registry do
  describe '.oci_tag_regex' do
    subject { %r{\A#{described_class.oci_tag_regex}\z} }

    it { is_expected.to match('latest') }
    it { is_expected.to match('v1.2.3') }
    it { is_expected.to match('feature-branch') }
    it { is_expected.to match('feature_branch') }
    it { is_expected.to match('_internal') }
    it { is_expected.to match('v1.2.3-rc.1_build.123') }
    it { is_expected.to match('1.0') }
    it { is_expected.to match('_') }

    # Maximum length is 128 characters
    it { is_expected.to match('a' * 128) }
    it { is_expected.not_to match('a' * 129) }

    # Invalid tags
    it { is_expected.not_to match('-invalid') } # cannot start with hyphen
    it { is_expected.not_to match('.invalid') } # cannot start with period
    it { is_expected.not_to match('') } # cannot be empty
    it { is_expected.not_to match('tag with spaces') }
    it { is_expected.not_to match('tag/with/slash') }
  end

  describe '.oci_digest_regex' do
    subject { %r{\A#{described_class.oci_digest_regex}\z} }

    # Valid sha256 digests
    it { is_expected.to match("sha256:#{'a' * 64}") }
    it { is_expected.to match("sha256:#{'0' * 64}") }
    it { is_expected.to match('sha256:14119a10abf4669e8cdbdff324a9f9605d99697215a0d21c360fe8dfa8471bab') }

    # Invalid digests
    it { is_expected.not_to match("sha256:#{'a' * 63}") } # too short
    it { is_expected.not_to match("sha256:#{'a' * 65}") } # too long
    it { is_expected.not_to match("sha256:#{'A' * 64}") } # uppercase not allowed
    it { is_expected.not_to match("sha256:#{'g' * 64}") } # invalid hex character
    it { is_expected.not_to match("md5:#{'a' * 32}") } # wrong algorithm
    it { is_expected.not_to match('sha256:') } # missing hash
  end

  describe '.oci_tag_or_digest_regex' do
    subject { %r{\A#{described_class.oci_tag_or_digest_regex}\z} }

    # Valid tags
    it { is_expected.to match('latest') }
    it { is_expected.to match('v1.2.3') }
    it { is_expected.to match('feature-branch') }

    # Valid digests
    it { is_expected.to match("sha256:#{'a' * 64}") }
    it { is_expected.to match('sha256:14119a10abf4669e8cdbdff324a9f9605d99697215a0d21c360fe8dfa8471bab') }

    # Invalid
    it { is_expected.not_to match('-invalid') }
    it { is_expected.not_to match("sha256:#{'a' * 63}") }
    it { is_expected.not_to match("md5:#{'a' * 32}") }
  end

  describe '.oci_blob_digest_regex' do
    subject { %r{\A#{described_class.oci_blob_digest_regex}\z} }

    # Valid sha256 digests (any length for blobs)
    it { is_expected.to match("sha256:#{'a' * 64}") }
    it { is_expected.to match('sha256:14119a10abf4669e8cdbdff324a9f9605d99697215a0d21c360fe8dfa8471bab') }
    it { is_expected.to match('sha256:abc123def456') } # short form also valid for blobs
    it { is_expected.to match('sha256:abc') } # even shorter

    # md5 is not a registered algorithm but the spec says the regexp should accept it:
    # https://github.com/opencontainers/image-spec/blob/main/descriptor.md#digests
    # Implementations SHOULD allow digests with unrecognized algorithms to pass validation
    # if they comply with the above grammar.
    it { is_expected.to match('md5:abc123') }

    # Valid alternative digest formats (for blobs)
    it { is_expected.to match('sha512:abc123') }
    it { is_expected.to match('sha1:abc123') }
    it { is_expected.to match('algorithm+variant:hash') }

    # Invalid - must have algorithm and hash separated by colon
    it { is_expected.not_to match('sha256:') } # missing hash
    it { is_expected.not_to match(':nocolon') } # missing algorithm
    it { is_expected.not_to match('nohash:') } # missing hash
    it { is_expected.not_to match('') } # empty
  end

  describe '.pipeline_trigger_api_route_regex', feature_category: :rate_limiting do
    subject { described_class.pipeline_trigger_api_route_regex }

    it { is_expected.to match('/api/v4/projects/42/trigger/pipeline') }
    it { is_expected.to match('/api/v4/projects/42/trigger/pipeline.json') }
    it { is_expected.to match('/api/v4/projects/group%2Fproject/trigger/pipeline') }
    it { is_expected.to match('/api/v4/projects/42/ref/main/trigger/pipeline') }
    it { is_expected.to match('/api/v4/projects/42/ref/feature/login/trigger/pipeline') }

    it { is_expected.not_to match('/api/v4/projects/42/triggers') }
    it { is_expected.not_to match('/api/v4/projects/42/triggers/7') }
    it { is_expected.not_to match('/api/v4/projects/42/pipeline') }
    it { is_expected.not_to match('/api/v4/projects/42/trigger/pipelines') }
    it { is_expected.not_to match('/api/v4/projects/42/trigger/pipeline/extra') }
    it { is_expected.not_to match('/api/v4/projects/trigger/pipeline') }
    it { is_expected.not_to match('/api/v3/projects/42/trigger/pipeline') }
    it { is_expected.not_to match('/group/api/v4/projects/42/trigger/pipeline') }
  end

  describe '.runner_registration_api_route_regex', feature_category: :rate_limiting do
    subject { described_class.runner_registration_api_route_regex }

    it { is_expected.to match('/api/v4/runners') }
    it { is_expected.to match('/api/v4/runners.json') }

    it { is_expected.not_to match('/api/v4/runners/') }
    it { is_expected.not_to match('/api/v4/runners/verify') }
    it { is_expected.not_to match('/api/v4/runners/router/discovery') }
    it { is_expected.not_to match('/api/v4/runners/1') }
    it { is_expected.not_to match('/api/v4/runners/all') }
    it { is_expected.not_to match('/api/v4/projects/1/runners') }
    it { is_expected.not_to match('/api/v3/runners') }
    it { is_expected.not_to match('/group/api/v4/runners') }
  end

  describe '.unleash_api_route_regex', feature_category: :rate_limiting do
    subject { described_class.unleash_api_route_regex }

    it { is_expected.to match('/api/v4/feature_flags/unleash/42') }
    it { is_expected.to match('/api/v4/feature_flags/unleash/42/features') }
    it { is_expected.to match('/api/v4/feature_flags/unleash/42/client/features') }
    it { is_expected.to match('/api/v4/feature_flags/unleash/42/client/register') }
    it { is_expected.to match('/api/v4/feature_flags/unleash/42/client/metrics') }
    it { is_expected.to match('/api/v4/feature_flags/unleash/group%2Fproject/client/features') }
    it { is_expected.to match('/api/v4/feature_flags/unleash/42/client/features.json') }

    it { is_expected.not_to match('/api/v4/feature_flags/unleash') }
    it { is_expected.not_to match('/api/v4/feature_flags/unleashed/42') }
    it { is_expected.not_to match('/api/v4/projects/42/feature_flags') }
    it { is_expected.not_to match('/api/v3/feature_flags/unleash/42/client/features') }
    it { is_expected.not_to match('/group/api/v4/feature_flags/unleash/42') }
  end

  describe '.jira_connect_atlassian_route_regex', feature_category: :rate_limiting do
    subject { described_class.jira_connect_atlassian_route_regex }

    it { is_expected.to match('/-/jira_connect/workspaces/search') }
    it { is_expected.to match('/-/jira_connect/repositories/search') }
    it { is_expected.to match('/-/jira_connect/repositories/associate') }
    it { is_expected.to match('/-/jira_connect/repositories/search.json') }
    it { is_expected.to match('/o/my-org/-/jira_connect/repositories/associate') }

    it { is_expected.not_to match('/-/jira_connect/events/installed') }
    it { is_expected.not_to match('/-/jira_connect/events/uninstalled') }
    it { is_expected.not_to match('/-/jira_connect/subscriptions') }
    it { is_expected.not_to match('/-/jira_connect/oauth_callbacks') }
    it { is_expected.not_to match('/-/jira_connect/branches/new') }
    it { is_expected.not_to match('/-/jira_connect/branches/route') }
    it { is_expected.not_to match('/-/jira_connect/installations') }
    it { is_expected.not_to match('/-/jira_connect/app_descriptor') }
    it { is_expected.not_to match('/-/jira_connect/workspaces/searchx') }
    it { is_expected.not_to match('/jira_connect/workspaces/search') }
    it { is_expected.not_to match('/group/project/-/jira_connect/workspaces/search') }
  end

  describe '.jira_connect_branch_route_regex', feature_category: :rate_limiting do
    subject { described_class.jira_connect_branch_route_regex }

    it { is_expected.to match('/-/jira_connect/branches/route') }
    it { is_expected.to match('/o/my-org/-/jira_connect/branches/route') }

    it { is_expected.not_to match('/-/jira_connect/branches/new') }
    it { is_expected.not_to match('/-/jira_connect/branches/routex') }
    it { is_expected.not_to match('/-/jira_connect/branches/route.json') }
    it { is_expected.not_to match('/-/jira_connect/workspaces/search') }
    it { is_expected.not_to match('/jira_connect/branches/route') }
    it { is_expected.not_to match('/group/project/-/jira_connect/branches/route') }
  end

  describe '.deprecated_secure_files_installer_route_regex', feature_category: :rate_limiting do
    subject { described_class.deprecated_secure_files_installer_route_regex }

    let(:download) { '/gitlab-org/incubation-engineering/mobile-devops/download-secure-files' }
    let(:load) { '/gitlab-org/incubation-engineering/mobile-devops/load-secure-files' }

    it 'matches each request of the install in both projects', :aggregate_failures do
      { download => 'dist', load => 'releases' }.each do |project, dir|
        is_expected.to match("#{project}/-/raw/main/installer")
        is_expected.to match("#{project}/-/releases/permalink/latest/downloads/binary")
        is_expected.to match("#{project}/-/releases/v0.1.16/downloads/binary")
        is_expected.to match("#{project}/-/jobs/artifacts/main/raw/#{dir}/binary")
        is_expected.to match("#{project}/-/jobs/11482053960/artifacts/raw/#{dir}/binary")
      end
    end

    it 'does not match other files, refs or pages in those projects', :aggregate_failures do
      is_expected.not_to match(download)
      is_expected.not_to match("#{download}/-/issues")
      is_expected.not_to match("#{download}/-/raw/main/README.md")
      is_expected.not_to match("#{download}/-/raw/feature/installer")
      is_expected.not_to match("#{download}/-/blob/main/installer")
      is_expected.not_to match("#{download}/-/releases")
      is_expected.not_to match("#{download}/-/releases/v0.1.16")
      is_expected.not_to match("#{download}/-/releases/v0.1.16/downloads/dist/binary")
      is_expected.not_to match("#{download}/-/jobs/artifacts/main/download")
      is_expected.not_to match("#{download}/-/jobs/artifacts/main/raw/src/main.go")
      is_expected.not_to match("#{download}/-/jobs/artifacts/feature/raw/dist/binary")
      is_expected.not_to match("#{download}/-/jobs/123/artifacts/download")
      is_expected.not_to match("#{download}/-/jobs/123/artifacts/browse")
      is_expected.not_to match("#{download}/-/jobs/123/artifacts/raw/dist/sub/binary")
      is_expected.not_to match("#{load}/-/tree/main")
    end

    it 'does not match the same paths in other projects', :aggregate_failures do
      is_expected.not_to match('/gitlab-org/gitlab/-/raw/main/installer')
      is_expected.not_to match("#{download}-fork/-/raw/main/installer")
      is_expected.not_to match("/group#{download}/-/raw/main/installer")
      is_expected.not_to match("/api/v4/projects/1#{download}/-/raw/main/installer")
    end
  end

  describe '.group_scim_api_route_regex', feature_category: :rate_limiting do
    subject { described_class.group_scim_api_route_regex }

    it { is_expected.to match('/api/scim/v2/groups/my-group/Users') }
    it { is_expected.to match('/api/scim/v2/groups/my-group/Users.json') }
    it { is_expected.to match('/api/scim/v2/groups/my-group/Users/0b1d561c-21ff-4092-beab-8154b17f82f2') }
    it { is_expected.to match('/api/scim/v2/groups/my.group/Users/42') }

    it { is_expected.not_to match('/api/scim/v1/groups/my-group/Users') }
    it { is_expected.not_to match('/api/scim/V2/groups/my-group/Users') }
    it { is_expected.not_to match('/api/scim/v2/groups/my-group') }
    it { is_expected.not_to match('/api/scim/v2/groups/my-group/Usersx') }
    it { is_expected.not_to match('/api/scim/v2/groups/my-group/users') }
    it { is_expected.not_to match('/api/scim/v2/groups/parent/child/Users') }
    it { is_expected.not_to match('/api/scim/v2/application/Users') }
    it { is_expected.not_to match('/api/v4/groups/my-group/Users') }
    it { is_expected.not_to match('/group/api/scim/v2/groups/my-group/Users') }
  end

  describe '.slack_app_api_route_regex', feature_category: :rate_limiting do
    subject { described_class.slack_app_api_route_regex }

    it { is_expected.to match('/api/v4/slack/trigger') }
    it { is_expected.to match('/api/v4/slack/trigger.json') }
    it { is_expected.to match('/api/v4/integrations/slack/events') }
    it { is_expected.to match('/api/v4/integrations/slack/interactions') }
    it { is_expected.to match('/api/v4/integrations/slack/options') }

    it { is_expected.not_to match('/api/v3/slack/trigger') }
    it { is_expected.not_to match('/api/v3/integrations/slack/events') }
    it { is_expected.not_to match('/api/v4/slack/triggered') }
    it { is_expected.not_to match('/api/v4/slack/trigger/extra') }
    it { is_expected.not_to match('/api/v4/integrations/jira_connect/subscriptions') }
    it { is_expected.not_to match('/api/v4/projects/1/integrations/slack') }
    it { is_expected.not_to match('/group/api/v4/slack/trigger') }
  end

  describe '.alert_notification_route_regex', feature_category: :rate_limiting do
    subject { described_class.alert_notification_route_regex }

    it { is_expected.to match('/group/project/alerts/notify') }
    it { is_expected.to match('/group/project/alerts/notify.json') }
    it { is_expected.to match('/group/subgroup/project/alerts/notify') }
    it { is_expected.to match('/group/project/alerts/notify/my-integration/a1b2c3d4e5f6') }
    it { is_expected.to match('/group/project/alerts/notify/my-integration/a1b2c3d4e5f6.json') }
    it { is_expected.to match('/group/project/prometheus/alerts/notify') }
    it { is_expected.to match('/group/project/prometheus/alerts/notify.json') }

    it { is_expected.to match('/blob/project/alerts/notify') }

    it { is_expected.not_to match('/group/project/-/blob/main/alerts/notify') }
    it { is_expected.not_to match('/group/project/blob/main/alerts/notify') }
    it { is_expected.not_to match('/group/project/raw/main/alerts/notify') }
    it { is_expected.not_to match('/group/project/tree/main/alerts/notify') }
    it { is_expected.not_to match('/group/project/blame/main/alerts/notify') }
    it { is_expected.not_to match('/group/project/commits/main/alerts/notify') }
    it { is_expected.not_to match('/group/project/find_file/main/alerts/notify') }
    it { is_expected.not_to match('/group/project/environments/folders/alerts/notify') }
    it { is_expected.not_to match('/mygroup/alerts/notify') }
    it { is_expected.not_to match('/group/project/-/alerts/notify') }
    it { is_expected.not_to match('/api/v4/projects/1/alerts/notify') }
    it { is_expected.not_to match('/group/project/alerts/notify/my-integration/not-alphanumeric') }
    it { is_expected.not_to match('/group/project/alerts/notify/extra') }
    it { is_expected.not_to match('/group/project/alerts/notifyx') }
    it { is_expected.not_to match('/alerts/notify') }
  end

  describe '.mailgun_webhook_route_regex', feature_category: :rate_limiting do
    subject { described_class.mailgun_webhook_route_regex }

    it { is_expected.to match('/-/mailgun/webhooks') }
    it { is_expected.to match('/-/mailgun/webhooks.json') }
    it { is_expected.to match('/-/members/mailgun/permanent_failures') }

    it { is_expected.not_to match('/-/mailgun/webhooks/extra') }
    it { is_expected.not_to match('/mailgun/webhooks') }
    it { is_expected.not_to match('/group/-/mailgun/webhooks') }
    it { is_expected.not_to match('/-/members/mailgun') }
  end

  describe '.home_page_route_regex', feature_category: :rate_limiting do
    subject { described_class.home_page_route_regex }

    it { is_expected.to match('/') }

    it { is_expected.not_to match('/o/my-org') }
    it { is_expected.not_to match('/o/my-org/') }
    it { is_expected.not_to match('/explore') }
    it { is_expected.not_to match('/group') }
    it { is_expected.not_to match('/o/my-org/group') }
    it { is_expected.not_to match('/o/') }
    it { is_expected.not_to match('/users/sign_in') }
  end

  describe '.sign_up_flow_route_regex', feature_category: :rate_limiting do
    subject { described_class.sign_up_flow_route_regex }

    it { is_expected.to match('/users') }
    it { is_expected.to match('/o/my-org/users') }
    it { is_expected.to match('/users/sign_up') }
    it { is_expected.to match('/o/my-org/users/sign_up') }
    it { is_expected.to match('/users/password/complexity') }
    it { is_expected.to match('/users/john.doe/exists') }
    it { is_expected.to match('/users/john_doe-1/exists.json') }
    # The browser's pattern allows these endings, so the form sends the check before the server rejects the name.
    it { is_expected.to match('/users/user.git/exists') }
    it { is_expected.to match('/users/user.atom/exists') }
    it { is_expected.to match('/users/identity_verification') }
    it { is_expected.to match('/users/identity_verification/verify_email_code') }
    it { is_expected.to match('/users/identity_verification/verification_state.json') }
    it { is_expected.to match('/o/my-org/users/identity_verification/success') }
    it { is_expected.to match('/users/sign_up.json') }
    it { is_expected.to match('/users/almost_there') }
    it { is_expected.to match('/-/subscriptions/payment_form') }
    it { is_expected.to match('/-/subscriptions/validate_payment_method') }
    it { is_expected.to match('/-/invites/AbC_123-xyz') }
    it { is_expected.to match('/o/my-org/-/invites/AbC_123-xyz') }
    it { is_expected.to match('/-/arkose/data_exchange_payload') }
    it { is_expected.to match('/o/my-org/-/arkose/data_exchange_payload') }

    it { is_expected.not_to match('/users/sign_up/welcome') }
    it { is_expected.not_to match('/users/sign_upx') }
    it { is_expected.not_to match('/users/-john/exists') }
    it { is_expected.not_to match('/users/john./exists') }
    it { is_expected.not_to match('/users/john/exists/extra') }
    it { is_expected.not_to match('/users/a/b/exists') }
    it { is_expected.not_to match('/users/identity_verification/a/b') }
    it { is_expected.not_to match('/users/identity_verification/unknown_action') }
    it { is_expected.not_to match('/users/identity_verification/success/extra') }
    it { is_expected.not_to match('/-/subscriptions/new') }
    it { is_expected.not_to match('/-/subscriptions/buy_minutes') }
    it { is_expected.not_to match('/-/invites/abc/accept') }
    it { is_expected.not_to match('/-/invites/abc/decline') }
    it { is_expected.not_to match('/-/invites/a.b') }
    it { is_expected.not_to match('/-/identity_verification') }
    it { is_expected.not_to match('/arkose/data_exchange_payload') }
    it { is_expected.not_to match('/group/users/sign_up') }
    it { is_expected.not_to match('/o/admin/users/sign_up') }
    it { is_expected.not_to match('/o/my.org/users/sign_up') }

    it 'matches every sign-up identity verification route' do
      routes = Rails.application.routes.routes.select do |route|
        route.defaults[:controller] == 'users/registrations_identity_verification' &&
          !route.path.spec.to_s.start_with?('/o/')
      end

      expect(routes).not_to be_empty

      routes.each do |route|
        path = route.path.spec.to_s.delete_suffix('(.:format)')

        expect(described_class.sign_up_flow_route_regex).to match(path), "#{route.verb} #{path} is not covered"
      end
    end
  end

  describe '.account_recovery_route_regex', feature_category: :rate_limiting do
    subject { described_class.account_recovery_route_regex }

    it { is_expected.to match('/users/password/new') }
    it { is_expected.to match('/users/password/edit') }
    it { is_expected.to match('/users/confirmation/new') }
    it { is_expected.to match('/users/unlock/new') }
    it { is_expected.to match('/o/my-org/users/password/new') }
    it { is_expected.to match('/users/password') }
    it { is_expected.to match('/users/confirmation') }
    it { is_expected.to match('/users/unlock') }
    it { is_expected.to match('/o/my-org/users/confirmation') }

    it { is_expected.not_to match('/users/passwordx') }
    it { is_expected.not_to match('/users/confirmation/edit') }
    it { is_expected.not_to match('/users/unlock/edit') }
    it { is_expected.not_to match('/users/password/new/extra') }
    it { is_expected.not_to match('/group/users/password/new') }
  end

  describe '.trial_registration_route_regex', feature_category: :rate_limiting do
    subject { described_class.trial_registration_route_regex }

    it { is_expected.to match('/-/trial_registrations') }
    it { is_expected.to match('/-/trial_registrations/new') }
    it { is_expected.to match('/o/my-org/-/trial_registrations/new') }

    it { is_expected.not_to match('/-/trial_registrations/new/extra') }
    it { is_expected.not_to match('/-/trial_registrations/edit') }
    it { is_expected.not_to match('/-/trial_registrationsx') }
    it { is_expected.not_to match('/-/trial_registrations/newx') }
    it { is_expected.not_to match('/trial_registrations/new') }
  end

  describe '.haproxy_api_health_check_route_regex', feature_category: :rate_limiting do
    subject { described_class.haproxy_api_health_check_route_regex }

    it { is_expected.to match('/-/k8s/api/-/readiness') }

    it { is_expected.not_to match('/-/k8s/api/-/readiness/extra') }
    it { is_expected.not_to match('/-/k8s/api/-/liveness') }
    it { is_expected.not_to match('/-/k8s/web/-/readiness') }
    it { is_expected.not_to match('/group/-/k8s/api/-/readiness') }
  end

  describe '.git_operation_continuation_route_regex', feature_category: :rate_limiting do
    subject { described_class.git_operation_continuation_route_regex }

    let(:lfs_oid) { Digest::SHA256.hexdigest('lfs object') }

    it { is_expected.to match('/group/project.git/git-upload-pack') }
    it { is_expected.to match('/group/project.git/git-receive-pack') }
    it { is_expected.to match('/group/subgroup/project.git/git-upload-pack') }
    it { is_expected.to match('/gitlab-org/gitlab-foss.git/git-upload-pack') }
    it { is_expected.to match('/group/project.wiki.git/git-upload-pack') }
    it { is_expected.to match('/snippets/1.git/git-upload-pack') }
    it { is_expected.to match('/group/project/snippets/1.git/git-receive-pack') }
    it { is_expected.to match("/group/project.git/gitlab-lfs/objects/#{lfs_oid}") }
    it { is_expected.to match("/group/project.git/gitlab-lfs/objects/#{lfs_oid}/1024/authorize") }
    it { is_expected.to match("/group/project.git/gitlab-lfs/objects/#{lfs_oid}/1024") }

    it { is_expected.not_to match('/group/project.git/info/refs') }
    it { is_expected.not_to match('/group/project.git/info/lfs/objects/batch') }
    it { is_expected.not_to match('/group/project.git/info/lfs/locks') }
    it { is_expected.not_to match('/group/project.git/info/lfs/locks/verify') }
    it { is_expected.not_to match('/group/project.git/ssh-upload-pack') }
    it { is_expected.not_to match('/group/project.git/git-upload-pack/extra') }
    it { is_expected.not_to match('/group/project.git/gitlab-lfs/objects/abc123') }
    it { is_expected.not_to match('/group/project/-/raw/main/file.git/git-upload-pack') }
    it { is_expected.not_to match('/api/v4/projects/1/repository/files/file.git/git-upload-pack') }
    it { is_expected.not_to match('/group/project/git-upload-pack') }
  end

  describe '.usage_data_telemetry_api_route_regex', feature_category: :rate_limiting do
    subject { described_class.usage_data_telemetry_api_route_regex }

    it { is_expected.to match('/api/v4/usage_data/track_event') }
    it { is_expected.to match('/api/v4/usage_data/track_event.json') }
    it { is_expected.to match('/api/v4/usage_data/track_events') }
    it { is_expected.to match('/api/v4/usage_data/track_events.json') }
    it { is_expected.to match('/api/v4/usage_data/increment_counter') }
    it { is_expected.to match('/api/v4/usage_data/increment_counter.json') }
    it { is_expected.to match('/api/v4/usage_data/increment_unique_users') }
    it { is_expected.to match('/api/v4/usage_data/increment_unique_users.json') }

    it { is_expected.not_to match('/api/v4/usage_data/metric_definitions') }
    it { is_expected.not_to match('/api/v4/usage_data/service_ping') }
    it { is_expected.not_to match('/api/v4/usage_data/queries') }
    it { is_expected.not_to match('/api/v4/usage_data/non_sql_metrics') }
    it { is_expected.not_to match('/api/v4/usage_data/track_eventss') }
    it { is_expected.not_to match('/api/v4/usage_data/track_event/extra') }
    it { is_expected.not_to match('/api/v3/usage_data/track_event') }
    it { is_expected.not_to match('/group/api/v4/usage_data/track_event') }
  end

  describe '.git_or_dependency_proxy_route_regex', feature_category: :rate_limiting do
    subject { described_class.git_or_dependency_proxy_route_regex }

    it { is_expected.to match('/group/project.git/info/refs') }
    it { is_expected.to match('/group/project/info/refs') }
    it { is_expected.to match('/group/project.git/git-upload-pack') }
    it { is_expected.to match('/group/project.git/info/lfs/objects/batch') }
    it { is_expected.to match('/group/project.git/gitlab-lfs/objects/abc') }
    it { is_expected.to match('/v2') }
    it { is_expected.to match('/v2/group/dependency_proxy/containers/alpine/manifests/latest') }

    it { is_expected.not_to match('/group/project') }
    it { is_expected.not_to match('/group/project/-/merge_requests/1') }
    it { is_expected.not_to match('/group/project/-/raw/main/file.git/git-upload-pack') }
    it { is_expected.not_to match('/api/v4/projects/1') }
    it { is_expected.not_to match('/v2/group/container_registry') }
    it { is_expected.not_to match('/user/user.gitlab.io/-/merge_requests/1') }
  end

  describe '.upload_or_pwa_manifest_route_regex', feature_category: :rate_limiting do
    subject { described_class.upload_or_pwa_manifest_route_regex }

    it { is_expected.to match('/-/project/1/uploads/0123abcd/image.png') }
    it { is_expected.to match('/-/group/1/uploads/0123abcd/image.png') }
    it { is_expected.to match('/o/my-org/-/project/1/uploads/0123abcd/image.png') }
    it { is_expected.to match('/group/project/uploads/0123abcd/image.png') }
    it { is_expected.to match('/group/subgroup/project/uploads/0123abcd/image.png') }
    it { is_expected.to match('/groups/group/subgroup/-/uploads/0123abcd/image.png') }
    it { is_expected.to match('/raw/project/uploads/0123abcd/image.png') }
    it { is_expected.to match('/group/project/-/wikis/uploads/0123abcd/image.png') }
    it { is_expected.to match('/groups/group/-/wikis/uploads/0123abcd/image.png') }
    it { is_expected.to match('/uploads/-/system/user/avatar/1/avatar.png') }
    it { is_expected.to match('/uploads/-/system/personal_snippet/1/0123abcd/image.png') }
    it { is_expected.to match('/-/manifest.json') }
    it { is_expected.to match('/o/my-org/-/manifest.json') }

    it { is_expected.not_to match('/group/project/-/blob/main/uploads/0123abcd/image.png') }
    it { is_expected.not_to match('/group/project/-/raw/main/uploads/0123abcd/image.png') }
    it { is_expected.not_to match('/group/project/raw/main/uploads/0123abcd/image.png') }
    it { is_expected.not_to match('/group/project/blob/main/uploads/0123abcd/image.png') }
    it { is_expected.not_to match('/group/project/tree/main/uploads/0123abcd/image.png') }
    it { is_expected.not_to match('/group/project/blame/main/uploads/0123abcd/image.png') }
    it { is_expected.not_to match('/api/v4/projects/1/uploads/0123abcd/image.png') }
    it { is_expected.not_to match('/group/uploads/-/issues') }
    it { is_expected.not_to match('/group/subgroup/uploads/tree/main') }
    it { is_expected.not_to match('/group/project/-/wikis/home') }
    it { is_expected.not_to match('/group/project/uploads') }
    it { is_expected.not_to match('/group/project/uploads/authorize') }
    it { is_expected.not_to match('/-/manifest') }
    it { is_expected.not_to match('/-/offline') }
  end

  describe '.sign_in_flow_route_regex', feature_category: :rate_limiting do
    it 'matches the sign-in flow whichever providers are configured' do
      expect(described_class.sign_in_flow_route_regex).to match('/users/sign_in')
    end

    it 'is built from the configured providers' do
      expect(described_class.sign_in_flow_route_regex)
        .to eq(described_class.sign_in_flow_route_regex_for(Gitlab::Auth::OAuth::Provider.providers))
    end
  end

  describe '.sign_in_flow_route_regex_for', feature_category: :rate_limiting do
    subject { described_class.sign_in_flow_route_regex_for(%i[github google_oauth2 group_saml]) }

    it { is_expected.to match('/users/sign_in') }
    it { is_expected.to match('/o/my-org/users/sign_in') }
    it { is_expected.to match('/users/sign_in_path') }
    it { is_expected.to match('/users/passkeys/sign_in') }
    it { is_expected.to match('/users/resend_verification_code') }
    it { is_expected.to match('/users/fallback_to_email_otp') }
    it { is_expected.to match('/users/skip_verification_for_now') }
    it { is_expected.to match('/users/skip_verification_confirmation') }
    it { is_expected.to match('/users/successful_verification') }
    it { is_expected.to match('/o/my-org/users/passkeys/sign_in') }
    it { is_expected.to match('/oauth/authorize') }
    it { is_expected.to match('/o/my-org/oauth/authorize') }
    it { is_expected.to match('/groups/my-group/-/saml/sso') }
    it { is_expected.to match('/groups/my-group/-/saml/callback') }
    it { is_expected.to match('/groups/my.group/-/saml/sso') }
    it { is_expected.to match('/users/auth/github') }
    it { is_expected.to match('/users/auth/google_oauth2/callback') }
    it { is_expected.to match('/users/auth/group_saml') }

    it { is_expected.not_to match('/users/sign_in_path/extra') }
    it { is_expected.not_to match('/users/passkeys') }
    it { is_expected.not_to match('/users/sign_up') }
    it { is_expected.not_to match('/users/password') }
    it { is_expected.not_to match('/users/SIGN_IN') }
    it { is_expected.not_to match('/group/users/sign_in') }
    it { is_expected.not_to match('/oauth/authorize/native') }
    it { is_expected.not_to match('/oauth/authorize_device') }
    it { is_expected.not_to match('/oauth/authorized_applications') }
    it { is_expected.not_to match('/groups/parent/child/-/saml/sso') }
    it { is_expected.not_to match('/groups/parent/child/-/saml/callback') }
    it { is_expected.not_to match('/groups/parent%2Fchild/-/saml/sso') }
    it { is_expected.not_to match('/groups/parent%2Fchild/-/saml/callback') }
    it { is_expected.not_to match('/o/my-org/groups/my-group/-/saml/sso') }
    it { is_expected.not_to match('/groups/my-group/-/saml') }
    it { is_expected.not_to match('/groups/my-group/-/saml/unlink') }
    it { is_expected.not_to match('/groups/my-group/-/saml_group_links') }
    it { is_expected.not_to match('/users/auth/projects') }
    it { is_expected.not_to match('/users/auth/activity') }
    it { is_expected.not_to match('/users/auth/calendar.json') }
    it { is_expected.not_to match('/users/auth/unknown_provider') }
    it { is_expected.not_to match('/users/auth/openid_connect') }
    it { is_expected.not_to match('/users/auth/github/extra') }
    it { is_expected.not_to match('/users/auth/githubx/callback') }
  end

  describe '.oauth_token_grant_route_regex', feature_category: :rate_limiting do
    subject { described_class.oauth_token_grant_route_regex }

    it { is_expected.to match('/oauth/token') }
    it { is_expected.to match('/oauth/token.json') }
    it { is_expected.to match('/o/my-org/oauth/token') }
    it { is_expected.to match('/oauth/authorize_device') }
    it { is_expected.to match('/o/my-org/oauth/authorize_device') }

    it { is_expected.not_to match('/oauth/token/info') }
    it { is_expected.not_to match('/oauth/token/info.json') }
    it { is_expected.not_to match('/o/my-org/oauth/token/info') }
    it { is_expected.not_to match('/oauth/tokens') }
    it { is_expected.not_to match('/oauth/revoke') }
    it { is_expected.not_to match('/oauth/introspect') }
    it { is_expected.not_to match('/oauth/authorize') }
    it { is_expected.not_to match('/OAuth/token') }
    it { is_expected.not_to match('/api/v4/oauth/token') }
  end

  describe '.discovery_document_route_regex', feature_category: :rate_limiting do
    subject { described_class.discovery_document_route_regex }

    it { is_expected.to match('/.well-known/openid-configuration') }
    it { is_expected.to match('/.well-known/terraform.json') }
    it { is_expected.to match('/oauth/discovery/keys') }
    it { is_expected.to match('/.well-known/oauth-authorization-server') }
    it { is_expected.to match('/.well-known/oauth-protected-resource') }
    it { is_expected.to match('/.well-known/openid-configuration/api/v4/mcp') }
    it { is_expected.to match('/.well-known/oauth-authorization-server/api/v4/mcp') }
    it { is_expected.to match('/.well-known/oauth-protected-resource/api/v4/mcp') }
    it { is_expected.to match('/.well-known/openid-configuration/api/v4/orbit/mcp') }
    it { is_expected.to match('/.well-known/oauth-authorization-server/api/v4/orbit/mcp') }
    it { is_expected.to match('/.well-known/oauth-protected-resource/api/v4/orbit/mcp') }

    it { is_expected.not_to match('/.well-known/openid-configuration/extra') }
    it { is_expected.not_to match('/.well-known/openid-configuration/oauth/token') }
    it { is_expected.not_to match('/.well-known/oauth-protected-resource/api/v4') }
    it { is_expected.not_to match('/.well-known/oauth-protected-resource/group/project/api/v4/mcp') }
    it { is_expected.not_to match('/.well-known/oauth-protected-resource/api/v4/mcp/extra') }
    it { is_expected.not_to match('/.well-known/terraform.json/api/v4/mcp') }
    it { is_expected.not_to match('/.well-known/terraformXjson') }
    it { is_expected.not_to match('/.well-known/terraform.json/extra') }
    it { is_expected.not_to match('/.well-known/webfinger') }
    it { is_expected.not_to match('/oauth/discovery/keys/extra') }
    it { is_expected.not_to match('/oauth/userinfo') }
    it { is_expected.not_to match('/group/.well-known/openid-configuration') }
  end

  describe '.oauth_dynamic_registration_route_regex', feature_category: :rate_limiting do
    subject { described_class.oauth_dynamic_registration_route_regex }

    it { is_expected.to match('/oauth/register') }
    it { is_expected.to match('/oauth/register.json') }
    it { is_expected.to match('/o/my-org/oauth/register') }

    it { is_expected.not_to match('/oauth/register/extra') }
    it { is_expected.not_to match('/oauth/registers') }
    it { is_expected.not_to match('/oauth/registration') }
    it { is_expected.not_to match('/api/v4/oauth/register') }
  end
end
