# frozen_string_literal: true

module Gitlab
  module Duo
    module CodeReview
      STANDARD_DEPTH = 'standard'
      DEEP_DEPTH = 'deep'
      DEPTHS = [STANDARD_DEPTH, DEEP_DEPTH].freeze
      DEPTHS_BY_FLOW_ID = { 'code_review' => :standard, 'deep_code_review' => :deep }.freeze

      module_function

      def enabled?(user:, container:)
        ModeResolver.new(user: user, container: container).enabled?
      end

      def mode(user:, container:)
        ModeResolver.new(user: user, container: container).mode
      end

      def dap?(user:, container:)
        mode(user:, container:) == :dap
      end

      # The depth of the code review flow that actually ran, as recorded by DWS.
      def depth_for(workflow)
        return if workflow.flow_metadata_json.blank?

        metadata = ::Gitlab::Json.safe_parse(workflow.flow_metadata_json)
        DEPTHS_BY_FLOW_ID[metadata['flow_id']] if metadata.is_a?(Hash)
      end
    end
  end
end
