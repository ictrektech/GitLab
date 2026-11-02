# frozen_string_literal: true

module Gitlab
  module Auth
    module Vos
      # Use native identities and account policies, without email or LDAP auto-linking.
      class User < Gitlab::Auth::OAuth::User
        def valid_sign_in?
          super && gl_user.active_for_authentication?
        end

        def bypass_two_factor?
          false
        end

        protected

        def auto_link_user?
          false
        end

        def auto_link_ldap_user?
          false
        end

        def sync_profile_from_provider?
          false
        end
      end
    end
  end
end
