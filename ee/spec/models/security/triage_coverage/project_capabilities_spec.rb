# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::TriageCoverage::ProjectCapabilities, feature_category: :security_asset_inventories do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:sast_fp_item) do
    create(:ai_catalog_item, :with_foundational_flow_reference, foundational_flow_reference: 'sast_fp_detection/v1',
      organization: organization)
  end

  let_it_be(:secrets_fp_item) do
    create(:ai_catalog_item, :with_foundational_flow_reference, foundational_flow_reference: 'secrets_fp_detection/v1',
      organization: organization)
  end

  let_it_be_with_reload(:root) do
    create(:group, organization: organization).tap do |g|
      g.namespace_settings.update!(duo_foundational_flows_enabled: true)
    end
  end

  let_it_be(:subgroup) { create(:group, parent: root, organization: organization) }
  let_it_be(:root_project) { create(:project, group: root) }
  let_it_be(:subgroup_project) { create(:project, group: subgroup) }

  def statuses_for(project)
    described_class.for_projects([project])[project.id].to_h { |c| [c[:trigger_type], c[:flow_status]] }
  end

  it 'is keyed by project id with a flow_status on every capability', :aggregate_failures do
    result = described_class.for_projects([root_project, subgroup_project])

    expect(result.keys).to contain_exactly(root_project.id, subgroup_project.id)
    expect(result.values.flatten.map { |c| c[:flow_status] }).to all(be_a(Symbol))
  end

  context 'with and without an inventory filter row' do
    let_it_be(:filtered_project) { create(:project, group: root) }

    before_all do
      create(:security_inventory_filters, project: filtered_project,
        triage_capabilities: { sast_false_positive: [true, true] })
    end

    before do
      stub_licensed_features(ai_features: true, ai_workflows: true)
    end

    it 'decodes the row and falls back to zero-valued capabilities', :aggregate_failures do
      result = described_class.for_projects([filtered_project, root_project])
      sast = ->(project) { result[project.id].find { |c| c[:trigger_type] == :sast_false_positive } }

      expect(sast.call(filtered_project)).to include(enabled: true, run_mode: :auto, flow_status: :flow_not_enabled)
      expect(sast.call(root_project)).to include(enabled: false, flow_status: :flow_not_enabled)
      expect(result[root_project.id].size).to eq(Security::TriageCoverage::CapabilityBitmask.trigger_types.size)
    end
  end

  it 'maps exactly the capability trigger types' do
    expect(described_class::FLOW_BY_TRIGGER.keys)
      .to match_array(Security::TriageCoverage::CapabilityBitmask.trigger_types)
  end

  it 'returns one entry per trigger type, not applicable when there is no flow', :aggregate_failures do
    stub_licensed_features(ai_features: true, ai_workflows: true)

    expect(statuses_for(root_project).keys).to match_array(Security::TriageCoverage::CapabilityBitmask.trigger_types)
    expect(statuses_for(root_project)[:vulnerability_enrichment]).to eq(:not_applicable)
  end

  context 'when foundational flows are disabled for the root group' do
    before do
      stub_licensed_features(ai_features: true, ai_workflows: true)
      root.namespace_settings.update!(duo_foundational_flows_enabled: false)
    end

    it 'disables the flow triggers and keeps not_applicable for triggers without a flow', :aggregate_failures do
      expect(statuses_for(root_project)[:sast_false_positive]).to eq(:foundational_flows_disabled)
      expect(statuses_for(root_project)[:vulnerability_enrichment]).to eq(:not_applicable)
    end

    it 'wins over an unavailable flow' do
      stub_licensed_features(ai_features: false)

      expect(statuses_for(root_project)[:sast_false_positive]).to eq(:foundational_flows_disabled)
    end

    it 'wins over an enabled flow' do
      root.sync_enabled_foundational_flows!([sast_fp_item.id])

      expect(statuses_for(root_project)[:sast_false_positive]).to eq(:foundational_flows_disabled)
    end
  end

  context 'when the flow accessor returns nil' do
    before do
      stub_licensed_features(ai_features: true, ai_workflows: true)
      allow(Ai::Catalog::FoundationalFlow).to receive(:sast_fp_detection_v1).and_return(nil)
    end

    it { expect(statuses_for(root_project)[:sast_false_positive]).to eq(:flow_unavailable) }
  end

  context 'when the root group is not licensed for workflows' do
    before do
      stub_licensed_features(ai_features: true, ai_workflows: false)
      root.sync_enabled_foundational_flows!([sast_fp_item.id])
    end

    it 'is unavailable even for an enabled flow', :aggregate_failures do
      expect(statuses_for(root_project)[:sast_false_positive]).to eq(:flow_unavailable)
      expect(statuses_for(root_project)[:vulnerability_enrichment]).to eq(:not_applicable)
    end

    it 'is available with an active credits add-on', :saas do
      create(:gitlab_subscription_add_on_purchase, :gitlab_credits, namespace: root)

      expect(statuses_for(root_project)[:sast_false_positive]).to eq(:available)
    end
  end

  context 'when foundational flows are disabled' do
    it 'does not run the stage check' do
      stub_licensed_features(ai_features: true, ai_workflows: true)
      root.namespace_settings.update!(duo_foundational_flows_enabled: false)

      expect(Gitlab::Llm::StageCheck).not_to receive(:available?)

      statuses_for(root_project)
    end
  end

  it 'runs the stage check once per root group, not once per trigger or project' do
    stub_licensed_features(ai_features: true, ai_workflows: true)

    expect(Gitlab::Llm::StageCheck).to receive(:available?).once.with(root, :duo_workflow).and_call_original

    described_class.for_projects([root_project, subgroup_project])
  end

  context 'when the flow is enabled but not available' do
    before do
      root.sync_enabled_foundational_flows!([sast_fp_item.id])
      stub_licensed_features(ai_features: false)
    end

    it { expect(statuses_for(root_project)[:sast_false_positive]).to eq(:flow_unavailable) }
  end

  context 'when a beta flow is blocked by the beta features setting' do
    before do
      stub_licensed_features(ai_features: true, ai_workflows: true)
      stub_application_setting(instance_level_ai_beta_features_enabled: false)
    end

    it 'is unavailable while ga flows are not', :aggregate_failures do
      expect(statuses_for(root_project)[:sbom_ingested]).to eq(:flow_unavailable)
      expect(statuses_for(root_project)[:sast_false_positive]).to eq(:flow_not_enabled)
    end
  end

  context 'when the flow is available but not enabled' do
    before do
      stub_licensed_features(ai_features: true, ai_workflows: true)
    end

    it { expect(statuses_for(root_project)[:sast_false_positive]).to eq(:flow_not_enabled) }
  end

  context 'when the flow is available and turned on for the root group' do
    before do
      stub_licensed_features(ai_features: true, ai_workflows: true)
      root.sync_enabled_foundational_flows!([sast_fp_item.id])
    end

    it 'is available only for the turned on flow, also for subgroup projects', :aggregate_failures do
      expect(statuses_for(root_project)).to include(
        sast_false_positive: :available,
        secret_detection_false_positive: :flow_not_enabled
      )
      expect(statuses_for(subgroup_project)[:sast_false_positive]).to eq(:available)
    end
  end

  it 'returns an empty hash for no projects' do
    expect(described_class.for_projects([])).to eq({})
  end

  context 'when the root group cannot be resolved' do
    let_it_be(:personal_project) { create(:project, namespace: create(:user, :with_namespace).namespace) }
    let(:unresolved) do
      Security::TriageCoverage::CapabilityBitmask.trigger_types.index_with { :flow_unavailable }
        .merge(vulnerability_enrichment: :not_applicable)
    end

    it 'returns a fixed entry for a personal namespace project' do
      expect(statuses_for(personal_project)).to eq(unresolved)
    end

    it 'returns a fixed entry for a project whose root cannot be resolved' do
      allow(Project).to receive(:root_namespace_ids_by_project_ids).and_return({})

      expect(statuses_for(root_project)).to eq(unresolved)
    end

    it 'resolves a mixed batch per project', :aggregate_failures do
      stub_licensed_features(ai_features: true, ai_workflows: true)
      root.sync_enabled_foundational_flows!([sast_fp_item.id])
      result = described_class.for_projects([root_project, personal_project])
      statuses = ->(project) { result[project.id].to_h { |c| [c[:trigger_type], c[:flow_status]] } }

      expect(statuses.call(root_project)[:sast_false_positive]).to eq(:available)
      expect(statuses.call(personal_project)).to eq(unresolved)
    end
  end

  context 'with two root groups' do
    let_it_be_with_reload(:other_root) do
      create(:group, organization: organization).tap do |g|
        g.namespace_settings.update!(duo_foundational_flows_enabled: true)
      end
    end

    let_it_be(:other_project) { create(:project, group: other_root) }

    before do
      stub_licensed_features(ai_features: true, ai_workflows: true)
      root.sync_enabled_foundational_flows!([sast_fp_item.id])
      other_root.sync_enabled_foundational_flows!([secrets_fp_item.id])
    end

    it 'resolves each root independently', :aggregate_failures do
      expect(statuses_for(root_project)).to include(sast_false_positive: :available,
        secret_detection_false_positive: :flow_not_enabled)
      expect(statuses_for(other_project)).to include(sast_false_positive: :flow_not_enabled,
        secret_detection_false_positive: :available)
    end
  end

  describe 'query budget' do
    it 'does not grow with the number of projects of the same root' do
      root.sync_enabled_foundational_flows!([sast_fp_item.id])
      one = create(:project, group: create(:group, parent: root, organization: organization))
      others = create_list(:project, 5, group: subgroup)

      described_class.for_projects([one])
      control = ActiveRecord::QueryRecorder.new { described_class.for_projects([one]) }

      expect { described_class.for_projects(others) }.not_to exceed_query_limit(control)
    end
  end

  describe 'SaaS licensing lookups', :saas do
    def ultimate_root
      create(:group_with_plan, plan: :ultimate_plan, organization: organization).then do |g|
        g.namespace_settings.update!(duo_foundational_flows_enabled: true)
        create(:project, group: create(:group, parent: g, organization: organization))
      end
    end

    it 'adds at most the credits add-on lookup per extra root group and reaches the licensing check',
      :aggregate_failures do
      two = Array.new(2) { ultimate_root }
      three = Array.new(3) { ultimate_root }

      described_class.for_projects(two)
      control = ActiveRecord::QueryRecorder.new { described_class.for_projects(two) }

      expect { described_class.for_projects(three) }.not_to exceed_query_limit(control).with_threshold(1)
      expect(statuses_for(three.first)[:sast_false_positive]).to eq(:flow_unavailable)
    end
  end
end
