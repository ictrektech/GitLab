# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Usage::Metrics::Instrumentations::CountKnowledgeGraphEnabledNamespacesMetric,
  feature_category: :service_ping do
  let_it_be(:namespace) { create(:group) }
  let_it_be(:enabled_namespace) { create(:knowledge_graph_enabled_namespace, namespace: namespace) }

  it_behaves_like 'a correct instrumented metric value and query', { time_frame: 'all', data_source: 'database' } do
    let(:expected_value) { 1 }
    let(:expected_query) do
      %{SELECT COUNT("knowledge_graph_enabled_namespaces"."id") FROM "knowledge_graph_enabled_namespaces"}
    end
  end
end
