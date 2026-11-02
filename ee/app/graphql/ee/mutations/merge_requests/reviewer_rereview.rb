# frozen_string_literal: true

module EE
  module Mutations
    module MergeRequests
      module ReviewerRereview
        extend ActiveSupport::Concern

        prepended do
          argument :duo_code_review_depth, ::Types::Ai::DuoCodeReviewDepthEnum,
            required: false,
            experiment: { milestone: '19.6' },
            description: 'Depth of the GitLab Duo Code Review to run when the user is the GitLab Duo Code Review ' \
              'bot. Ignored for other users, and unless the `duo_code_review_deep_flow` feature flag is enabled ' \
              'for the current user.'
        end
      end
    end
  end
end
