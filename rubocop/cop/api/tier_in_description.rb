# frozen_string_literal: true

require_relative '../../code_reuse_helpers'

module RuboCop
  module Cop
    module API
      # Checks that API desc blocks do not contain tier terms
      # (Premium, Ultimate, EE-only, requires a license) in the description or detail strings.
      # Use `route_setting :tier, :premium` or `route_setting :tier, :ultimate` instead.
      #
      # @example
      #
      #   # bad
      #   desc 'Get all widgets (Premium and above)' do
      #     detail 'This feature requires a Premium subscription.'
      #     tags %w[widgets]
      #   end
      #
      #   # good
      #   route_setting :tier, :premium
      #   desc 'Get all widgets' do
      #     detail 'Gets all widgets of the requested group.'
      #     tags %w[widgets]
      #   end
      class TierInDescription < RuboCop::Cop::Base
        include CodeReuseHelpers

        MSG = 'Do not use tier terms (Premium, Ultimate, EE-only, requires a license) in API descriptions. ' \
          'Use `route_setting :tier, :premium` or `route_setting :tier, :ultimate` instead. ' \
          'https://docs.gitlab.com/development/api_styleguide/#marking-endpoint-tier'

        TIER_PATTERN = Regexp.union(
          /\b(?:premium|ultimate|starter|bronze|silver|gold)\b/i,
          /\b(?:EE[ -]only|GitLab EE)\b/i,
          /\brequires\b.*\b(?:license|subscription)\b/i
        )

        # @!method desc_block(node)
        def_node_matcher :desc_block, <<~PATTERN
          (block
            (send nil? :desc ${str dstr} ...)
            _args
            _body
          )
        PATTERN

        # @!method desc_block_body(node)
        def_node_matcher :desc_block_body, <<~PATTERN
          (block
            (send nil? :desc ...)
            _args
            $_body
          )
        PATTERN

        # @!method detail_string(node)
        def_node_matcher :detail_string, '(send nil? :detail ${str dstr})'

        def on_block(node)
          return unless node.method?(:desc)

          check_summary(node)
          check_detail(node)
        end

        alias_method :on_numblock, :on_block

        private

        def check_summary(node)
          summary_node = desc_block(node)
          return unless summary_node
          return unless extract_text(summary_node).match?(TIER_PATTERN)

          add_offense(summary_node)
        end

        def check_detail(node)
          body = desc_block_body(node)
          return unless body

          find_detail_nodes(body).each do |detail_node|
            next unless extract_text(detail_node).match?(TIER_PATTERN)

            add_offense(detail_node)
          end
        end

        def find_detail_nodes(body)
          statements = body.begin_type? ? body.children : [body]

          statements.filter_map { |child| detail_string(child) }
        end

        def extract_text(node)
          return node.value if node.str_type?

          node.children.select { |child| child.is_a?(Parser::AST::Node) && child.str_type? }
            .map(&:value).join
        end
      end
    end
  end
end
