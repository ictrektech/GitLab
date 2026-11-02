# frozen_string_literal: true

module Ai
  # Answers Duo access questions for one user. Replaces the methods that
  # Ai::UserAuthorizable adds to User; see
  # https://gitlab.com/gitlab-org/gitlab/-/work_items/636699
  class UserAuthorizer
    def initialize(user)
      @user = user
    end

    def eligible_for_self_managed_gitlab_duo_pro?
      return false if user.gitlab_com_subscription?

      user.active? && !user.bot? && !user.ghost?
    end

    private

    attr_reader :user
  end
end
