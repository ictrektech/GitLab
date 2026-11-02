# frozen_string_literal: true

module WorkItemTypeVisibilityHelpers
  # Types can be system-defined base types (e.g. :incident) or type objects responding to #id.
  def disable_work_item_types(namespace, *types, settings_namespace: namespace.root_ancestor)
    stub_saas_features(namespace_scoped_work_item_types: true)
    ::WorkItems::Settings.find_or_initialize_by(namespace: settings_namespace)
      .update!(customizable_type_visibility: true)

    types.each do |type|
      type = build(:work_item_system_defined_type, type) if type.is_a?(Symbol)

      create(:work_item_type_visibility,
        namespace: namespace,
        work_item_type_id: type.id,
        enabled: false,
        propagate: !namespace.is_a?(Namespaces::ProjectNamespace))
    end
  end
end
