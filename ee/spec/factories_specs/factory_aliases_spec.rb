# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Factory association aliases', feature_category: :tooling do
  row = FactoryDefaults::Row

  it_behaves_like 'factory default associations', [
    row.new(
      factory: :analyzer_namespace_status, skip: :namespace, passed: { namespace: :group, group: :group },
      expected: ->(group, strategy) {
        attributes = { namespace: group, namespace_id: group.id, group: group }
        strategy == :build_stubbed ? attributes : attributes.merge(traversal_ids: group.traversal_ids)
      },
      default_strategy: :build
    ),
    row.new(
      factory: :vulnerability_namespace_statistic, skip: :namespace, passed: { namespace: :group, group: :group },
      expected: ->(group, strategy) {
        attributes = { namespace: group, namespace_id: group.id, group: group }
        strategy == :build_stubbed ? attributes : attributes.merge(traversal_ids: group.traversal_ids)
      },
      default_strategy: :build
    ),
    row.new(
      factory: :resource_state_event, skip: :epic, passed: { work_item: :work_item },
      expected: ->(work_item, _) { { issue: work_item, work_item: work_item } }, default_strategy: :build
    ),
    row.new(factory: :epic, skip: :work_item, passed: { sync_object: :work_item }),
    row.new(
      factory: :system_access_group_microsoft_graph_access_token,
      skip: :system_access_group_microsoft_application,
      passed: { system_access_microsoft_application: :system_access_group_microsoft_application }
    )
  ]
end
