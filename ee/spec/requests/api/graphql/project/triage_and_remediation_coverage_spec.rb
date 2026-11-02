# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying a project\'s triage and remediation coverage', feature_category: :security_asset_inventories do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, developer_of: project) }

  let(:query) do
    graphql_query_for(:project, { full_path: project.full_path },
      query_graphql_field(:triage_and_remediation_coverage, {},
        'capabilities { triggerType enabled runMode flowStatus }'))
  end

  let(:coverage_data) { graphql_data_at(:project, :triage_and_remediation_coverage) }

  before do
    stub_licensed_features(security_scan_profiles: true)
  end

  context 'when the project is not licensed for security scan profiles' do
    before do
      stub_licensed_features(security_scan_profiles: false)
    end

    it 'returns null for the field', :aggregate_failures do
      post_graphql(query, current_user: user)

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:project)).to include('triageAndRemediationCoverage' => nil)
    end
  end

  context 'when the user cannot read security scan profiles' do
    let_it_be(:reporter) { create(:user, reporter_of: project) }

    it 'returns null for the field', :aggregate_failures do
      post_graphql(query, current_user: reporter)

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:project)).to include('triageAndRemediationCoverage' => nil)
    end
  end

  context 'when the project has no security_inventory_filters row' do
    before do
      NamespaceSetting.find_by!(namespace_id: group.id).update!(duo_foundational_flows_enabled: true)
      stub_licensed_features(security_scan_profiles: true, ai_features: true, ai_workflows: true)
      stub_application_setting(instance_level_ai_beta_features_enabled: true)
    end

    it 'returns a zero-valued capability for every trigger type' do
      post_graphql(query, current_user: user)

      expect(graphql_errors).to be_nil
      expect(coverage_data['capabilities']).to contain_exactly(
        { 'triggerType' => 'SBOM_INGESTED', 'enabled' => false, 'runMode' => nil, 'flowStatus' => 'FLOW_NOT_ENABLED' },
        { 'triggerType' => 'SAST_FALSE_POSITIVE', 'enabled' => false, 'runMode' => nil,
          'flowStatus' => 'FLOW_NOT_ENABLED' },
        { 'triggerType' => 'SAST_VULNERABILITY_RESOLUTION', 'enabled' => false, 'runMode' => nil,
          'flowStatus' => 'FLOW_NOT_ENABLED' },
        { 'triggerType' => 'SECRET_DETECTION_FALSE_POSITIVE', 'enabled' => false, 'runMode' => nil,
          'flowStatus' => 'FLOW_NOT_ENABLED' },
        { 'triggerType' => 'VULNERABILITY_ENRICHMENT', 'enabled' => false, 'runMode' => nil,
          'flowStatus' => 'NOT_APPLICABLE' }
      )
    end
  end

  context 'when the project has capabilities attached' do
    before do
      NamespaceSetting.find_by!(namespace_id: group.id).update!(duo_foundational_flows_enabled: false)
      create(:security_inventory_filters, project: project,
        triage_capabilities: {
          sbom_ingested: [true, false],
          sast_false_positive: [true, true],
          sast_vulnerability_resolution: [true, false]
        })
    end

    it 'returns the enabled state and run mode for each trigger type' do
      post_graphql(query, current_user: user)

      expect(graphql_errors).to be_nil
      expect(coverage_data['capabilities']).to contain_exactly(
        { 'triggerType' => 'SBOM_INGESTED', 'enabled' => true, 'runMode' => nil,
          'flowStatus' => 'FOUNDATIONAL_FLOWS_DISABLED' },
        { 'triggerType' => 'SAST_FALSE_POSITIVE', 'enabled' => true, 'runMode' => 'AUTO',
          'flowStatus' => 'FOUNDATIONAL_FLOWS_DISABLED' },
        { 'triggerType' => 'SAST_VULNERABILITY_RESOLUTION', 'enabled' => true, 'runMode' => 'MANUAL',
          'flowStatus' => 'FOUNDATIONAL_FLOWS_DISABLED' },
        { 'triggerType' => 'SECRET_DETECTION_FALSE_POSITIVE', 'enabled' => false, 'runMode' => nil,
          'flowStatus' => 'FOUNDATIONAL_FLOWS_DISABLED' },
        { 'triggerType' => 'VULNERABILITY_ENRICHMENT', 'enabled' => false, 'runMode' => nil,
          'flowStatus' => 'NOT_APPLICABLE' }
      )
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL',
      %i[read_project read_security_scan_profiles] do
      let(:boundary_object) { project }
      let(:request) { post_graphql(query, token: { personal_access_token: pat }) }
    end
  end

  describe 'flowStatus' do
    let_it_be(:organization) { group.organization }
    let_it_be(:sast_fp_item) do
      create(:ai_catalog_item, :with_foundational_flow_reference, foundational_flow_reference: 'sast_fp_detection/v1',
        organization: organization)
    end

    let_it_be(:subgroup) { create(:group, parent: group) }
    let_it_be(:subgroup_project) { create(:project, group: subgroup) }

    before_all do
      group.add_developer(user)
    end

    def enable_flows(root)
      NamespaceSetting.find_by!(namespace_id: root.id).update!(duo_foundational_flows_enabled: true)
    end

    def flow_status(data, trigger_type)
      data['capabilities'].find { |c| c['triggerType'] == trigger_type }['flowStatus']
    end

    before do
      stub_licensed_features(security_scan_profiles: true, ai_features: true, ai_workflows: true)
      stub_application_setting(instance_level_ai_beta_features_enabled: true)
      enable_flows(group)
    end

    context 'when the flow is enabled on the root group' do
      before do
        group.sync_enabled_foundational_flows!([sast_fp_item.id])
      end

      it 'returns available for the enabled flow and not enabled for the others', :aggregate_failures do
        post_graphql(query, current_user: user)

        expect(graphql_errors).to be_nil
        expect(flow_status(coverage_data, 'SAST_FALSE_POSITIVE')).to eq('AVAILABLE')
        expect(flow_status(coverage_data, 'SAST_VULNERABILITY_RESOLUTION')).to eq('FLOW_NOT_ENABLED')
        expect(flow_status(coverage_data, 'VULNERABILITY_ENRICHMENT')).to eq('NOT_APPLICABLE')
      end

      context 'when the project is in a subgroup' do
        let_it_be(:sub_user) { create(:user, developer_of: subgroup_project) }
        let(:query) do
          graphql_query_for(:project, { full_path: subgroup_project.full_path },
            query_graphql_field(:triage_and_remediation_coverage, {}, 'capabilities { triggerType flowStatus }'))
        end

        it 'returns the root group status' do
          post_graphql(query, current_user: sub_user)

          expect(graphql_errors).to be_nil
          expect(flow_status(coverage_data, 'SAST_FALSE_POSITIVE')).to eq('AVAILABLE')
        end
      end
    end

    describe 'batching' do
      let_it_be(:other_subgroup) { create(:group, parent: group) }
      let(:projects_query) do
        graphql_query_for(:group, { full_path: group.full_path },
          'projects(includeSubgroups: true) { nodes { ' \
            'triageAndRemediationCoverage { capabilities { triggerType flowStatus } } } }')
      end

      before do
        group.sync_enabled_foundational_flows!([sast_fp_item.id])
      end

      it 'resolves flow availability once for all projects' do
        [subgroup, other_subgroup].each do |sg|
          create(:project, group: sg)
          create(:security_inventory_filters, project: create(:project, group: sg),
            triage_capabilities: { sast_false_positive: [true, false] })
        end

        expect(::Security::TriageCoverage::ProjectCapabilities).to receive(:for_projects).once.and_call_original

        post_graphql(projects_query, current_user: user)

        expect(graphql_errors).to be_nil
        nodes = graphql_data_at(:group, :projects, :nodes)
        capabilities = nodes.flat_map { |n| n.dig('triageAndRemediationCoverage', 'capabilities') }

        expect(nodes.size).to eq(6)
        expect(capabilities.group_by { |c| c['triggerType'] }.transform_values { |c| c.pluck('flowStatus').uniq })
          .to eq(
            'SBOM_INGESTED' => ['FLOW_NOT_ENABLED'],
            'SAST_FALSE_POSITIVE' => ['AVAILABLE'],
            'SAST_VULNERABILITY_RESOLUTION' => ['FLOW_NOT_ENABLED'],
            'SECRET_DETECTION_FALSE_POSITIVE' => ['FLOW_NOT_ENABLED'],
            'VULNERABILITY_ENRICHMENT' => ['NOT_APPLICABLE']
          )
      end

      it 'returns each project its own root group status in one batch', :aggregate_failures do
        other_root = create(:group)
        enable_flows(other_root)
        other_project = create(:project, group: other_root)
        other_root.add_developer(user)
        fields = 'triageAndRemediationCoverage { capabilities { triggerType flowStatus } }'
        batched_query = <<~GQL
          query {
            enabled: project(fullPath: "#{project.full_path}") { #{fields} }
            notEnabled: project(fullPath: "#{other_project.full_path}") { #{fields} }
          }
        GQL

        expect(::Security::TriageCoverage::ProjectCapabilities).to receive(:for_projects).once.and_call_original

        post_graphql(batched_query, current_user: user)

        expect(graphql_errors).to be_nil
        expect(flow_status(graphql_data_at(:enabled, :triage_and_remediation_coverage), 'SAST_FALSE_POSITIVE'))
          .to eq('AVAILABLE')
        expect(flow_status(graphql_data_at(:not_enabled, :triage_and_remediation_coverage), 'SAST_FALSE_POSITIVE'))
          .to eq('FLOW_NOT_ENABLED')
      end
    end
  end
end
