# frozen_string_literal: true

module Resolvers
  module Security
    class TriageAndRemediationCoverageCountersResolver < BaseResolver
      type ::Types::Security::TriageAndRemediationCoverageCountersType, null: true
      authorize :read_security_scan_profiles
      authorizes_object!

      # GraphQL-Ruby forbids `experiment:` (implemented via deprecation) on a required argument;
      # the enclosing field is already tagged `experiment: { milestone: '19.5' }` in GroupType.
      argument :trigger_type, ::Types::Security::ScanProfileTriggerTypeEnum,
        required: true,
        description: 'Trigger type to count coverage for.'

      alias_method :group, :object

      def resolve(trigger_type:)
        counts = ::Security::InventoryFilter.triage_coverage_counts_for(group, trigger_type)
        return unless counts

        ::Types::Security::TriageAndRemediationCoverageCountersType::Adapter.new(
          enabled_count: counts.enabled_count, auto_count: counts.auto_count, group: group
        )
      end
    end
  end
end
