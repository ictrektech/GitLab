# frozen_string_literal: true

# The CI database has no projects or namespaces tables, so tables on it are
# scoped through the CI mirror tables instead.
ci_sharding_key_types = { projects: :ci_project_mirrors, namespaces: :ci_namespace_mirrors }.freeze

sharding_key_map = Gitlab::Database::Dictionary.entries.each_with_object({}) do |entry, map|
  sharding_key = entry.sharding_key
  # Tables with multiple sharding keys are excluded: scoping them requires an
  # OR condition across the keys, which performs poorly. See
  # https://gitlab.com/gitlab-org/gitlab/-/issues/594726
  next unless sharding_key.is_a?(Hash) && sharding_key.size == 1

  keys = sharding_key.transform_values(&:to_sym)
  keys = keys.transform_values { |type| ci_sharding_key_types.fetch(type, type) } if entry.gitlab_schema == 'gitlab_ci'

  map[entry.key_name] = keys
end

Gitlab::Database::DataIsolation.configure do |config|
  config.strategy = :arel
  config.sharding_key_map = sharding_key_map
  config.current_sharding_key_value = ->(type) {
    return unless Gitlab::Organizations::Isolation.enabled?

    organization_id = Current.organization&.id if Current.organization_assigned
    return unless organization_id

    case type
    when :projects
      Project.select(:id).in_organization(organization_id)
    when :namespaces
      Namespace.select(:id).in_organization(organization_id)
    when :ci_project_mirrors
      Ci::ProjectMirror.select(:project_id).where(organization_id: organization_id)
    when :ci_namespace_mirrors
      Ci::NamespaceMirror.select(:namespace_id).where(organization_id: organization_id)
    when :organizations
      organization_id
    when :users
      User.select(:id).in_organization(organization_id)
    end
  }
end

Gitlab::Database::DataIsolation.install!
