# frozen_string_literal: true

module Gitlab
  # Shared by controllers and API endpoints. The host must provide `current_user`
  # and `check_rate_limit!` (CheckRateLimit or API::Helpers::RateLimiter), and a
  # block is handled the way that `check_rate_limit!` handles it.
  module NotesCreateRateLimit
    # A cost above the limit could never succeed, so it is capped at the limit.
    def check_notes_create_rate_limit!(cost: nil, &block)
      settings = Gitlab::CurrentSettings.current_application_settings

      options = {
        scope: { user: current_user },
        users_allowlist: settings.notes_create_limit_allowlist
      }
      options[:cost] = [cost, settings.notes_create_limit].min if cost

      check_rate_limit!(:notes_create, **options, &block)
    end
  end
end
