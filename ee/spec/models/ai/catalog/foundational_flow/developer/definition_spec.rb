# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::Developer::Definition, feature_category: :duo_agent_platform do
  subject(:flow) { Ai::Catalog::FoundationalFlow.developer_v1 }

  let(:project) { build_stubbed(:project) }
  let_it_be(:user) { create(:user) }

  it 'grants the privileges its flow config needs, including run_command', :aggregate_failures do
    expect(flow.agent_privileges).to eq([
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_FILES,
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_ONLY_GITLAB,
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_GITLAB,
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::RUN_COMMANDS,
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::USE_GIT
    ])
  end

  it 'requires only the privileges its own toolset binds' do
    expect(flow.required_agent_privileges).to eq([
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::READ_WRITE_FILES,
      ::Ai::DuoWorkflows::Workflow::AgentPrivileges::RUN_COMMANDS
    ])
  end

  it 'accepts a trigger goal' do
    expect(flow.accepts_trigger_goal).to be(true)
  end

  describe 'resolve_flow_version_for' do
    subject(:resolved) { flow.resolve_flow_version_for(container: project, user: user) }

    before do
      stub_feature_flags(duo_developer_continuable_sessions: false)
    end

    it 'returns the flow own reference and version' do
      expect(resolved).to eq(
        flow_config_id: 'developer',
        flow_config_schema_version: 'v1',
        flow_version: '^3.0.0'
      )
    end

    context 'when duo_developer_orbit is enabled and the orbit killswitch is on' do
      before do
        stub_feature_flags(duo_developer_orbit: user)
        user.user_preference.update!(orbit_settings: { 'enabled' => true })
      end

      it 'returns the flow own reference and version' do
        expect(resolved).to eq(
          flow_config_id: 'developer',
          flow_config_schema_version: 'v1',
          flow_version: '^3.0.0'
        )
      end
    end

    context 'with duo_developer_continuable_sessions' do
      let_it_be(:root_group) { create(:group) }
      let_it_be(:subgroup) { create(:group, parent: root_group) }
      let_it_be(:project) { create(:project, group: subgroup) }

      shared_examples 'resolves developer 4.0.0' do
        it 'overrides the version to ^4.0.0' do
          expect(resolved).to eq(
            flow_config_id: 'developer',
            flow_config_schema_version: 'v1',
            flow_version: '^4.0.0'
          )
        end
      end

      context 'when enabled for the user' do
        before do
          stub_feature_flags(duo_developer_continuable_sessions: user)
        end

        it_behaves_like 'resolves developer 4.0.0'
      end

      context 'when enabled for the top-level group of the container' do
        before do
          stub_feature_flags(duo_developer_continuable_sessions: root_group)
        end

        it_behaves_like 'resolves developer 4.0.0'
      end

      context 'when enabled only for the subgroup of the container' do
        before do
          stub_feature_flags(duo_developer_continuable_sessions: subgroup)
        end

        it 'keeps ^3.0.0' do
          expect(resolved[:flow_version]).to eq('^3.0.0')
        end
      end

      context 'when the container is nil' do
        subject(:resolved) { flow.resolve_flow_version_for(container: nil, user: user) }

        before do
          stub_feature_flags(duo_developer_continuable_sessions: root_group)
        end

        it 'keeps ^3.0.0 without raising' do
          expect(resolved[:flow_version]).to eq('^3.0.0')
        end
      end
    end
  end
end
