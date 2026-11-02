# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::Flows::ReferenceResolver, feature_category: :ai_catalog_curation do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:group) { create(:group) }
  let_it_be(:flow_project) { create(:project, group: group) }
  let_it_be(:user) { create(:user, developer_of: flow_project) }

  let_it_be(:agent) do
    create(:ai_catalog_agent, :public, project: flow_project).tap do |item|
      create(:ai_catalog_agent_version, :released, item: item, version: '1.0.0')
    end
  end

  let(:agent_version) { agent.versions.find_by(version: '1.0.0') }

  let(:include_entries) do
    [{ 'source' => 'ai-catalog', 'item_type' => 'agent', 'item_id' => agent.id.to_s, 'version' => '1.0.0' }]
  end

  let(:definition) { { 'version' => 'v1', 'include' => include_entries } }
  let(:flow_visibility) { :private }

  subject(:resolution) do
    described_class.new(
      user: user, flow_project: flow_project, definition: definition, flow_visibility: flow_visibility
    ).execute
  end

  before do
    allow(Ability).to receive(:allowed?).and_call_original
    allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, agent).and_return(true)
  end

  describe '#execute' do
    it 'resolves the referenced agent to its pinned version' do
      expect(resolution).to be_success
      expect(resolution.payload[:agents].size).to eq(1)
      expect(resolution.payload[:agents].first.item).to eq(agent)
      expect(resolution.payload[:agents].first.version).to eq(agent_version)
    end

    it 'builds the payload the run sends for each agent' do
      expect(resolution.payload[:run_payload]).to contain_exactly(
        a_hash_including(
          item_id: agent.id.to_s,
          version: '1.0.0',
          name: agent.name,
          description: agent.description
        )
      )
    end

    context 'when the serialized payload exceeds the size limit' do
      before do
        allow(Ai::Catalog::Flows::ReferenceLimits)
          .to receive(:payload_size_exceeded?).and_return(true)
      end

      it 'fails without returning a payload' do
        expect(resolution).to be_error
        expect(resolution.message.first).to include('maximum payload size')
        expect(resolution.payload).to be_empty
      end
    end

    context 'when the definition has no include entries' do
      let(:definition) { { 'version' => 'v1' } }

      it 'resolves to an empty set' do
        expect(resolution).to be_success
        expect(resolution.payload[:agents]).to be_empty
      end
    end

    context 'when the definition is not a hash' do
      let(:definition) { [] }

      it 'resolves to an empty set' do
        expect(resolution).to be_success
        expect(resolution.payload[:agents]).to be_empty
      end
    end

    context 'when the item does not exist' do
      let(:include_entries) do
        [{ 'source' => 'ai-catalog', 'item_type' => 'agent', 'item_id' => '0', 'version' => '1.0.0' }]
      end

      it 'fails naming the reference' do
        expect(resolution).to be_error
        expect(resolution.message.first).to include("Agent '0' (version 1.0.0) was not found")
      end
    end

    context 'when the user cannot read the item' do
      before do
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, agent).and_return(false)
      end

      it 'fails with the same message as a missing item' do
        expect(resolution).to be_error
        expect(resolution.message.first).to include('was not found or you do not have access')
      end
    end

    context 'when the referenced item is a flow, not an agent' do
      let_it_be(:flow_item) { create(:ai_catalog_flow, :public, project: flow_project) }

      let(:include_entries) do
        [{ 'source' => 'ai-catalog', 'item_type' => 'agent', 'item_id' => flow_item.id.to_s, 'version' => '1.0.0' }]
      end

      it 'fails as an unknown reference' do
        expect(resolution).to be_error
        expect(resolution.message.first).to include("Agent '#{flow_item.id}'")
      end
    end

    context 'when the item is soft-deleted' do
      let_it_be(:deleted_agent) do
        create(:ai_catalog_agent, :public, :soft_deleted, project: flow_project).tap do |item|
          create(:ai_catalog_agent_version, :released, item: item, version: '1.0.0')
        end
      end

      let(:include_entries) do
        [{ 'source' => 'ai-catalog', 'item_type' => 'agent', 'item_id' => deleted_agent.id.to_s,
           'version' => '1.0.0' }]
      end

      before do
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, deleted_agent).and_return(true)
      end

      it 'fails as an unknown reference' do
        expect(resolution).to be_error
        expect(resolution.message.first).to include("Agent '#{deleted_agent.id}'")
      end
    end

    context 'when the version does not exist' do
      let(:include_entries) do
        [{ 'source' => 'ai-catalog', 'item_type' => 'agent', 'item_id' => agent.id.to_s, 'version' => '9.9.9' }]
      end

      it 'fails naming the item and version' do
        expect(resolution).to be_error
        expect(resolution.message.first).to include(agent.name)
        expect(resolution.message.first).to include('9.9.9')
      end
    end

    context 'when the pinned version is a draft' do
      let_it_be(:draft_agent) do
        create(:ai_catalog_agent, :public, project: flow_project).tap do |item|
          create(:ai_catalog_agent_version, :draft, item: item, version: '1.0.0')
        end
      end

      let(:include_entries) do
        [{ 'source' => 'ai-catalog', 'item_type' => 'agent', 'item_id' => draft_agent.id.to_s, 'version' => '1.0.0' }]
      end

      before do
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, draft_agent).and_return(true)
      end

      it 'fails naming the item and version' do
        expect(resolution).to be_error
        expect(resolution.message.first).to include("Agent '#{draft_agent.name}' has no version 1.0.0")
      end
    end

    context 'when the flow group confines the AI Catalog to its hierarchy' do
      let_it_be(:outside_agent) do
        create(:ai_catalog_agent, :public, project: create(:project)).tap do |item|
          create(:ai_catalog_agent_version, :released, item: item, version: '1.0.0')
        end
      end

      let(:include_entries) do
        [{ 'source' => 'ai-catalog', 'item_type' => 'agent', 'item_id' => outside_agent.id.to_s,
           'version' => '1.0.0' }]
      end

      before do
        group.ai_settings.update!(ai_catalog_restricted_to_group_hierarchy: true)
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, outside_agent).and_return(true)
      end

      it 'refuses a public agent from outside the hierarchy' do
        expect(resolution).to be_error
        expect(resolution.message.first).to include('not visible to flows in this project')
      end

      context 'when the agent lives inside the hierarchy' do
        let(:include_entries) do
          [{ 'source' => 'ai-catalog', 'item_type' => 'agent', 'item_id' => agent.id.to_s, 'version' => '1.0.0' }]
        end

        it 'resolves' do
          expect(resolution).to be_success
        end
      end
    end

    context 'with a private item' do
      let_it_be(:other_project) { create(:project, group: group) }
      let_it_be(:private_agent) do
        create(:ai_catalog_agent, :private, project: other_project).tap do |item|
          create(:ai_catalog_agent_version, :released, item: item, version: '1.0.0')
        end
      end

      let(:include_entries) do
        [{ 'source' => 'ai-catalog', 'item_type' => 'agent', 'item_id' => private_agent.id.to_s,
           'version' => '1.0.0' }]
      end

      before do
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, private_agent).and_return(true)
      end

      it 'refuses a reference from another project' do
        expect(resolution).to be_error
        expect(resolution.message.first).to include('not visible to flows in this project')
      end

      context 'when the flow lives in the same project' do
        let_it_be(:same_project_flow) { other_project }

        subject(:resolution) do
          described_class.new(
            user: user, flow_project: other_project, definition: definition, flow_visibility: flow_visibility
          ).execute
        end

        it 'resolves' do
          expect(resolution).to be_success
        end
      end
    end

    context 'with a restricted item' do
      let_it_be(:sibling_project) { create(:project, group: group) }
      let_it_be(:outside_project) { create(:project) }
      let_it_be(:restricted_agent) do
        create(:ai_catalog_agent, :restricted, project: sibling_project).tap do |item|
          create(:ai_catalog_agent_version, :released, item: item, version: '1.0.0')
        end
      end

      let(:include_entries) do
        [{ 'source' => 'ai-catalog', 'item_type' => 'agent', 'item_id' => restricted_agent.id.to_s,
           'version' => '1.0.0' }]
      end

      before do
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, restricted_agent).and_return(true)
      end

      it 'resolves from a flow in the same root group' do
        expect(resolution).to be_success
      end

      it 'refuses a reference from outside the root group' do
        outside = described_class.new(
          user: user, flow_project: outside_project, definition: definition, flow_visibility: flow_visibility
        ).execute

        expect(outside).to be_error
        expect(outside.message.first).to include('not visible to flows in this project')
      end
    end

    context 'when the agent is less visible than the flow' do
      let_it_be(:private_agent) do
        create(:ai_catalog_agent, :private, project: flow_project).tap do |item|
          create(:ai_catalog_agent_version, :released, item: item, version: '1.0.0')
        end
      end

      let_it_be(:restricted_agent) do
        create(:ai_catalog_agent, :restricted, project: flow_project).tap do |item|
          create(:ai_catalog_agent_version, :released, item: item, version: '1.0.0')
        end
      end

      let(:referenced_agent) { private_agent }
      let(:include_entries) do
        [{ 'source' => 'ai-catalog', 'item_type' => 'agent', 'item_id' => referenced_agent.id.to_s,
           'version' => '1.0.0' }]
      end

      before do
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, referenced_agent).and_return(true)
      end

      where(:flow_visibility, :agent_visibility, :allowed) do
        :public     | :private    | false
        :public     | :restricted | false
        :public     | :public     | true
        :restricted | :private    | false
        :restricted | :restricted | true
        :restricted | :public     | true
        :private    | :private    | true
        :private    | :restricted | true
        :private    | :public     | true
      end

      with_them do
        let(:referenced_agent) do
          { private: private_agent, restricted: restricted_agent, public: agent }.fetch(agent_visibility)
        end

        it 'allows only agents at least as visible as the flow' do
          if allowed
            expect(resolution).to be_success
          else
            expect(resolution).to be_error
            expect(resolution.message.first).to include(
              "Agent '#{referenced_agent.name}' must be at least as visible as the flow that references it"
            )
          end
        end
      end
    end

    context 'when the flow references several agents' do
      let_it_be(:sibling_project) { create(:project, group: group) }
      let_it_be(:other_agents) do
        [
          create(:ai_catalog_agent, :public, project: flow_project),
          create(:ai_catalog_agent, :restricted, project: sibling_project)
        ].each do |item|
          create(:ai_catalog_agent_version, :released, item: item, version: '1.0.0')
        end
      end

      let(:include_entries) do
        [agent, *other_agents].map do |item|
          { 'source' => 'ai-catalog', 'item_type' => 'agent', 'item_id' => item.id.to_s, 'version' => '1.0.0' }
        end
      end

      before do
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_item, anything).and_return(true)
      end

      it 'does not query more as the number of agents grows' do
        control = ActiveRecord::QueryRecorder.new do
          described_class.new(
            user: user,
            flow_project: flow_project,
            definition: { 'version' => 'v1', 'include' => include_entries.first(1) },
            flow_visibility: flow_visibility
          ).execute
        end

        expect { resolution }.not_to exceed_query_limit(control)
        expect(resolution.payload[:agents].map(&:item)).to eq([agent, *other_agents])
      end
    end

    context 'when the same item is referenced twice' do
      let(:include_entries) do
        [
          { 'source' => 'ai-catalog', 'item_type' => 'agent', 'item_id' => agent.id.to_s, 'version' => '1.0.0' },
          { 'source' => 'ai-catalog', 'item_type' => 'agent', 'item_id' => agent.id.to_s, 'version' => '1.0.0' }
        ]
      end

      it 'fails naming the duplicated id' do
        expect(resolution).to be_error
        expect(resolution.message.first).to include(agent.id.to_s)
      end
    end

    context 'when the reference count exceeds the limit' do
      let(:include_entries) do
        Array.new(Ai::Catalog::Flows::ReferenceLimits.limit_for(:agent) + 1) do |i|
          { 'source' => 'ai-catalog', 'item_type' => 'agent', 'item_id' => (i + 1).to_s, 'version' => '1.0.0' }
        end
      end

      it 'fails without resolving any entry' do
        expect(resolution).to be_error
        expect(resolution.message.first).to include("exceeds the limit of #{Ai::Catalog::Flows::ReferenceLimits.limit_for(:agent)}")
        expect(resolution.payload).to be_empty
      end
    end
  end
end
