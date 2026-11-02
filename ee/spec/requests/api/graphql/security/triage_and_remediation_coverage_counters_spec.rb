# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query.group.triageAndRemediationCoverageCounters', feature_category: :security_asset_inventories do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:enabled_project) { create(:project, namespace: group) }
  let_it_be(:auto_project) { create(:project, namespace: group) }
  let_it_be(:uncovered_project) { create(:project, namespace: group) }

  let_it_be(:enabled_filter) do
    create(:security_inventory_filters, project: enabled_project,
      triage_capabilities: { sast_false_positive: [true, false] })
  end

  let_it_be(:auto_filter) do
    create(:security_inventory_filters, project: auto_project,
      triage_capabilities: { sast_false_positive: [true, true] })
  end

  let_it_be(:uncovered_filter) { create(:security_inventory_filters, project: uncovered_project) }

  let(:query) do
    <<~GQL
      query($fullPath: ID!, $triggerType: ScanProfileTriggerType!) {
        group(fullPath: $fullPath) {
          triageAndRemediationCoverageCounters(triggerType: $triggerType) {
            enabledCount
            autoCount
          }
        }
      }
    GQL
  end

  let(:trigger_type) { 'SAST_FALSE_POSITIVE' }
  let(:variables) { { fullPath: group.full_path, triggerType: trigger_type } }
  let(:counters_data) { graphql_data_at(:group, :triage_and_remediation_coverage_counters) }

  subject(:execute_query) { post_graphql(query, current_user: current_user, variables: variables) }

  before do
    stub_licensed_features(security_scan_profiles: true)
  end

  context 'when the user does not have permission' do
    it 'returns null for the field' do
      execute_query

      expect(graphql_errors).to be_nil
      expect(counters_data).to be_nil
    end
  end

  context 'when the user has permission' do
    before_all do
      group.add_developer(current_user)
    end

    it 'returns the enabled and auto counts for the given trigger type' do
      execute_query

      expect(graphql_errors).to be_nil
      expect(counters_data).to eq('enabledCount' => 2, 'autoCount' => 1)
    end

    # `read_group` authorizes traversing the parent `Group` type,
    # `read_security_scan_profiles` the `TriageAndRemediationCoverageCounters` type
    it_behaves_like 'authorizing granular token permissions for GraphQL',
      %i[read_group read_security_scan_profiles] do
      let(:user) { current_user }
      let(:boundary_object) { group }
      let(:request) { post_graphql(query, token: { personal_access_token: pat }, variables: variables) }
    end

    context 'when the security_scan_profiles license is unavailable' do
      before do
        stub_licensed_features(security_scan_profiles: false)
      end

      it 'returns null for the field' do
        execute_query

        expect(graphql_errors).to be_nil
        expect(counters_data).to be_nil
      end
    end

    context 'with a trigger type that has no matching filters' do
      let(:trigger_type) { 'SAST_VULNERABILITY_RESOLUTION' }

      it 'returns zero counts' do
        execute_query

        expect(graphql_errors).to be_nil
        expect(counters_data).to eq('enabledCount' => 0, 'autoCount' => 0)
      end
    end

    context 'with a valid trigger type that has no triage bit' do
      let(:trigger_type) { 'DEFAULT_BRANCH_PIPELINE' }

      it 'returns null' do
        execute_query

        expect(graphql_errors).to be_nil
        expect(counters_data).to be_nil
      end
    end
  end
end
