# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::SastFpDetection::Definition, feature_category: :duo_agent_platform do
  subject(:flow) { Ai::Catalog::FoundationalFlow.sast_fp_detection_v1 }

  it 'disallows event triggers' do
    expect(flow.supported_events).to eq([])
  end

  describe '#resolve_flow_version_for' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: create(:group, parent: group)) }

    subject(:resolved) { flow.resolve_flow_version_for(container: project, user: nil) }

    context 'when sast_fp_detection_flow_1_1_0 is disabled' do
      before do
        stub_feature_flags(sast_fp_detection_flow_1_1_0: false)
      end

      it 'returns the flow own reference and version' do
        expect(resolved).to eq(
          flow_config_id: 'sast_fp_detection',
          flow_config_schema_version: 'v1',
          flow_version: '1.0.0'
        )
      end
    end

    context 'when sast_fp_detection_flow_1_1_0 is enabled for the root ancestor' do
      before do
        stub_feature_flags(sast_fp_detection_flow_1_1_0: group)
      end

      it 'overrides to flow version 1.1.0-dev' do
        expect(resolved).to eq(
          flow_config_id: 'sast_fp_detection',
          flow_config_schema_version: 'v1',
          flow_version: '1.1.0-dev'
        )
      end
    end

    context 'when sast_fp_detection_flow_1_1_0 is enabled for another group' do
      before do
        stub_feature_flags(sast_fp_detection_flow_1_1_0: create(:group))
      end

      it 'returns the flow own version' do
        expect(resolved[:flow_version]).to eq('1.0.0')
      end
    end
  end

  describe 'source branch resolution' do
    let_it_be(:project) { create(:project) }
    let_it_be(:other_project) { create(:project) }
    let_it_be(:other_vulnerability) { create(:vulnerability, :with_finding, project: other_project) }
    let_it_be(:tracked_context) do
      create(:security_project_tracked_context, :tracked, project: project, context_name: 'feature-branch')
    end

    let_it_be(:vulnerability) do
      create(:vulnerability, :with_finding, project: project).tap do |vulnerability|
        vulnerability.finding.update!(project_tracked_context: tracked_context)
      end
    end

    subject(:source_branch) { flow.resolve_source_branch_for(project: project, goal: goal) }

    before do
      allow(Security::VAC).to receive(:enabled?).and_return(true)
    end

    context 'when the goal is the ID of a vulnerability on a non-default branch' do
      let(:goal) { vulnerability.id.to_s }

      it { is_expected.to eq('feature-branch') }

      context 'when the fp_detection_non_default_branches flag is disabled' do
        before do
          stub_feature_flags(fp_detection_non_default_branches: false)
        end

        it { is_expected.to be_nil }
      end
    end

    context 'when the goal is the ID of a vulnerability in another project' do
      let(:goal) { other_vulnerability.id.to_s }

      it { is_expected.to be_nil }
    end

    context 'when no vulnerability matches the ID' do
      let(:goal) { non_existing_record_id.to_s }

      it { is_expected.to be_nil }
    end

    context 'when the goal is not a vulnerability ID' do
      let(:goal) { "Analyze vulnerability #{vulnerability.id}" }

      it { is_expected.to be_nil }
    end

    context 'when the goal is nil' do
      let(:goal) { nil }

      it { is_expected.to be_nil }
    end
  end
end
