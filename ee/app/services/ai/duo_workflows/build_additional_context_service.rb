# frozen_string_literal: true

module Ai
  module DuoWorkflows
    class BuildAdditionalContextService
      include ::Gitlab::Utils::StrongMemoize

      DWS_STANDARD_CONTEXT_CATEGORY = "agent_platform_standard_context"
      DWS_TRIGGER_CONTEXT_CATEGORY = "agent_platform_trigger_context"
      DWS_RESOURCE_CONTEXT_CATEGORY = "agent_platform_resource_context"
      DWS_CLIENT_CONTEXT_CATEGORY = "agent_platform_client_context"
      DWS_CONTEXT_VERSION = "1.0.0"
      DWS_STANDARD_CONTEXT_VERSION = "1.1.0"
      DWS_RESOURCE_CONTEXT_VERSION = "1.1.0"
      DWS_CLIENT_CONTEXT_VERSION = "1.0.0"
      DWS_RESERVED_CATEGORIES = [
        DWS_STANDARD_CONTEXT_CATEGORY,
        DWS_TRIGGER_CONTEXT_CATEGORY,
        DWS_RESOURCE_CONTEXT_CATEGORY,
        ::Ai::DuoWorkflows::AdditionalContext::BlSecurityContextBuilder::CATEGORY,
        DWS_CLIENT_CONTEXT_CATEGORY
      ].freeze

      def initialize(
        standard_context_params: nil,
        trigger_params: {},
        additional_context: nil,
        resource: nil,
        foundational_flow: nil,
        workflow_definition: nil,
        goal: nil,
        client_context: nil
      )
        @standard_context_params = standard_context_params
        @workflow_definition = workflow_definition
        @goal = goal
        @trigger_params = trigger_params
        @resource = resource
        @foundational_flow = foundational_flow
        @additional_context = additional_context
        @client_context = client_context
      end

      def execute
        context = caller_context + standard_context + trigger_context + resource_context + foundational_flow_context +
          client_context_envelope
        context = with_bl_security_context(context)

        ServiceResponse.success(payload: { context: context })
      end

      private

      attr_reader :standard_context_params, :trigger_params, :additional_context, :resource, :foundational_flow,
        :workflow_definition, :goal, :client_context

      # Rails owns the reserved categories and the ones the flow resolves: drop any
      # caller-supplied envelope with a colliding category so the central version wins.
      def caller_context
        reserved = DWS_RESERVED_CATEGORIES + foundational_flow_context.map { |envelope| envelope_category(envelope) }

        Array.wrap(additional_context).reject { |envelope| reserved.include?(envelope_category(envelope)) }
      end

      def envelope_category(envelope)
        envelope["Category"] || envelope[:Category]
      end

      def foundational_flow_context
        return [] unless foundational_flow

        ::Ai::DuoWorkflows::AdditionalContext::FoundationalFlowContextBuilder
          .new(flow: foundational_flow)
          .build(resource: resource)
      end
      strong_memoize_attr :foundational_flow_context

      # Without standard_context_params neither this nor the BL security envelope is built: both
      # need a project, service account and workload branch, which Workhorse sessions lack.
      def standard_context
        return [] unless standard_context_params

        [
          ::Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(
            category: DWS_STANDARD_CONTEXT_CATEGORY,
            fields: standard_context_fields,
            version: DWS_STANDARD_CONTEXT_VERSION
          )
        ]
      end

      def standard_context_fields
        @standard_context_fields ||=
          ::Ai::DuoWorkflows::AdditionalContext::StandardContextBuilder.build(**standard_context_params)
      end

      # Separate envelope so the standard context schema stays frozen across deploys:
      # an unknown category is skipped with a warning; an unknown field inside a known
      # category fails envelope validation.
      def trigger_context
        fields = ::Ai::DuoWorkflows::AdditionalContext::TriggerContextBuilder.build(**trigger_params)

        return [] unless fields

        [
          ::Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(
            category: DWS_TRIGGER_CONTEXT_CATEGORY,
            fields: fields,
            version: DWS_CONTEXT_VERSION
          )
        ]
      end

      def client_context_envelope
        fields = ::Ai::DuoWorkflows::AdditionalContext::ClientContextBuilder.build(content: client_context)
        return [] unless fields

        [
          ::Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(
            category: DWS_CLIENT_CONTEXT_CATEGORY,
            fields: fields,
            version: DWS_CLIENT_CONTEXT_VERSION
          )
        ]
      end

      def resource_context
        fields = ::Ai::DuoWorkflows::AdditionalContext::ResourceContextBuilder.build(resource)
        return [] unless fields

        [
          ::Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(
            category: DWS_RESOURCE_CONTEXT_CATEGORY,
            fields: fields,
            version: DWS_RESOURCE_CONTEXT_VERSION
          )
        ]
      end

      # The business logic security scan's dials, in their own category so the standard
      # context schema stays shared and frozen. Other flows, and runs while the flag is
      # off, get no envelope. A caller-supplied envelope with this category is always
      # dropped (see caller_context).
      def with_bl_security_context(context)
        return context unless standard_context_params

        builder = ::Ai::DuoWorkflows::AdditionalContext::BlSecurityContextBuilder
        fields = builder.build(
          project: standard_context_params[:project],
          workflow_definition: workflow_definition,
          goal: goal,
          primary_branch: standard_context_fields["primary_branch"]
        )
        return context unless fields

        context + [
          ::Ai::DuoWorkflows::AdditionalContext::Envelope.wrap(
            category: builder::CATEGORY,
            fields: fields,
            version: DWS_CONTEXT_VERSION
          )
        ]
      end
    end
  end
end
