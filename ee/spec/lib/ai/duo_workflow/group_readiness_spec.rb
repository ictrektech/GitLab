# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflow::GroupReadiness, feature_category: :duo_agent_platform do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: subgroup) }
  let_it_be(:user) { create(:user, owner_of: group) }

  let(:workload_tag) { ::Ai::DuoWorkflows::Workflow.workload_tag_for(subgroup) }
  let(:readiness) { described_class.new(subgroup, user) }

  def create_docker_runner(*traits, **attributes)
    runner = create(:ci_runner, *traits, :online, tag_list: [workload_tag], **attributes)
    create(:ci_runner_machine, runner: runner, executor_type: :docker)
    runner
  end

  describe '#runner_available?' do
    subject { readiness.runner_available? }

    it 'is false when no runner carries the workload tag' do
      runner = create(:ci_runner, :instance, :online)
      create(:ci_runner_machine, runner: runner, executor_type: :docker)

      is_expected.to be(false)
    end

    it 'is true with an online, Duo-tagged instance runner on a Docker executor' do
      create_docker_runner(:instance)

      is_expected.to be(true)
    end

    it 'is true with a runner of the top-level group, seen from a subgroup' do
      create_docker_runner(:group, groups: [group])

      is_expected.to be(true)
    end

    it 'is false when the only tagged runner has stopped checking in' do
      runner = create(:ci_runner, :instance, tag_list: [workload_tag], contacted_at: 1.day.ago)
      create(:ci_runner_machine, runner: runner, executor_type: :docker)

      is_expected.to be(false)
    end

    it 'is false when the runner has no Docker-compatible executor' do
      runner = create(:ci_runner, :instance, :online, tag_list: [workload_tag])
      create(:ci_runner_machine, runner: runner, executor_type: :shell)

      is_expected.to be(false)
    end

    context 'when duo_runner_restrictions is on' do
      it "ignores the subgroup's own runner" do
        create_docker_runner(:group, groups: [subgroup])

        is_expected.to be(false)
      end

      it 'ignores a project runner below the group' do
        create_docker_runner(:project, projects: [project])

        is_expected.to be(false)
      end
    end

    context 'when the group has shared runners disabled' do
      let_it_be(:no_shared_group) { create(:group, shared_runners_enabled: false) }

      let(:readiness) { described_class.new(no_shared_group, user) }

      it 'ignores instance runners' do
        create_docker_runner(:instance)

        is_expected.to be(false)
      end

      it "still accepts the group's own runner" do
        create_docker_runner(:group, groups: [no_shared_group])

        is_expected.to be(true)
      end
    end

    context 'when duo_runner_restrictions is disabled' do
      before do
        stub_feature_flags(duo_runner_restrictions: false)
      end

      it "accepts the subgroup's own runner" do
        create_docker_runner(:group, groups: [subgroup])

        is_expected.to be(true)
      end
    end

    it 'looks the runner up once, however many readers ask' do
      create_docker_runner(:instance)

      expect(::Ci::Runner).to receive(:from_union).once.and_call_original

      readiness.runner_available?
      readiness.usable_runner_type
    end

    describe 'the candidate window' do
      it 'is not crowded out by descendant runners that can never qualify' do
        stub_const("#{described_class}::RUNNER_CANDIDATE_LIMIT", 1)

        create_docker_runner(:group, groups: [group])
        create_docker_runner(:group, groups: [subgroup])

        expect(readiness.runner_available?).to be(true)
      end

      it 'misses a usable runner older than everything in the window' do
        stub_const("#{described_class}::RUNNER_CANDIDATE_LIMIT", 1)

        create_docker_runner(:instance)
        newer = create(:ci_runner, :instance, :online, tag_list: [workload_tag])
        create(:ci_runner_machine, runner: newer, executor_type: :shell)

        expect(readiness.runner_available?).to be(false)
      end

      it 'finds the usable runner inside the window' do
        stub_const("#{described_class}::RUNNER_CANDIDATE_LIMIT", 2)

        older = create(:ci_runner, :instance, :online, tag_list: [workload_tag])
        create(:ci_runner_machine, runner: older, executor_type: :shell)
        create_docker_runner(:instance)

        expect(readiness.runner_available?).to be(true)
      end
    end
  end

  describe '#mcp_server_names' do
    let_it_be(:mcp_group, freeze: false) { create(:group) }
    let_it_be(:organization) { mcp_group.organization }

    let(:user) { create(:user, owner_of: mcp_group, organizations: [organization]) }
    let(:readiness) { described_class.new(mcp_group, user) }

    before do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?)
        .with(user, :read_ai_catalog_item_consumer, mcp_group).and_return(true)
      allow(::Ai::Catalog).to receive(:mcp_servers_available?).with(user).and_return(true)
    end

    it 'is empty when no configured agent uses an MCP server' do
      expect(readiness.mcp_server_names).to eq([])
    end

    context 'when configured agents use MCP servers' do
      let_it_be(:server) { create(:ai_catalog_mcp_server, organization: organization, name: 'linear') }
      let_it_be(:shared_server) { create(:ai_catalog_mcp_server, organization: organization, name: 'Atlassian') }

      before_all do
        create(:ai_catalog_mcp_server, organization: organization, name: 'Unused')

        [[server.id, shared_server.id], [shared_server.id]].each do |server_ids|
          agent = create(:ai_catalog_agent, organization: organization)
          create(:ai_catalog_agent_version, item: agent, definition: {
            'system_prompt' => 'Test prompt',
            'tools' => [],
            'user_prompt' => '',
            'mcp_servers' => server_ids
          })
          create(:ai_catalog_item_consumer, group: mcp_group, item: agent)
        end

        mcp_group.namespace_settings.update!(duo_custom_agents_enabled: true)
      end

      it 'lists each server of the configured agents once, sorted case-insensitively' do
        expect(readiness.mcp_server_names).to eq(%w[Atlassian linear])
      end

      it 'lists a name shared by several servers once' do
        duplicate = create(:ai_catalog_mcp_server, organization: organization, name: 'linear')
        agent = create(:ai_catalog_agent, organization: organization)
        create(:ai_catalog_agent_version, item: agent, definition: {
          'system_prompt' => 'Test prompt',
          'tools' => [],
          'user_prompt' => '',
          'mcp_servers' => [duplicate.id]
        })
        create(:ai_catalog_item_consumer, group: mcp_group, item: agent)

        expect(readiness.mcp_server_names).to eq(%w[Atlassian linear])
      end

      it 'lists a name shared across casings once' do
        duplicate = create(:ai_catalog_mcp_server, organization: organization, name: 'Linear')
        agent = create(:ai_catalog_agent, organization: organization)
        create(:ai_catalog_agent_version, item: agent, definition: {
          'system_prompt' => 'Test prompt',
          'tools' => [],
          'user_prompt' => '',
          'mcp_servers' => [duplicate.id]
        })
        create(:ai_catalog_item_consumer, group: mcp_group, item: agent)

        expect(readiness.mcp_server_names).to eq(%w[Atlassian Linear])
      end

      it 'shares its lookup with the count' do
        expect(::Ai::Catalog::ItemConsumersFinder).to receive(:new).once.and_call_original

        readiness.mcp_server_names
        expect(readiness.mcp_servers_count).to eq(2)
      end

      context 'when a configured agent pins an older version' do
        let_it_be(:pinned_server) { create(:ai_catalog_mcp_server, organization: organization, name: 'Sentry') }
        let_it_be(:latest_server) { create(:ai_catalog_mcp_server, organization: organization, name: 'Zendesk') }

        before_all do
          agent = create(:ai_catalog_agent, organization: organization)
          pinned_version = create(:ai_catalog_agent_version, item: agent, definition: {
            'system_prompt' => 'Test prompt',
            'tools' => [],
            'user_prompt' => '',
            'mcp_servers' => [pinned_server.id]
          })
          create(:ai_catalog_agent_version, item: agent, definition: {
            'system_prompt' => 'Test prompt',
            'tools' => [],
            'user_prompt' => '',
            'mcp_servers' => [latest_server.id]
          })
          create(:ai_catalog_item_consumer,
            group: mcp_group, item: agent, pinned_version_prefix: pinned_version.version)
        end

        it 'lists the servers of the pinned version, not of the latest' do
          expect(readiness.mcp_server_names).to eq(%w[Atlassian linear Sentry])
        end
      end

      context 'when a pinned version no longer resolves' do
        before do
          agent = create(:ai_catalog_agent, organization: organization)
          orphan_server = create(:ai_catalog_mcp_server, organization: organization, name: 'Orphan')
          create(:ai_catalog_agent_version, item: agent, definition: {
            'system_prompt' => 'Test prompt',
            'tools' => [],
            'user_prompt' => '',
            'mcp_servers' => [orphan_server.id]
          })
          consumer = create(:ai_catalog_item_consumer, group: mcp_group, item: agent)
          consumer.update_column(:pinned_version_prefix, 'gone')
        end

        it 'skips that consumer' do
          expect(readiness.mcp_server_names).to eq(%w[Atlassian linear])
        end
      end

      context 'when a used server is blocked for the group' do
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
  end

  describe '#usable_runner_type' do
    subject { readiness.usable_runner_type }

    it 'is instance_type for an instance runner' do
      create_docker_runner(:instance)

      is_expected.to eq('instance_type')
    end

    it 'is group_type for a top-level group runner' do
      create_docker_runner(:group, groups: [group])

      is_expected.to eq('group_type')
    end

    it 'is nil when nothing qualifies' do
      is_expected.to be_nil
    end
  end
end
