# frozen_string_literal: true

module Authz
  class AdminRole < ApplicationRecord
    belongs_to :organization, class_name: 'Organizations::Organization'
    has_many :user_admin_roles, class_name: 'Authz::UserAdminRole'
    has_many :users, through: :user_admin_roles

    validate :validate_permissions
    validates :name, presence: true, uniqueness: { scope: :organization_id }
    validates :permissions, json_schema: { filename: 'admin_role_permissions' }

    before_destroy :prevent_delete_if_assigned

    jsonb_accessor :permissions,
      Gitlab::CustomRoles::Definition.admin.keys.index_with(::Gitlab::Database::Type::JsonbBoolean.new)

    def enabled_permissions
      Gitlab::CustomRoles::Definition.admin.filter do |permission, _|
        attributes[permission.to_s]
      end
    end

    def admin_related_role?
      true
    end

    private

    def validate_permissions
      self.permissions = permissions.select { |_, enabled| enabled }

      if permissions.empty?
        errors.add(:base, s_('MemberRole|Cannot create a member role with no enabled permissions'))
        return
      end

      permissions.each_key do |permission|
        next if Gitlab::CustomRoles::Definition.admin.include?(permission.to_sym)

        message = format(s_('MemberRole|Unknown permission: %{permission}'), permission: permission)
        errors.add(:base, message)
      end
    end

    def prevent_delete_if_assigned
      return unless user_admin_roles.exists?

      errors.add(:base,
        s_("MemberRole|Admin role is assigned to one or more users. " \
          "Remove role from all users, then delete role."))

      throw :abort # rubocop:disable Cop/BanCatchThrow -- Stops the destroy. Adding an error alone would not.
    end
  end
end
