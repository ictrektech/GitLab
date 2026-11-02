# frozen_string_literal: true

module Security
  module Ingestion
    module Tasks
      class HooksExecution < AbstractTask
        def execute
          SecApplicationRecord.current_transaction.after_commit do
            new_vulnerabilities.each do |vulnerability|
              vulnerability.execute_hooks
              vulnerability.trigger_false_positive_detection
            end
          end
        end

        private

        def new_vulnerabilities
          new_finding_maps.map(&:vulnerability_id)
                          .then { |ids| Vulnerability.id_in(ids).with_projects }
        end

        def new_finding_maps
          finding_maps.select { |map| map.new_record && eligible_context?(map) }
        end

        def eligible_context?(map)
          context = map.tracked_context
          return true if context.nil? || context.is_default?

          # Only the SAST FP worker reads code at the finding's ref.
          context.tracked? &&
            map.report_finding.report_type.to_s == 'sast' &&
            non_default_allowed?(context.project)
        end

        # CVS ingestion passes a nil pipeline and can span many projects.
        def non_default_allowed?(project)
          strong_memoize_with(:non_default_allowed, project.id) do
            ::Vulnerability.fp_detection_non_default_branches_enabled?(project)
          end
        end
      end
    end
  end
end
