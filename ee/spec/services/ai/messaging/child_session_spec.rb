# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Messaging::ChildSession, :clean_gitlab_redis_shared_state, feature_category: :duo_agent_platform do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }

  let(:surface_context) do
    { 'adapter' => 'slack', 'team_id' => 'T1', 'channel_id' => 'C1', 'thread_ts' => '1.0', 'message_ts' => '1.0',
      'user_id' => 'U1' }
  end

  let(:parent_context) { surface_context.merge('status_ts' => '2.0', 'delivered_at' => '2026-10-13T00:00:00Z') }
  let(:parent) do
    create(:duo_workflows_workflow, user: user, project: project, messaging_callback_context: parent_context)
  end

  let(:child) do
    create(:duo_workflows_workflow, user: user, project: project, trigger_source: :flow,
      parent_workflow: parent)
  end

  let(:adapter) { instance_double(Ai::Messaging::Adapters::Slack) }

  before do
    allow(Ai::Messaging::Adapters::Slack).to receive(:from_callback_context).and_call_original
  end

  shared_examples "a session not shown on its parent's surface" do
    context 'when the session has no parent' do
      let(:child) { create(:duo_workflows_workflow, user: user, project: project) }

      it { is_expected.to eq(absent) }
    end

    context 'when the session runs as another user' do
      let(:child) do
        create(:duo_workflows_workflow, user: create(:user, developer_of: project), project: project,
          trigger_source: :flow, parent_workflow: parent)
      end

      it { is_expected.to eq(absent) }
    end

    context 'when the parent has no messaging surface' do
      let(:parent_context) { nil }

      it { is_expected.to eq(absent) }
    end

    context "when the parent's surface does not show delegated sessions" do
      let(:parent_context) { { 'adapter' => 'webhook', 'hook_id' => 1 } }

      it { is_expected.to eq(absent) }
    end

    context "when the parent's adapter is unknown" do
      let(:parent_context) { { 'adapter' => 'unknown' } }

      it { is_expected.to eq(absent) }
    end

    context 'when the session has a surface of its own' do
      let(:child) do
        create(:duo_workflows_workflow, user: user, project: project, trigger_source: :flow,
          parent_workflow: parent, messaging_callback_context: surface_context)
      end

      it { is_expected.to eq(absent) }
    end
  end

  describe '.from_workflow' do
    subject(:session) { described_class.from_workflow(child) }

    let(:absent) { nil }

    it 'resolves the parent surface' do
      expect(session.child).to eq(child)
      expect(Ai::Messaging::Adapters::Slack).to have_received(:from_callback_context).with(parent_context)
    end

    it_behaves_like "a session not shown on its parent's surface"
  end

  describe '.relayed?' do
    subject(:relayed) { described_class.relayed?(child) }

    let(:absent) { false }

    it 'is true without building the adapter', :aggregate_failures do
      expect(relayed).to be(true)
      expect(Ai::Messaging::Adapters::Slack).not_to have_received(:from_callback_context)
    end

    it_behaves_like "a session not shown on its parent's surface"
  end

  describe 'delivery to the surface' do
    subject(:session) { described_class.from_workflow(child) }

    before do
      allow(Ai::Messaging::Adapters::Slack).to receive(:from_callback_context).and_return(adapter)
    end

    it "renders the card with the parent's context, without its session state" do
      expect(adapter).to receive(:render_child_card).with(callback_context: surface_context, child: child)
        .and_return(true)

      expect(session.render_card).to be(true)
    end

    it "delivers the outcome with the parent's context, without its session state" do
      expect(adapter).to receive(:deliver_child_result)
        .with(callback_context: surface_context, child: child, message: 'Done', error: nil).and_return(true)

      expect(session.deliver_result(message: 'Done', error: nil)).to be(true)
    end
  end

  describe 'result delivery claim' do
    subject(:session) { described_class.from_workflow(child) }

    it 'is won once until released', :aggregate_failures do
      expect(session.claim_result_delivery(nil)).to be(true)
      expect(described_class.from_workflow(child).claim_result_delivery(nil)).to be(false)

      session.release_result_delivery!(nil)

      expect(session.claim_result_delivery(nil)).to be(true)
    end

    it 'is held per kind of ending, so a retried session still reports how it ended', :aggregate_failures do
      expect(session.claim_result_delivery(:flow_failed)).to be(true)
      expect(session.claim_result_delivery(nil)).to be(true)
      expect(session.claim_result_delivery(:flow_failed)).to be(false)
    end

    it 'expires' do
      session.claim_result_delivery(nil)

      ttl = Gitlab::Redis::SharedState.with { |redis| redis.ttl("ai:messaging:child_session:#{child.id}:delivered:finished") }
      expect(ttl).to be_within(5).of(described_class::DELIVERY_CLAIM_TTL.to_i)
    end
  end
end
