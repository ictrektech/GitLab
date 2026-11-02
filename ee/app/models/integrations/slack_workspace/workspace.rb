# frozen_string_literal: true

module Integrations
  module SlackWorkspace
    # The top-level group a Slack workspace runs GitLab Duo in. No row means GitLab Duo is off for that workspace.
    # team_id is unique across organizations. The Cells claim for it lands before any code writes rows:
    # https://gitlab.com/gitlab-org/gitlab/-/work_items/633611
    class Workspace < ApplicationRecord
      self.table_name = 'slack_workspaces'

      belongs_to :duo_namespace, class_name: 'Namespace', inverse_of: false, optional: false

      validates :team_id, presence: true, uniqueness: true, length: { maximum: 255 }
      validate :duo_namespace_is_top_level_group

      private

      def duo_namespace_is_top_level_group
        return if duo_namespace.nil? || (duo_namespace.is_a?(::Group) && duo_namespace.root?)

        errors.add(:duo_namespace, s_('SlackIntegration|must be a top-level group'))
      end
    end
  end
end
