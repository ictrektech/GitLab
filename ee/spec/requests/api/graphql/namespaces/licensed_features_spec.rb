# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'namespace.licensedFeatures', feature_category: :team_planning do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:namespace) { create(:group, developers: user) }

  let(:query) do
    graphql_query_for(
      :namespace,
      { full_path: namespace.full_path },
      query_graphql_field(:available_features, available_features_fields)
    )
  end

  let(:available_features_fields) do
    <<~FIELDS
      hasBlockedIssuesFeature
      hasCustomFieldsFeature
      hasEpicsFeature
      hasGroupBulkEditFeature
      hasIssuableHealthStatusFeature
      hasIssueWeightsFeature
      hasIterationsFeature
      hasLinkedItemsEpicsFeature
      hasOkrsFeature
      hasQualityManagementFeature
      hasScopedLabelsFeature
      hasSubepicsFeature
      hasWorkItemStatusFeature
    FIELDS
  end

  context 'when features are available' do
    before do
      stub_licensed_features(
        blocked_issues: true,
        custom_fields: true,
        epics: true,
        group_bulk_edit: true,
        issuable_health_status: true,
        issue_weights: true,
        iterations: true,
        linked_items_epics: true,
        okrs: true,
        quality_management: true,
        scoped_labels: true,
        subepics: true,
        work_item_status: true
      )
    end

    it 'returns true' do
      post_graphql(query, current_user: user)

      expect(graphql_data_at(:namespace, :available_features)).to eq(
        'hasBlockedIssuesFeature' => true,
        'hasCustomFieldsFeature' => true,
        'hasEpicsFeature' => true,
        'hasGroupBulkEditFeature' => true,
        'hasIssuableHealthStatusFeature' => true,
        'hasIssueWeightsFeature' => true,
        'hasIterationsFeature' => true,
        'hasLinkedItemsEpicsFeature' => true,
        'hasOkrsFeature' => true,
        'hasQualityManagementFeature' => true,
        'hasScopedLabelsFeature' => true,
        'hasSubepicsFeature' => true,
        'hasWorkItemStatusFeature' => true
      )
    end
  end

  context 'when features are not available' do
    before do
      stub_licensed_features(
        blocked_issues: false,
        custom_fields: false,
        epics: false,
        group_bulk_edit: false,
        issuable_health_status: false,
        issue_weights: false,
        iterations: false,
        linked_items_epics: false,
        okrs: false,
        quality_management: false,
        scoped_labels: false,
        subepics: false,
        work_item_status: false
      )
    end

    it 'returns false' do
      post_graphql(query, current_user: user)

      expect(graphql_data_at(:namespace, :available_features)).to eq(
        'hasBlockedIssuesFeature' => false,
        'hasCustomFieldsFeature' => false,
        'hasEpicsFeature' => false,
        'hasGroupBulkEditFeature' => false,
        'hasIssuableHealthStatusFeature' => false,
        'hasIssueWeightsFeature' => false,
        'hasIterationsFeature' => false,
        'hasLinkedItemsEpicsFeature' => false,
        'hasOkrsFeature' => false,
        'hasQualityManagementFeature' => false,
        'hasScopedLabelsFeature' => false,
        'hasSubepicsFeature' => false,
        'hasWorkItemStatusFeature' => false
      )
    end
  end

  describe 'granular PAT authorization (NamespaceAvailableFeatures child type)' do
    # Use a private group so the public-access bypass does not apply and the
    # parent GroupType's authorize_granular_token (boundary: :itself,
    # boundary_type: :group) is the sole gate.
    let_it_be(:private_group) { create(:group, :private, developers: user) }

    let(:group_query) do
      graphql_query_for(
        :group,
        { full_path: private_group.full_path },
        query_graphql_field(:available_features, 'hasEpicsFeature')
      )
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
      :read_group do
      let(:boundary_object) { private_group }
      let(:request) { post_graphql(group_query, current_user: user, token: { personal_access_token: pat }) }
      let(:skipped_data_path) { %i[group available_features] }
    end

    # NamespaceAvailableFeatures is also reachable via the `namespace` root field with a
    # project namespace full path, where NamespaceType's read_namespace directive gates it.
    context 'when accessed via a project namespace' do
      let_it_be(:project) { create(:project, :private, developers: user) }

      let(:project_namespace_query) do
        graphql_query_for(
          :namespace,
          { full_path: project.full_path },
          query_graphql_field(:available_features, 'hasEpicsFeature')
        )
      end

      it 'resolves the project namespace for a legacy PAT' do
        pat = create(:personal_access_token, user: user)
        post_graphql(project_namespace_query, current_user: user, token: { personal_access_token: pat })

        expect(graphql_data_at(:namespace, :available_features)).to be_present
      end

      it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
        :read_namespace do
        let(:boundary_object) { project }
        let(:request) do
          post_graphql(project_namespace_query, current_user: user, token: { personal_access_token: pat })
        end

        let(:skipped_data_path) { %i[namespace available_features] }
      end
    end
  end
end
