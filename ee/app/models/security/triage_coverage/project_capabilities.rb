# frozen_string_literal: true

module Security
  module TriageCoverage
    module ProjectCapabilities
      FLOW_BY_TRIGGER = {
        sbom_ingested: -> { Ai::Catalog::FoundationalFlow.resolve_dependency_bump_experimental },
        sast_false_positive: -> { Ai::Catalog::FoundationalFlow.sast_fp_detection_v1 },
        sast_vulnerability_resolution: -> { Ai::Catalog::FoundationalFlow.resolve_sast_vulnerability_v1 },
        secret_detection_false_positive: -> { Ai::Catalog::FoundationalFlow.secrets_fp_detection_v1 },
        vulnerability_enrichment: nil
      }.freeze

      UNRESOLVED_FLOW_STATUSES = FLOW_BY_TRIGGER.transform_values { |f| f ? :flow_unavailable : :not_applicable }.freeze

      def self.for_projects(projects)
        project_ids = projects.map(&:id)
        filters_by_project_id = Security::InventoryFilter.by_project_id(project_ids).index_by(&:project_id)
        flow_statuses = flow_statuses_by_project_id(projects, project_ids)

        projects.to_h do |project|
          capabilities = filters_by_project_id[project.id]&.triage_capabilities || CapabilityBitmask.decode(0, 0)
          statuses = flow_statuses.fetch(project.id)

          [project.id, capabilities.map { |c| c.merge(flow_status: statuses.fetch(c[:trigger_type])) }]
        end
      end

      def self.flow_statuses_by_project_id(projects, project_ids)
        return {} if projects.blank?

        root_id_by_project = Project.root_namespace_ids_by_project_ids(project_ids)
        roots = Group.id_in(root_id_by_project.values.uniq).includes(:namespace_settings).index_by(&:id)
        enabled = enabled_references(roots.keys)
        by_root = roots.transform_values { |root| flow_statuses_for(root, enabled.fetch(root.id, [])) }

        projects.to_h do |project|
          [project.id, by_root.fetch(root_id_by_project[project.id], UNRESOLVED_FLOW_STATUSES)]
        end
      end

      def self.enabled_references(root_ids)
        Ai::Catalog::EnabledFoundationalFlow.for_namespace(root_ids).includes(:catalog_item)
          .group_by(&:namespace_id)
          .transform_values { |records| records.filter_map { |r| r.catalog_item.foundational_flow_reference } }
      end

      def self.flow_statuses_for(root, enabled)
        flows_enabled = root.duo_foundational_flows_enabled
        stage_available = flows_enabled && Gitlab::Llm::StageCheck.available?(root, :duo_workflow)

        FLOW_BY_TRIGGER.transform_values do |lookup|
          next :not_applicable unless lookup
          next :foundational_flows_disabled unless flows_enabled

          flow = lookup.call
          next :flow_unavailable unless stage_available && flow&.available_for?(root)

          enabled.include?(flow.foundational_flow_reference) ? :available : :flow_not_enabled
        end
      end

      private_class_method :flow_statuses_by_project_id, :enabled_references, :flow_statuses_for
    end
  end
end
