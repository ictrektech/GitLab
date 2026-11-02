# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Messaging::ChildSessionCardWorker, :clean_gitlab_redis_shared_state, feature_category: :duo_agent_platform do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:parent) do
    create(:duo_workflows_workflow, user: user, project: project,
      messaging_callback_context: { 'adapter' => 'slack', 'team_id' => 'T1', 'channel_id' => 'C1' })
  end

  let(:child) do
    create(:duo_workflows_workflow, user: user, project: project, trigger_source: :flow,
      parent_workflow: parent)
  end

  let(:adapter) { instance_double(Ai::Messaging::Adapters::Slack, render_child_card: true) }

  subject(:perform) { described_class.new.perform(child.id) }

  before do
    allow(Ai::Messaging::Adapters::Slack).to receive(:from_callback_context).and_return(adapter)
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [child.id] }
  end

  it "renders the delegated session's card on the parent's surface" do
    perform

    expect(adapter).to have_received(:render_child_card).with(callback_context: a_hash_including('channel_id' => 'C1'),
      child: child)
  end

  context 'when the session no longer exists' do
    subject(:perform) { described_class.new.perform(non_existing_record_id) }

    it 'does nothing' do
      perform

      expect(adapter).not_to have_received(:render_child_card)
    end
  end

  context 'when the session has already ended' do
    let(:child) do
      create(:duo_workflows_workflow, :finished, user: user, project: project, trigger_source: :flow,
        parent_workflow: parent)
    end

    it 'leaves the card to the outcome' do
      perform

      expect(adapter).not_to have_received(:render_child_card)
    end
  end

  context "when the parent's surface does not show delegated sessions" do
    let(:child) { create(:duo_workflows_workflow, user: user, project: project) }

    it 'does nothing' do
      perform

      expect(adapter).not_to have_received(:render_child_card)
    end
  end
end
