# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggers::CallerContext, feature_category: :dap_triggers do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:human) { create(:user) }
  let_it_be(:service_account) { create(:user, :service_account) }
  let_it_be(:root) { create(:duo_workflows_workflow, project: project, user: human) }

  subject(:caller_context) { described_class.new(parent_workflow: parent) }

  def create_child(parent, trigger_source: :flow)
    create(:duo_workflows_workflow, project: project, user: service_account, trigger_source: trigger_source,
      parent_workflow: parent)
  end

  # Returns the workflows of a linear chain, root first.
  def create_chain(length)
    (length - 1).times.reduce([root]) { |chain, _| chain << create_child(chain.last) }
  end

  describe '.authorized_parent_workflow' do
    subject(:parent) { described_class.authorized_parent_workflow(workflow_id, human) }

    let(:workflow_id) { root.id.to_s }

    context 'when the user may update the workflow' do
      before do
        allow(human).to receive(:can?).with(:update_duo_workflow, root).and_return(true)
      end

      it { is_expected.to eq(root) }

      context 'without a user' do
        subject(:parent) { described_class.authorized_parent_workflow(workflow_id, nil) }

        it { is_expected.to be_nil }
      end
    end

    context 'when the user may not update the workflow' do
      before do
        allow(human).to receive(:can?).with(:update_duo_workflow, root).and_return(false)
      end

      it { is_expected.to be_nil }
    end

    context 'when the workflow does not exist' do
      let(:workflow_id) { non_existing_record_id.to_s }

      it { is_expected.to be_nil }
    end

    context 'without a workflow id' do
      let(:workflow_id) { nil }

      it { is_expected.to be_nil }
    end
  end

  describe '.authorized_parent_workflow_for_request' do
    it 'authorizes the workflow from the request header' do
      expect(described_class).to receive(:authorized_parent_workflow).with(root.id.to_s, human).and_return(root)

      parent = ::Gitlab::ApplicationContext.with_context(duo_workflow_id: root.id.to_s) do
        described_class.authorized_parent_workflow_for_request(human)
      end

      expect(parent).to eq(root)
    end
  end

  describe '#depth and #depth_exceeded?' do
    using RSpec::Parameterized::TableSyntax

    # A chain of length n is the parent and its ancestors, so the new child has depth n.
    where(:chain_length, :exceeded) do
      1 | false
      2 | false
      3 | true
      4 | true
    end

    with_them do
      let(:parent) { create_chain(chain_length).last }

      before do
        stub_const("#{described_class}::MAX_TRIGGER_DEPTH", 3)
      end

      it 'counts the parent and its ancestors', :aggregate_failures do
        expect(caller_context.depth).to eq(chain_length)
        expect(caller_context.depth_exceeded?).to eq(exceeded)
      end
    end

    context 'when the chain is longer than the walk' do
      let(:parent) { create_chain(described_class::MAX_TRIGGER_DEPTH + 3).last.reload }

      it 'stops walking and reports the depth as exceeded', :aggregate_failures do
        context = caller_context
        recorder = ActiveRecord::QueryRecorder.new { context.depth }

        expect(context.depth_exceeded?).to be(true)
        expect(recorder.count).to eq(described_class::MAX_TRIGGER_DEPTH + 1)
      end
    end

    context 'when the root is a verification run' do
      let(:parent) do
        create(:duo_workflows_workflow, project: project, user: human, trigger_source: :verification)
      end

      it 'does not count it' do
        expect(caller_context.depth).to eq(0)
      end
    end
  end

  describe '#breadth_exceeded?' do
    let_it_be(:parent) { create(:duo_workflows_workflow, project: project, user: human) }

    before do
      stub_const("#{described_class}::MAX_CHILD_WORKFLOWS_PER_PARENT", 2)
    end

    it 'is false below the limit' do
      create_child(parent)

      expect(caller_context.breadth_exceeded?).to be(false)
    end

    it 'counts children in any status' do
      create(:duo_workflows_workflow, :failed, project: project, user: service_account, trigger_source: :flow,
        parent_workflow: parent)
      create(:duo_workflows_workflow, :stopped, project: project, user: service_account, trigger_source: :flow,
        parent_workflow: parent)

      expect(caller_context.breadth_exceeded?).to be(true)
    end
  end

  describe '#chain_size_exceeded?' do
    let_it_be(:other_root) { create(:duo_workflows_workflow, project: project, user: human) }

    let(:parent) { create_child(root) }

    before do
      stub_const("#{described_class}::MAX_DESCENDANT_WORKFLOWS_PER_ROOT", 3)
      create_child(other_root)
    end

    it 'is false below the limit' do
      create_child(root)

      expect(caller_context.chain_size_exceeded?).to be(false)
    end

    it 'counts descendants of the root in any status and at any depth' do
      create(:duo_workflows_workflow, :failed, project: project, user: service_account, trigger_source: :flow,
        parent_workflow: root)
      create_child(parent)

      expect(caller_context.chain_size_exceeded?).to be(true)
    end

    it 'counts in a single query' do
      context = caller_context.tap(&:root_workflow)

      expect { context.chain_size_exceeded? }.to match_query_count(1)
    end
  end

  describe '#root_workflow' do
    context 'when the chain fits in the walk' do
      let(:parent) { create_chain(3).last }

      it { expect(caller_context.root_workflow).to eq(root) }
    end

    context 'when the chain is longer than the walk' do
      let(:parent) { create_chain(described_class::MAX_TRIGGER_DEPTH + 3).last }

      it { expect(caller_context.root_workflow).to be_nil }
    end
  end

  describe '#root_human' do
    context 'when the root was triggered by a human' do
      let(:parent) { create_chain(2).last }

      it { expect(caller_context.root_human).to eq(human) }
    end

    context 'when the root was triggered autonomously' do
      using RSpec::Parameterized::TableSyntax

      where(:trigger_source) { %i[system scheduled] }

      with_them do
        let(:parent) do
          create(:duo_workflows_workflow, project: project, user: service_account, trigger_source: trigger_source)
        end

        it { expect(caller_context.root_human).to be_nil }
      end
    end

    context 'when the root user is not human' do
      let(:parent) { create(:duo_workflows_workflow, project: project, user: service_account) }

      it { expect(caller_context.root_human).to be_nil }
    end

    context 'when the chain is longer than the walk' do
      let(:parent) { create_chain(described_class::MAX_TRIGGER_DEPTH + 3).last }

      it { expect(caller_context.root_human).to be_nil }
    end

    context 'when the parent of a flow-triggered workflow was deleted' do
      let(:parent) do
        deleted_parent = create(:duo_workflows_workflow, project: project, user: human)
        child = create(:duo_workflows_workflow, project: project, user: human, trigger_source: :flow,
          parent_workflow: deleted_parent)
        deleted_parent.delete

        child.reload
      end

      it 'counts the orphan as the root but does not resolve a human', :aggregate_failures do
        expect(caller_context.depth).to eq(1)
        expect(caller_context.root_human).to be_nil
      end
    end
  end

  describe '#same_root_namespace?' do
    let(:parent) { root }

    it 'is true for a container in the same top-level namespace', :aggregate_failures do
      expect(caller_context.same_root_namespace?(create(:project, group: create(:group, parent: group))))
        .to be(true)
      expect(caller_context.same_root_namespace?(group)).to be(true)
    end

    it 'is false for a container in another top-level namespace' do
      expect(caller_context.same_root_namespace?(create(:project))).to be(false)
    end

    it 'is false without a container' do
      expect(caller_context.same_root_namespace?(nil)).to be(false)
    end
  end
end
