# frozen_string_literal: true

module Gitlab
  module Auth
    module Vos
      module Callbacks
        # Switching VOS users must never link the new identity to the previous session's account.
        def vos
          sign_out(current_user) if current_user
          sign_in_user_flow(Gitlab::Auth::Vos::User)
        end
      end
    end
  end
end
