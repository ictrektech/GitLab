# frozen_string_literal: true

module Ai
  module Catalog
    class FoundationalFlow
      include ActiveRecord::FixedItemsModel::Model
      include GlobalID::Identification
      include Ai::Catalog::FoundationalFlow::Attributes
      include Ai::Catalog::FoundationalFlow::Items

      SESSION_LIFECYCLE_HOOKS = {
        ::Ai::DuoWorkflows::WorkflowFinishedCloudEvent => :on_session_finished,
        ::Ai::DuoWorkflows::WorkflowFailedEvent => :on_session_failed,
        ::Ai::DuoWorkflows::WorkflowStoppedEvent => :on_session_stopped
      }.freeze

      register_flow(CodeReview::Definition)
      register_flow(RiskClassification::Definition)
      register_flow(SastFpDetection::Definition)
      register_flow(ResolveSastVulnerability::Definition)
      register_flow(Developer::Definition)
      register_flow(FixPipeline::Definition)
      register_flow(ConvertToGlCi::Definition)
      register_flow(RecommendReviewers::Definition)
      register_flow(SecretsFpDetection::Definition)
      register_flow(ResolveDependencyBump::Definition)
      register_flow(SecurityReview::Definition)
      register_flow(BlSecurity::Definition)
      register_flow(BusinessContextSecurityGuidelines::Definition)
      register_flow(Workplan::Definition)
      register_flow(ReadinessScore::Definition)
      register_flow(SlackAssistant::Definition)

      def self.find_by_reference(reference)
        find_by(foundational_flow_reference: reference)
      end

      def self.[](key)
        find_by(foundational_flow_reference: key) || find_by(display_name: key)
      end

      def self.session_hook?(foundational_flow_reference, event_class)
        flow = find_by(foundational_flow_reference: foundational_flow_reference)
        !!flow&.session_lifecycle_hook(event_class)
      end

      def self.beta?(foundational_flow_reference)
        flow = find_by(foundational_flow_reference: foundational_flow_reference)
        !!flow&.beta?
      end

      def self.ultimate_only?(foundational_flow_reference)
        flow = find_by(foundational_flow_reference: foundational_flow_reference)
        !!flow&.ultimate_only?
      end

      def self.available_for_group(group)
        all.select { |flow| flow.available_for?(group) }
      end

      def available_for?(namespace)
        return false if beta? && !namespace.duo_beta_flows_enabled?
        return false if ultimate_only? && !namespace.licensed_feature_available?(:ai_features)

        !blocked_for?(namespace)
      end

      def beta?
        feature_maturity == 'beta'
      end

      def ultimate_only?
        Gitlab::Utils.to_boolean(ultimate_only)
      end

      # Whether the flow cannot run for the namespace: it is not offered on this deployment
      # (`available_on`), or it is not switched on (`enabled_for?`).
      def blocked_for?(namespace)
        return true unless available_on_current_deployment?

        !enabled_for?(namespace)
      end

      # Whether the flow's own settings block it for the namespace, leaving out the per-instance
      # lookup: not offered on this deployment, not opted in on Dedicated, or its flag is off.
      def blocked_by_settings_for?(namespace)
        return true unless available_on_current_deployment?
        return !opted_in_on_dedicated? if per_instance_gate_applies?

        !feature_flag_enabled_for?(namespace)
      end

      # Whether the flow is switched on for the actor (a namespace, or `:instance`): by GitLab's
      # enablement where the per-instance gate applies, else by its `feature_flag`. It does not check
      # `available_on`; for availability use `blocked_for?` or `available_for?`.
      def enabled_for?(actor)
        if per_instance_gate_applies?
          return false unless opted_in_on_dedicated?

          # GitLab enables the flow only if ai-assist also lists it in GATED_FLOWS
          # (lib/flow_enablement.py) with this instance's uids.
          return ::Ai::Catalog::FoundationalFlows::EnabledFlowsClient.enabled?(flow_config_id)
        end

        feature_flag_enabled_for?(actor)
      end

      # On GitLab Dedicated, a flow available on `:dedicated_enabled_instances` runs only where
      # GitLab has enabled it, in place of its `feature_flag`.
      def per_instance_gate_applies?
        current_deployment == :dedicated && available_on.include?(:dedicated_enabled_instances)
      end

      # The flow id the Duo Workflow Service knows the flow by, e.g. `bl_security`.
      def flow_config_id
        foundational_flow_reference.split('/', 2).first
      end

      def agent_privileges=(value)
        super(Array(value).map { |v| Integer(v) })
      end

      def available_on=(value)
        super(Array(value).map(&:to_sym))
      end

      def pre_approved_agent_privileges=(value)
        super(value.nil? ? nil : Array(value).map { |v| Integer(v) })
      end

      def required_agent_privileges=(value)
        super(value.nil? ? nil : Array(value).map { |v| Integer(v) })
      end

      def supported_resource_types=(value)
        super(value.nil? ? nil : Array.wrap(value))
      end

      # A flow that does not narrow its pre-approved set runs unattended, so every
      # granted privilege is pre-approved: pausing for an approval nobody can give
      # would just hang the flow.
      def pre_approved_agent_privileges
        super || agent_privileges
      end

      def required_agent_privileges
        super || agent_privileges
      end

      def resolve_noteable_for(project:, goal:)
        noteable_resolver&.call(project: project, goal: goal)
      end

      def resolve_source_pipeline_for(project:, goal:)
        source_pipeline_resolver&.call(project: project, goal: goal)
      end

      def resolve_source_branch_for(project:, goal:)
        source_branch_resolver&.call(project: project, goal: goal)
      end

      def validate_start_request(container:, goal:, additional_context: nil, client_executed: false)
        result = start_request_validator&.call(
          container: container,
          goal: goal,
          additional_context: Array(additional_context),
          client_executed: client_executed
        )
        return result if result.nil? || result.is_a?(ServiceResponse)

        raise ArgumentError, "start_request_validator must return a ServiceResponse or nil, got #{result.class}"
      end

      # A flow that declares the resource types it accepts rejects a nil resource
      # too: every such flow reads the resource to build its goal.
      def supports_resource?(resource)
        return true if supported_resource_types.nil?

        supported_resource_types.any? { |type| resource.is_a?(type) }
      end

      def resolve_additional_context_for(resource:)
        with_supported_resource(resource) do
          additional_context_resolver&.call(resource: resource)
        end
      end

      def run_eligible?(project:, resource:)
        return true if run_eligibility_resolver.nil?

        run_eligibility_resolver.call(project: project, resource: resource)
      end

      def resolve_ai_feature(current_user:, additional_context: nil)
        ai_feature_resolver&.call(current_user: current_user, additional_context: additional_context) || ai_feature
      end

      def run_on_session_created(resource:)
        with_supported_resource(resource) do
          on_session_created&.call(resource: resource)
        end
      end

      def run_session_hook(event_class, workflow:)
        hook = session_lifecycle_hook(event_class)
        return false unless hook

        hook.call(workflow: workflow)

        true
      end

      def resolve_flow_version_for(container:, user:, additional_context: nil)
        resolved_reference, resolved_version =
          flow_version_resolver&.call(container: container, user: user, additional_context: additional_context) ||
          [foundational_flow_reference, flow_version]

        flow_config_id, flow_config_schema_version = resolved_reference.split('/', 2)

        {
          flow_config_id: flow_config_id,
          flow_config_schema_version: flow_config_schema_version,
          flow_version: resolved_version
        }
      end

      def translated_display_name
        # rubocop:disable Gettext/StaticIdentifier -- Translations available in `fixed_items`.
        s_("FoundationalFlow|#{display_name}") if display_name
        # rubocop:enable Gettext/StaticIdentifier
      end

      def translated_description
        # rubocop:disable Gettext/StaticIdentifier -- Translations available in `fixed_items`.
        s_("FoundationalFlow|#{description}") if description
        # rubocop:enable Gettext/StaticIdentifier
      end

      # Cached per request, not on the instance: instances live for the whole process (FixedItemsModel),
      # so instance memoization keeps a missing or re-seeded item stale until restart.
      def catalog_item
        return if foundational_flow_reference.nil?

        Gitlab::SafeRequestStore.fetch([self.class, :catalog_item, foundational_flow_reference]) do
          Ai::Catalog::Item.with_foundational_flow_reference(foundational_flow_reference).first
        end
      end

      def session_lifecycle_hook(event_class)
        hook = SESSION_LIFECYCLE_HOOKS[event_class]

        return if hook.nil?

        read_attribute(hook)
      end

      private

      def current_deployment
        return :gitlab_com if ::Gitlab::Saas.feature_available?(:gitlab_com_subscriptions)
        return :dedicated if ::Gitlab::Dedicated.feature_available?(:ai_flow_enablement)

        :self_managed
      end

      def available_on_current_deployment?
        deployment = current_deployment
        return available_on.intersect?(%i[dedicated dedicated_enabled_instances]) if deployment == :dedicated

        available_on.include?(deployment)
      end

      # An experimental or beta flow also needs the customer's opt-in: the instance-level AI
      # beta features setting.
      def opted_in_on_dedicated?
        return true if feature_maturity == 'ga'

        ::Gitlab::CurrentSettings.instance_level_ai_beta_features_enabled?
      end

      def feature_flag_enabled_for?(actor)
        return true if feature_flag.blank?

        # rubocop:disable Gitlab/FeatureFlagKeyDynamic -- Need to check the flag defined by flow dynamically.
        ::Feature.enabled?(feature_flag.to_sym, actor)
        # rubocop:enable Gitlab/FeatureFlagKeyDynamic
      end

      def with_supported_resource(resource)
        return unless supports_resource?(resource)

        yield
      end
    end
  end
end
