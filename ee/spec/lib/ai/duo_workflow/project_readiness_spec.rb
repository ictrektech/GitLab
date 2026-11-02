# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflow::ProjectReadiness, feature_category: :duo_agent_platform do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, namespace: group) }
  let_it_be(:user) { create(:user, maintainer_of: project) }

  let(:readiness) { described_class.new(project, user) }

  describe '#platform_enabled?' do
    subject { readiness.platform_enabled? }

    it 'reports whether the Agent Platform is on above this project' do
      allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).with(project).and_return(true)

      is_expected.to be(true)
    end

    it 'is false when the platform is off' do
      allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).with(project).and_return(false)

      is_expected.to be(false)
    end

    # The self-managed path re-reads the Ai::Setting singleton on every call.
    it 'is read once' do
      expect(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).once.and_return(true)

      3.times { readiness.platform_enabled? }
    end
  end

  describe '#runner_available?' do
    subject { readiness.runner_available? }

    let(:workload_tag) { ::Ai::DuoWorkflows::Workflow.workload_tag_for(project) }

    def create_duo_runner(*traits, **runner_args)
      create(:ci_runner, :online, *traits, tag_list: [workload_tag], **runner_args).tap do |runner|
        create(:ci_runner_machine, runner: runner, executor_type: :docker)
      end
    end

    context 'with an online, Duo-tagged instance runner on a Docker executor' do
      before do
        create_duo_runner(:instance)
      end

      it { is_expected.to be(true) }
    end

    context 'with the workload tag routed by suspendable_workload_tag_for_dap' do
      def create_tagged_runner(tag)
        create(:ci_runner, :instance, :online, tag_list: [tag]).tap do |runner|
          create(:ci_runner_machine, runner: runner, executor_type: :docker)
        end
      end

      it 'ignores a runner tagged only gitlab--duo' do
        create_tagged_runner(::Ai::DuoWorkflows::Workflow::WORKLOAD_TAG)

        is_expected.to be(false)
      end

      it 'accepts a runner tagged gitlab--duo--suspendable' do
        create_tagged_runner(::Ai::DuoWorkflows::Workflow::SUSPENDABLE_WORKLOAD_TAG)

        is_expected.to be(true)
      end

      context 'when suspendable_workload_tag_for_dap is disabled' do
        before do
          stub_feature_flags(suspendable_workload_tag_for_dap: false)
        end

        it 'ignores a runner tagged only gitlab--duo--suspendable' do
          create_tagged_runner(::Ai::DuoWorkflows::Workflow::SUSPENDABLE_WORKLOAD_TAG)

          is_expected.to be(false)
        end

        it 'accepts a runner tagged gitlab--duo' do
          create_tagged_runner(::Ai::DuoWorkflows::Workflow::WORKLOAD_TAG)

          is_expected.to be(true)
        end
      end
    end

    it 'is false when no runner carries the workload tag' do
      runner = create(:ci_runner, :instance, :online, tag_list: %w[some-other-tag])
      create(:ci_runner_machine, runner: runner, executor_type: :docker)

      is_expected.to be(false)
    end

    it 'is false when the only tagged runner is paused' do
      create_duo_runner(:instance, :paused)

      is_expected.to be(false)
    end

    it 'is false when the only tagged runner has stopped checking in' do
      create_duo_runner(:instance, :offline)

      is_expected.to be(false)
    end

    it 'is false when the runner has no Docker-compatible executor' do
      runner = create(:ci_runner, :instance, :online, tag_list: [workload_tag])
      create(:ci_runner_machine, runner: runner, executor_type: :shell)

      is_expected.to be(false)
    end

    it 'is false when the runner never registered a manager' do
      create(:ci_runner, :instance, :online, tag_list: [workload_tag])

      is_expected.to be(false)
    end

    context 'when the only tagged runner is a project runner' do
      before do
        create_duo_runner(:project, projects: [project])
      end

      it { is_expected.to be(false) }

      context 'when duo_runner_restrictions is disabled' do
        before do
          stub_feature_flags(duo_runner_restrictions: false)
        end

        it { is_expected.to be(true) }
      end
    end

    context 'with a top-level group runner' do
      before do
        create_duo_runner(:group, groups: [group])
      end

      it { is_expected.to be(true) }
    end

    it 'looks the runner up once, however many readers ask' do
      expect(::Ci::Runner).to receive(:from_union).once.and_call_original

      readiness.runner_available?
      readiness.runner_available?
      readiness.usable_runner_type
    end

    it 'does not load the project runners that RunnerValidator rejects anyway' do
      create_duo_runner(:project, projects: [project])

      recorder = ActiveRecord::QueryRecorder.new { readiness.runner_available? }

      expect(recorder.log.grep(/ci_runner_projects/)).to be_empty
    end

    describe 'the candidate window' do
      before do
        stub_const("#{described_class}::RUNNER_CANDIDATE_LIMIT", 1)
      end

      it 'misses a usable runner older than everything in the window' do
        create_duo_runner(:instance)
        newer = create(:ci_runner, :instance, :online, tag_list: [workload_tag])
        create(:ci_runner_machine, runner: newer, executor_type: :shell)

        is_expected.to be(false)
      end

      it 'finds the usable runner inside the window' do
        older = create(:ci_runner, :instance, :online, tag_list: [workload_tag])
        create(:ci_runner_machine, runner: older, executor_type: :shell)
        create_duo_runner(:instance)

        is_expected.to be(true)
      end
    end
  end

  describe '#usable_runner_type' do
    subject { readiness.usable_runner_type }

    let(:workload_tag) { ::Ai::DuoWorkflows::Workflow.workload_tag_for(project) }

    def create_duo_runner(*traits, **runner_args)
      create(:ci_runner, :online, *traits, tag_list: [workload_tag], **runner_args).tap do |runner|
        create(:ci_runner_machine, runner: runner, executor_type: :docker)
      end
    end

    it 'is instance_type for an instance runner' do
      create_duo_runner(:instance)

      is_expected.to eq('instance_type')
    end

    it 'is group_type for a top-level group runner' do
      create_duo_runner(:group, groups: [group])

      is_expected.to eq('group_type')
    end

    context 'when duo_runner_restrictions is disabled, so project runners count too' do
      before do
        stub_feature_flags(duo_runner_restrictions: false)
      end

      it 'is project_type for a project runner' do
        create_duo_runner(:project, projects: [project])

        is_expected.to eq('project_type')
      end
    end

    it 'is nil when nothing qualifies' do
      is_expected.to be_nil
    end
  end

  describe '#agent_config_present?' do
    let_it_be(:repo_project) { create(:project, :repository, namespace: group, maintainers: user) }

    it 'is false when the file is absent from the default branch' do
      expect(described_class.new(repo_project, user).agent_config_present?).to be(false)
    end

    context 'when the file is on the default branch' do
      # A separate project: repository writes are not rolled back between examples, so
      # committing to a shared project would leak into every other example.
      let_it_be(:configured_project) do
        create(:project, :repository, namespace: group).tap do |configured|
          configured.repository.create_file(
            configured.creator,
            described_class::AGENT_CONFIG_PATH,
            "image: ruby:3.3\n",
            message: 'Add agent config',
            branch_name: configured.default_branch
          )
        end
      end

      it { expect(described_class.new(configured_project, user)).to be_agent_config_present }
    end
  end

  describe '#agent_config_merge_request' do
    let_it_be(:merge_request_project) { create(:project, :repository, namespace: group, maintainers: user) }
    let(:merge_request_readiness) { described_class.new(merge_request_project, user) }

    it 'is nil when nothing is open' do
      expect(merge_request_readiness.agent_config_merge_request).to be_nil
    end

    context 'when an open merge request adds the file' do
      let_it_be(:merge_request) do
        merge_request_project.repository.create_file(
          merge_request_project.creator,
          described_class::AGENT_CONFIG_PATH,
          "image: ruby:3.3\n",
          message: 'Add agent config',
          branch_name: 'add-agent-config'
        )

        create(:merge_request,
          source_project: merge_request_project,
          target_project: merge_request_project,
          source_branch: 'add-agent-config',
          target_branch: merge_request_project.default_branch)
      end

      it 'finds it, so the row can link to it instead of generating a duplicate' do
        expect(merge_request_readiness.agent_config_merge_request).to eq(merge_request)
      end

      it 'is skipped once the file is already on the default branch' do
        allow(merge_request_readiness).to receive(:agent_config_present?).and_return(true)

        expect(merge_request_readiness.agent_config_merge_request).to be_nil
      end
    end

    context 'when the open merge request is older than the lookup window' do
      let_it_be(:old_merge_request) do
        merge_request_project.repository.create_file(
          merge_request_project.creator,
          described_class::AGENT_CONFIG_PATH,
          "image: ruby:3.3\n",
          message: 'Add agent config',
          branch_name: 'add-agent-config-old'
        )

        create(:merge_request,
          source_project: merge_request_project,
          target_project: merge_request_project,
          source_branch: 'add-agent-config-old',
          target_branch: merge_request_project.default_branch,
          created_at: (described_class::AGENT_CONFIG_MERGE_REQUEST_WINDOW + 1.day).ago)
      end

      it 'is nil, so the lookup only reads the diffs of recent merge requests' do
        expect(merge_request_readiness.agent_config_merge_request).to be_nil
      end
    end

    context 'when the open merge request targets another branch' do
      let_it_be(:other_target_merge_request) do
        merge_request_project.repository.create_file(
          merge_request_project.creator,
          described_class::AGENT_CONFIG_PATH,
          "image: ruby:3.3\n",
          message: 'Add agent config',
          branch_name: 'add-agent-config-elsewhere'
        )

        create(:merge_request,
          source_project: merge_request_project,
          target_project: merge_request_project,
          source_branch: 'add-agent-config-elsewhere',
          target_branch: 'feature')
      end

      it 'is nil, since only the default branch is read for the config' do
        expect(merge_request_readiness.agent_config_merge_request).to be_nil
      end
    end
  end

  describe '#agent_config_workflow_id' do
    it 'is nil when no generation run is active' do
      expect(readiness.agent_config_workflow_id).to be_nil
    end

    context 'when a generation run is active' do
      let(:workflow) { build_stubbed(:duo_workflows_workflow) }

      before do
        allow_next_instance_of(::Ai::DuoWorkflow::AgentConfigWorkflowTracker) do |tracker|
          allow(tracker).to receive(:active_workflow).and_return(workflow)
        end
      end

      it 'returns the workflow id, so the row can link the running session' do
        expect(readiness.agent_config_workflow_id).to eq(workflow.id)
      end

      it 'is nil once the file is on the default branch' do
        allow(readiness).to receive(:agent_config_present?).and_return(true)

        expect(readiness.agent_config_workflow_id).to be_nil
      end
    end
  end

  describe '#repository_empty?' do
    let_it_be(:repo_project) { create(:project, :repository, namespace: group) }

    it 'is true when the project has no commits' do
      expect(readiness.repository_empty?).to be(true)
    end

    it 'is false when the default branch has commits' do
      expect(described_class.new(repo_project, user).repository_empty?).to be(false)
    end
  end

  describe '#generate_available?' do
    let_it_be(:repo_project) { create(:project, :repository, namespace: group) }

    let(:readiness_project) { repo_project }
    let(:readiness) { described_class.new(readiness_project, user) }

    subject { readiness.generate_available? }

    it 'is false when the developer flow has no consumer for the project' do
      is_expected.to be(false)
    end

    context 'when the catalog is unseeded' do
      before do
        allow(::Ai::Catalog::FoundationalFlow).to receive(:[]).and_return(nil)
      end

      it 'is false rather than raising' do
        is_expected.to be(false)
      end
    end

    context 'when a consumer exists for the project' do
      before do
        consumer = create(:ai_catalog_item_consumer, :for_flow, project: readiness_project)

        allow(::Ai::Catalog::FoundationalFlow.developer_v1).to receive(:catalog_item)
          .and_return(consumer.item)
      end

      it { is_expected.to be(true) }

      context 'when the repository is empty' do
        let(:readiness_project) { project }

        it 'is false, because the generate run has no commit to branch from' do
          is_expected.to be(false)
        end
      end
    end
  end

  describe '#mcp_servers_count' do
    let_it_be(:mcp_group, freeze: false) { create(:group) }
    let_it_be(:mcp_project) { create(:project, group: mcp_group) }
    let_it_be(:organization) { mcp_project.organization }

    let(:project) { mcp_project }
    let(:user) { create(:user, maintainer_of: mcp_project, organizations: [organization]) }

    subject(:count) { readiness.mcp_servers_count }

    before do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?)
        .with(user, :read_ai_catalog_item_consumer, mcp_project).and_return(true)
      allow(::Ai::Catalog).to receive(:mcp_servers_available?).with(user).and_return(true)
    end

    it 'is zero when no configured agent uses an MCP server' do
      expect(count).to eq(0)
    end

    context 'when configured agents use MCP servers' do
      let_it_be(:server) { create(:ai_catalog_mcp_server, organization: organization, name: 'linear') }
      let_it_be(:shared_server) { create(:ai_catalog_mcp_server, organization: organization, name: 'Atlassian') }

      before_all do
        create(:ai_catalog_mcp_server, organization: organization, name: 'Unused')

        [[server.id, shared_server.id], [shared_server.id]].each do |server_ids|
          create_configured_agent(server_ids)
        end

        mcp_group.namespace_settings.update!(duo_custom_agents_enabled: true)
      end

      def create_configured_agent(server_ids)
        agent = create(:ai_catalog_agent, organization: mcp_project.organization)
        create(:ai_catalog_agent_version, item: agent, definition: {
          'system_prompt' => 'Test prompt',
          'tools' => [],
          'user_prompt' => '',
          'mcp_servers' => server_ids
        })
        create(:ai_catalog_item_consumer, project: mcp_project, item: agent)
      end

      def create_pinned_agent(pinned_server_ids, latest_server_ids)
        agent = create(:ai_catalog_agent, organization: mcp_project.organization)
        pinned_version, _latest = [pinned_server_ids, latest_server_ids].map do |server_ids|
          create(:ai_catalog_agent_version, item: agent, definition: {
            'system_prompt' => 'Test prompt',
            'tools' => [],
            'user_prompt' => '',
            'mcp_servers' => server_ids
          })
        end

        create(:ai_catalog_item_consumer,
          project: mcp_project, item: agent, pinned_version_prefix: pinned_version.version)
      end

      it 'counts each server of the configured agents once' do
        expect(count).to eq(2)
      end

      it 'is read once' do
        expect(::Ai::Catalog::ItemConsumersFinder).to receive(:new).once.and_call_original

        2.times { readiness.mcp_servers_count }
      end

      it 'does not run a query per configured agent, pinned or not' do
        create_pinned_agent([server.id], [shared_server.id])

        control = ActiveRecord::QueryRecorder.new { described_class.new(project, user).mcp_servers_count }

        [[server.id], [shared_server.id]].each { |server_ids| create_configured_agent(server_ids) }
        create_pinned_agent([shared_server.id], [server.id])

        expect { described_class.new(project, user).mcp_servers_count }.not_to exceed_query_limit(control)
      end

      describe '#mcp_server_names' do
        it 'lists each server of the configured agents once, sorted case-insensitively' do
          expect(readiness.mcp_server_names).to eq(%w[Atlassian linear])
        end

        it 'lists a name shared by several servers once' do
          duplicate = create(:ai_catalog_mcp_server, organization: organization, name: 'linear')
          create_configured_agent([duplicate.id])

          expect(readiness.mcp_server_names).to eq(%w[Atlassian linear])
        end

        it 'lists a name shared across casings once' do
          duplicate = create(:ai_catalog_mcp_server, organization: organization, name: 'Linear')
          create_configured_agent([duplicate.id])

          expect(readiness.mcp_server_names).to eq(%w[Atlassian Linear])
        end

        it 'shares its lookup with the count' do
          expect(::Ai::Catalog::ItemConsumersFinder).to receive(:new).once.and_call_original

          readiness.mcp_server_names
          readiness.mcp_servers_count
        end
      end

      context 'when a configured agent pins an older version' do
        let_it_be(:pinned_server) { create(:ai_catalog_mcp_server, organization: organization, name: 'Sentry') }
        let_it_be(:latest_server) { create(:ai_catalog_mcp_server, organization: organization, name: 'Zendesk') }

        before do
          create_pinned_agent([pinned_server.id], [latest_server.id])
        end

        it 'lists the servers of the pinned version, not of the latest' do
          expect(readiness.mcp_server_names).to eq(%w[Atlassian linear Sentry])
        end
      end

      context 'when a pinned version no longer resolves' do
        before do
          orphan_server = create(:ai_catalog_mcp_server, organization: organization, name: 'Orphan')
          consumer = create_pinned_agent([orphan_server.id], [orphan_server.id])
          consumer.update_column(:pinned_version_prefix, 'gone')
        end

        it 'skips that consumer' do
          expect(readiness.mcp_server_names).to eq(%w[Atlassian linear])
        end
      end

      context 'when a used server is blocked for the hierarchy' do
        before do
          create(:ai_catalog_mcp_server_block,
            namespace: mcp_group, mcp_server: server, organization: organization)
        end

        it 'does not list the blocked server' do
          expect(readiness.mcp_server_names).to eq(%w[Atlassian])
        end

        context 'when the mcp_server_block_enforcement feature flag is disabled' do
          before do
            stub_feature_flags(mcp_server_block_enforcement: false)
          end

          it 'lists the blocked server' do
            expect(readiness.mcp_server_names).to eq(%w[Atlassian linear])
          end
        end
      end
    end

    describe '#mcp_server_names' do
      it 'is empty when no configured agent uses an MCP server' do
        expect(readiness.mcp_server_names).to eq([])
      end
    end

    context 'when an agent using an MCP server is inherited from the top-level group' do
      let_it_be(:server) { create(:ai_catalog_mcp_server, organization: organization) }

      before_all do
        agent = create(:ai_catalog_agent, :public, organization: organization)
        create(:ai_catalog_agent_version, item: agent, definition: {
          'system_prompt' => 'Test prompt',
          'tools' => [],
          'user_prompt' => '',
          'mcp_servers' => [server.id]
        })
        create(:ai_catalog_item_consumer, :inheritance, group: mcp_group, item: agent, service_account: nil)

        mcp_group.namespace_settings.update!(duo_custom_agents_enabled: true)
      end

      it 'counts the servers of the inherited agent' do
        expect(count).to eq(1)
      end

      context 'when the ai_catalog_group_inherited_consumers feature flag is disabled' do
        before do
          stub_feature_flags(ai_catalog_group_inherited_consumers: false)
        end

        it 'does not count the servers of the inherited agent' do
          expect(count).to eq(0)
        end
      end
    end
  end
end
