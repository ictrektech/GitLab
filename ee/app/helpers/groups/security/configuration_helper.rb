# frozen_string_literal: true

module Groups
  module Security
    module ConfigurationHelper
      SCAN_COVERAGE_BANNER_SNOOZE_PERIOD = 35.days

      def group_security_configuration_data(group)
        {
          namespace_id: group.root_ancestor.id,
          group_id: group.id,
          group_full_path: group.full_path,
          group_name: group.name,
          root_group_name: group.root_ancestor.name,
          security_inventory_path: group_security_inventory_path(group),
          can_read_attributes: can?(current_user, :read_security_attribute, group).to_s,
          # rubocop:disable Gitlab/Authz/PermissionCheck -- pre-existing check moved from SecurityFeaturesHelper
          can_manage_attributes: can?(current_user, :admin_security_attributes, group.root_ancestor).to_s,
          # rubocop:enable Gitlab/Authz/PermissionCheck
          can_read_scan_profiles: can?(current_user, :read_security_scan_profiles, group.root_ancestor).to_s,
          can_apply_profiles: can?(current_user, :apply_security_scan_profiles, group).to_s,
          scan_coverage_banner: scan_coverage_banner_json(group)
        }
      end

      def scan_coverage_banner_payload(group)
        return unless ::Feature.enabled?(:security_profile_banner, group.root_ancestor)
        return unless ::Ability.allowed?(current_user, :apply_security_scan_profiles, group)
        return if scan_coverage_banner_dismissed?(group)

        result = ::Security::ScanCoverageBanners::GenerateContentService.new(group).execute
        result.payload if result.success?
      end

      private

      def scan_coverage_banner_json(group)
        scan_coverage_banner_payload(group)&.transform_keys { |k| k.to_s.camelize(:lower) }.to_json
      end

      def scan_coverage_banner_snooze_period
        SCAN_COVERAGE_BANNER_SNOOZE_PERIOD
      end

      def scan_coverage_banner_dismissed?(group)
        current_user.dismissed_callout_for_group?(
          feature_name: :scan_coverage_recommendation_banner,
          group: group,
          ignore_dismissal_earlier_than: scan_coverage_banner_snooze_period.ago
        )
      end
    end
  end
end
