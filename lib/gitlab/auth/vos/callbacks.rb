# frozen_string_literal: true

module Gitlab
  module Auth
    module Vos
      module Callbacks
        include Gitlab::ExclusiveLeaseHelpers

        # Switching VOS users must never link the new identity to the previous session's account.
        def vos
          in_lock("vos:identity:#{oauth.fetch('uid')}", ttl: 30, retries: 50, sleep_sec: 0.1) do
            if current_user && !::Identity.with_extern_uid('vos', oauth.fetch('uid')).exists?(user_id: current_user.id)
              sign_out(current_user)
            end
            sign_in_user_flow(Gitlab::Auth::Vos::User)
          end
        rescue Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError
          redirect_to new_user_session_path, alert: _('Please try again')
        end
      end
    end
  end
end
