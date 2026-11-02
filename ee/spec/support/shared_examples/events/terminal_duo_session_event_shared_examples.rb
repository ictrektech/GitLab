# frozen_string_literal: true

RSpec.shared_examples 'a terminal Duo session cloud event' do
  describe '.build' do
    let_it_be(:project) { create(:project) }

    let(:messaging_callback_context) { { 'adapter' => 'slack' } }
    let(:workflow) do
      create(:duo_workflows_workflow, :running,
        project: project,
        workflow_definition: 'chat',
        messaging_callback_context: messaging_callback_context)
    end

    let(:event) { described_class.build(workflow: workflow) }

    it 'sets the cloud event envelope' do
      expect(event.data[:type]).to eq(expected_type)
      expect(event.data[:source]).to eq("ai/duo_workflows/workflows/#{workflow.id}")
      expect(event.data[:subject]).to eq("ai/duo_workflows/workflows/#{workflow.id}")
    end

    it 'carries what the subscriptions filter on' do
      expect(event.event_data).to eq(
        workflow_id: workflow.id,
        workflow_definition: 'chat',
        adapter: 'slack'
      )
    end

    it 'builds without querying' do
      reloaded = ::Ai::DuoWorkflows::Workflow.find(workflow.id)

      expect { described_class.build(workflow: reloaded) }.not_to exceed_query_limit(0)
    end

    context 'when no surface is waiting on the session' do
      let(:messaging_callback_context) { nil }

      it 'reports a nil adapter, which keeps the messaging subscriptions unenqueued' do
        expect(event.event_data[:adapter]).to be_nil
      end
    end

    # A payload is stored as Sidekiq job arguments, so it is JSON by the time the
    # node that runs the job rebuilds it. That node may be on another release.
    it 'rebuilds from the JSON Sidekiq stores' do
      args = ::Gitlab::Json::SafeParser.parse(::Gitlab::Json.dump(event.data))

      expect { described_class.new(data: args) }.not_to raise_error
      expect(described_class.new(data: args).event_data).to eq(event.event_data)
    end
  end
end
