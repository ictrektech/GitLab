# frozen_string_literal: true

module Ai
  class NamespaceSetting < ApplicationRecord
    self.table_name = "namespace_ai_settings"

    include HasRolePermissions
    include NormalizesDomainLists

    # Settings whose explicit submission is recorded in `configured_at` (key presence = explicitly configured).
    PROVENANCE_TRACKED_SETTINGS = %w[
      duo_workflow_mcp_enabled
      ai_usage_data_collection_enabled
      ai_catalog_restricted_to_group_hierarchy
      web_search_enabled
      prompt_injection_protection_level
    ].freeze

    enum :prompt_injection_protection_level, {
      log_only: 0,
      no_checks: 1,
      interrupt: 2
    }

    jsonb_accessor :feature_settings,
      duo_agent_platform_enabled: [:boolean, { default: true }]

    validates :feature_settings,
      json_schema: { filename: "ai_namespace_setting_feature_settings", size_limit: 64.kilobytes }

    validates :configured_at,
      json_schema: { filename: "ai_namespace_setting_configured_at", size_limit: 64.kilobytes }

    validates :duo_workflow_mcp_enabled, inclusion: { in: [true, false] }
    validates :prompt_injection_protection_level, presence: true
    validates :ai_usage_data_collection_enabled, inclusion: { in: [true, false] }
    validates :ai_catalog_restricted_to_group_hierarchy, inclusion: { in: [true, false] }
    validates :web_search_enabled, inclusion: { in: [true, false] }
    validate :validate_namespace_for_catalog_restriction, if: :ai_catalog_restricted_to_group_hierarchy_changed?
    validate :validate_namespace_for_web_search, if: :web_search_enabled_changed?

    belongs_to :namespace, inverse_of: :ai_settings

    private

    def validate_namespace_for_catalog_restriction
      return if top_level_group_namespace?

      errors.add(:ai_catalog_restricted_to_group_hierarchy,
        _('can only be set for top-level groups'))
    end

    def validate_namespace_for_web_search
      return if top_level_group_namespace?

      errors.add(:web_search_enabled, _('can only be set for top-level groups'))
    end

    def top_level_group_namespace?
      namespace&.root? && namespace.group_namespace?
    end

    def domain_list_limits_actor
      namespace
    end
  end
end
