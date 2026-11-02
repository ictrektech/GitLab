#!/usr/bin/env ruby
# frozen_string_literal: true

# Shim, like seed_admin_token.rb: Caproni has no post-deploy hook, so activate GitLab Duo here.
# Ported from gitlab-qa's support/setup/gitlab_duo_setup.rb, which the omnibus scenario runs.
# https://gitlab.com/gitlab-org/caproni/-/issues/192
#
# Runs on its own, or together with other seeders through scripts/seed.rb

module SeedGitlabDuo
  # The CustomersDot endpoint behind the token sync is rate limited
  TOKEN_SYNC_ATTEMPTS = 3
  TOKEN_SYNC_RETRY_SECONDS = 30

  module_function

  def description
    'the GitLab Duo cloud license'
  end

  # inspect escapes the code, so a quote in it cannot break out.
  # A cloud license brings the Duo add-on purchase, so the suite's offline license is skipped.
  def seed_program(activation_code)
    <<~RUBY
      if License.current&.cloud_license?
        puts 'Cloud license already active, skipping activation'
      else
        result = ::GitlabSubscriptions::ActivateService.new.execute(#{activation_code.inspect})
        abort("Cloud license activation failed: \#{Array(result[:errors]).join(' ')}") unless result[:success]

        puts 'Cloud license activated'
      end

      # Synchronous, unlike the activation's own sync, so the suite never starts without a token
      response = nil
      synced = #{TOKEN_SYNC_ATTEMPTS}.times.any? do |attempt|
        sleep #{TOKEN_SYNC_RETRY_SECONDS} if attempt > 0
        next true if ::CloudConnector::ServiceAccessToken.active.exists?

        response = ::CloudConnector::SyncCloudConnectorAccessService.new(License.current).execute
        response.success?
      end
      abort("Failed to sync the Cloud Connector service access token: \#{response&.message}") unless synced

      puts 'Cloud Connector service access token synced'
    RUBY
  end

  def program_from_env
    code = ENV.fetch('QA_EE_ACTIVATION_CODE') { abort('QA_EE_ACTIVATION_CODE is not set') }

    seed_program(code)
  end
end

if __FILE__ == $PROGRAM_NAME
  # Here, not at the top: seed.rb loads this file, and must not load itself again
  require_relative 'seed'
  Seed.run([SeedGitlabDuo])
end
