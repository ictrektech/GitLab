# frozen_string_literal: true

module Types
  module Ai
    class DuoCodeReviewDepthEnum < BaseEnum
      graphql_name 'DuoCodeReviewDepth'
      description 'Depth of a GitLab Duo Code Review.'

      value 'STANDARD', value: ::Gitlab::Duo::CodeReview::STANDARD_DEPTH,
        description: 'Standard review.'
      value 'DEEP', value: ::Gitlab::Duo::CodeReview::DEEP_DEPTH,
        description: 'Deep review.'
    end
  end
end
