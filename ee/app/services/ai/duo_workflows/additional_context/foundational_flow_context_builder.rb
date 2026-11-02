# frozen_string_literal: true

module Ai
  module DuoWorkflows
    module AdditionalContext
      class FoundationalFlowContextBuilder
        CONTEXT_CATEGORY = "agent_platform_%s_context"

        def initialize(flow:)
          @flow = flow
        end

        def build(resource:)
          fields = flow.resolve_additional_context_for(resource: resource)

          return [] if fields.blank?

          context_categories.map do |category|
            Envelope.wrap(category: category, fields: fields)
          end
        end

        private

        attr_reader :flow

        def context_categories
          [default_context_category, aliased_context_category].compact.uniq
        end

        def default_context_category
          flow_identifier = flow.reference.split('/').first
          CONTEXT_CATEGORY % flow_identifier
        end

        def aliased_context_category
          flow.context_category_alias
        end
      end
    end
  end
end
