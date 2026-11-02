# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../spec/support/shared_examples/events/cloud_event_with_schema_shared_examples'

RSpec.describe Ai::DuoWorkflows::WorkflowFailedEvent, feature_category: :duo_agent_platform do
  it_behaves_like 'a cloud event with schema',
    valid_data: { workflow_id: 1, workflow_definition: 'chat', adapter: 'slack' },
    missing_required: %i[workflow_id],
    invalid_types: { workflow_id: 'not_an_integer', workflow_definition: 1, adapter: 1 }

  it_behaves_like 'a terminal Duo session cloud event' do
    let(:expected_type) { 'com.gitlab.duo_agent_platform.workflow_failed' }
  end

  describe '.build with status_event' do
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, :running, messaging_callback_context: { 'adapter' => 'slack' })
    end

    it 'carries the single-event payload 19.5 publishes' do
      event = described_class.build(workflow: workflow, status_event: :stop)

      expect(event.event_data).to eq(workflow_id: workflow.id, status_event: 'stop')
    end

    it 'accepts a drop too' do
      event = described_class.build(workflow: workflow, status_event: :drop)

      expect(event.event_data[:status_event]).to eq('drop')
    end
  end

  # A payload is stored as Sidekiq job arguments, so a job queued on one release can
  # run on another. 19.5 publishes the single-event payload and 19.6 publishes the
  # split one, so this schema has to accept both. 19.4's schema is written out rather
  # than read from the code, so these fail if 19.5 drifts from what 19.4 accepts.
  describe 'payload compatibility across releases' do
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, :running, messaging_callback_context: { 'adapter' => 'slack' })
    end

    let(:schema_19_4) do
      {
        'type' => 'object',
        'required' => %w[workflow_id status_event],
        'properties' => {
          'workflow_id' => { 'type' => 'integer' },
          'status_event' => { 'type' => 'string', 'enum' => %w[drop stop] }
        },
        'additionalProperties' => false
      }
    end

    def valid_against?(schema, event)
      JSONSchemer.schema(schema).valid?(event.event_data.deep_stringify_keys)
    end

    %i[drop stop].each do |status_event|
      it "accepts the #{status_event} payload 19.4 queues" do
        expect { described_class.build(workflow: workflow, status_event: status_event) }.not_to raise_error
      end

      it "publishes a #{status_event} that 19.4 still accepts" do
        event = described_class.build(workflow: workflow, status_event: status_event)

        expect(valid_against?(schema_19_4, event)).to be(true)
      end
    end

    it 'accepts the split payload 19.6 will queue' do
      expect { described_class.build(workflow: workflow) }.not_to raise_error
    end

    # Why 19.6 cannot publish this until every node runs 19.5: 19.4 sets
    # additionalProperties false, so it rejects the two new keys.
    it 'builds a 19.6 payload that 19.4 cannot read' do
      event = described_class.build(workflow: workflow)

      expect(valid_against?(schema_19_4, event)).to be(false)
    end
  end
end
