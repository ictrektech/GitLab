# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.group(fullPath).dependencies', feature_category: :dependency_management do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:current_user) { create(:user, developer_of: group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:occurrence) { create(:sbom_occurrence, project: project) }
  let_it_be(:default_context) { create(:security_project_tracked_context, :default, project: project) }
  let_it_be(:feature_context) { create(:security_project_tracked_context, :tracked, project: project) }

  let(:args) { {} }
  let(:query) do
    graphql_query_for(:group, { fullPath: group.full_path }, query_nodes(:dependencies, 'id reachability', args: args))
  end

  let(:reachability) do
    graphql_data_at(:group, :dependencies, :nodes)
      .find { |node| node['id'] == occurrence.to_gid.to_s }['reachability']
  end

  before_all do
    create(:sbom_occurrence_ref, occurrence: occurrence, project: project, tracked_context: default_context,
      reachability: :not_found)
    create(:sbom_occurrence_ref, occurrence: occurrence, project: project, tracked_context: feature_context,
      reachability: :in_use)
  end

  before do
    stub_licensed_features(dependency_scanning: true, security_dashboard: true)
    stub_feature_flags(vulnerabilities_across_contexts: true)
  end

  describe 'reachability field' do
    context 'when filtered by a tracked ref' do
      let(:args) { { tracked_ref_ids: [feature_context.to_global_id] } }

      it 'ignores the filter like the rows do and returns the default branch value', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(reachability).to eq('NOT_FOUND')
      end
    end
  end
end
