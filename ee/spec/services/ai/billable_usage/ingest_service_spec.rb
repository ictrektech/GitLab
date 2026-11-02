# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::BillableUsage::IngestService, feature_category: :"self-hosted_models" do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }

  let(:event_id) { SecureRandom.uuid }
  let(:timestamp) { '2026-10-02T10:08:16.196123' }
  let(:metadata) { { 'feature_qualified_name' => 'duo_agent_platform', 'is_gitlab_team_member' => false } }
  let(:billable_usage) do
    {
      'event_id' => event_id,
      'event_type' => 'duo_agent_platform_workflow_completion',
      'unit_of_measure' => 'tokens',
      'quantity' => 5328.0,
      'timestamp' => timestamp,
      'namespace_id' => group.id,
      'root_namespace_id' => group.id,
      'project_id' => project.id,
      'subject' => '42',
      'global_user_id' => 'anonymized-user-id',
      'metadata' => metadata
    }
  end

  let(:contexts_envelope) do
    {
      'schema' => 'iglu:com.snowplowanalytics.snowplow/contexts/jsonschema/1-0-1',
      'data' => [{ 'schema' => 'iglu:com.gitlab/billable_usage/jsonschema/1-0-3', 'data' => billable_usage }]
    }
  end

  let(:event) do
    {
      'e' => 'se',
      'se_ca' => 'DuoWorkflowService',
      'se_ac' => 'duo_agent_platform_workflow_completion',
      'eid' => event_id,
      'aid' => 'gitlab_ai_gateway',
      'tv' => 'py-1.0.0',
      'p' => 'srv',
      'cx' => Base64.urlsafe_encode64(contexts_envelope.to_json)
    }
  end

  let(:events) { [event] }

  subject(:result) { described_class.new(events).execute }

  before do
    allow_next_instance_of(::Gitlab::BillingEvents::Client) do |client|
      allow(client).to receive(:local_persistence_enabled?).and_return(true)
    end
  end

  shared_examples 'returns a not available error' do
    it 'does not forward any event' do
      expect(::Gitlab::BillingEvents::Client).not_to receive(:track_billing_event)

      expect(result).to be_error
      expect(result.message).to eq('Events collector is not available')
    end
  end

  context 'when the BillingEvents local_billing_persistence is disabled' do
    before do
      allow_next_instance_of(::Gitlab::BillingEvents::Client) do |client|
        allow(client).to receive(:local_persistence_enabled?).and_return(false)
      end
    end

    it_behaves_like 'returns a not available error'
  end

  shared_examples 'forwards the billable usage context' do
    it 'calls the billing client with the context fields and no user' do
      expect(::Gitlab::BillingEvents::Client).to receive(:track_billing_event).with(
        event_type: 'duo_agent_platform_workflow_completion',
        category: 'DuoWorkflowService',
        quantity: 5328.0,
        unit_of_measure: 'tokens',
        namespace: group,
        project: project,
        idempotency_key: event_id,
        timestamp: ::ActiveSupport::TimeZone['UTC'].parse(timestamp),
        metadata: metadata
      )

      expect(result).to be_success
      expect(result.payload).to eq(forwarded_events: 1)
    end
  end

  it_behaves_like 'forwards the billable usage context'

  context 'when contexts are sent as plain JSON in co' do
    let(:event) { super().except('cx').merge('co' => contexts_envelope.to_json) }

    it_behaves_like 'forwards the billable usage context'
  end

  context 'when the event has no project' do
    let(:billable_usage) { super().except('project_id') }

    it 'forwards the event without a project' do
      expect(::Gitlab::BillingEvents::Client).to receive(:track_billing_event)
        .with(hash_including(namespace: group, project: nil))

      expect(result).to be_success
    end
  end

  context 'when only root_namespace_id is present' do
    let(:billable_usage) { super().except('namespace_id') }

    it 'resolves the namespace from root_namespace_id' do
      expect(::Gitlab::BillingEvents::Client).to receive(:track_billing_event)
        .with(hash_including(namespace: group))

      expect(result).to be_success
    end
  end

  context 'when the timestamp cannot be parsed' do
    let(:timestamp) { 'not-a-timestamp' }

    it 'forwards the event without a timestamp' do
      expect(::Gitlab::BillingEvents::Client).to receive(:track_billing_event)
        .with(hash_including(timestamp: nil))

      expect(result).to be_success
    end
  end

  context 'when the namespace cannot be found' do
    let(:billable_usage) do
      super().merge('namespace_id' => non_existing_record_id, 'root_namespace_id' => non_existing_record_id)
    end

    it 'skips the event and logs a warning' do
      expect(::Gitlab::BillingEvents::Client).not_to receive(:track_billing_event)
      expect(::Gitlab::AppLogger).to receive(:warn).with(
        hash_including(
          message: 'BillableUsage::IngestService: billing event skipped, namespace not found',
          event_id: event_id
        )
      )

      expect(result).to be_success
      expect(result.payload).to eq(forwarded_events: 0)
    end
  end

  context 'when the event carries no billable usage context' do
    let(:event) { super().except('cx') }

    it 'skips the event' do
      expect(::Gitlab::BillingEvents::Client).not_to receive(:track_billing_event)

      expect(result).to be_success
      expect(result.payload).to eq(forwarded_events: 0)
    end
  end

  context 'when the encoded contexts are not valid' do
    let(:event) { super().merge('cx' => '!!not-base64!!') }

    it 'skips the event' do
      expect(::Gitlab::BillingEvents::Client).not_to receive(:track_billing_event)

      expect(result).to be_success
      expect(result.payload).to eq(forwarded_events: 0)
    end
  end

  context 'when an event is not a hash' do
    let(:events) { ['nope', event] }

    it 'skips it and forwards the rest' do
      expect(::Gitlab::BillingEvents::Client).to receive(:track_billing_event).once

      expect(result).to be_success
      expect(result.payload).to eq(forwarded_events: 1)
    end
  end

  context 'when events is not an array' do
    let(:events) { nil }

    it 'returns an error' do
      expect(::Gitlab::BillingEvents::Client).not_to receive(:track_billing_event)

      expect(result).to be_error
      expect(result.message).to eq('Invalid Snowplow payload')
    end
  end

  context 'when the timestamp is out of range' do
    let(:timestamp) { '2026-13-45T00:00:00' }

    it 'forwards the event without a timestamp' do
      expect(::Gitlab::BillingEvents::Client).to receive(:track_billing_event)
                                                   .with(hash_including(timestamp: nil))

      expect(result).to be_success
    end
  end

  context 'when the context has no namespace' do
    let(:billable_usage) { super().except('namespace_id', 'root_namespace_id') }

    it 'skips the event' do
      expect(::Gitlab::BillingEvents::Client).not_to receive(:track_billing_event)

      expect(result).to be_success
      expect(result.payload).to eq(forwarded_events: 0)
    end
  end

  context 'when the decoded contexts are not an object' do
    let(:event) { super().merge('cx' => Base64.urlsafe_encode64('[]')) }

    it 'skips the event' do
      expect(::Gitlab::BillingEvents::Client).not_to receive(:track_billing_event)

      expect(result).to be_success
      expect(result.payload).to eq(forwarded_events: 0)
    end
  end
end
