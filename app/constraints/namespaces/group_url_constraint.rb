# frozen_string_literal: true

module Namespaces
  class GroupUrlConstraint
    def matches?(request, existence_check: true)
      full_path = request.params[:group_id] || request.params[:id]

      return false unless NamespacePathValidator.valid_path?(full_path)
      return true unless existence_check

      Group.find_by_full_path(full_path, follow_redirects: request.get?).present?
    end
  end
end
