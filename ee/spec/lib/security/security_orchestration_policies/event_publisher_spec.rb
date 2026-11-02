# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecurityOrchestrationPolicies::EventPublisher, feature_category: :security_policy_management do
  describe '#publish' do
    let_it_be(:created_policy) { create(:security_policy) }
    let_it_be(:updated_policy) { create(:security_policy) }
    let_it_be(:deleted_policy) { create(:security_policy) }
    let_it_be(:db_policy) { create(:security_policy) }

    let_it_be(:event_payload) do
      {
        security_policy_id: updated_policy.id,
        diff: { name: { from: 'Old Policy', to: 'New Policy' } },
        rules_diff: { created: [], updated: [], deleted: [] }
      }
    end

    let(:policy_changes) do
      instance_double(Security::SecurityOrchestrationPolicies::PolicyComparer, event_payload: event_payload)
    end

    let(:created_event) do
      instance_double(Security::PolicyCreatedEvent, data: { security_policy_id: created_policy.id })
    end

    let(:updated_event) do
      instance_double(Security::PolicyUpdatedEvent, data: event_payload)
    end

    let(:deleted_event) do
      instance_double(Security::PolicyDeletedEvent, data: { security_policy_id: deleted_policy.id })
    end

    let(:resync_event) do
      instance_double(Security::PolicyResyncEvent, data: { security_policy_id: db_policy.id })
    end

    let(:publisher_options) { {} }

    subject(:publish) do
      described_class.new(
        db_policies: [db_policy],
        created_policies: [created_policy],
        policies_changes: [policy_changes],
        deleted_policies: [deleted_policy],
        **publisher_options
      ).publish
    end

    before do
      allow(::Gitlab::EventStore).to receive(:publish_group)

      allow(Security::PolicyCreatedEvent).to receive(:new).with(data: { security_policy_id: created_policy.id })
        .and_return(created_event)
      allow(Security::PolicyUpdatedEvent).to receive(:new).with(data: event_payload).and_return(updated_event)
      allow(Security::PolicyDeletedEvent).to receive(:new).with(data: { security_policy_id: deleted_policy.id })
        .and_return(deleted_event)
      allow(Security::PolicyResyncEvent).to receive(:new).with(data: { security_policy_id: db_policy.id })
        .and_return(resync_event)
    end

    context 'when sync_reason is not given' do
      it 'publishes created, updated and deleted events' do
        expect(::Gitlab::EventStore).to receive(:publish_group).with([created_event])
        expect(::Gitlab::EventStore).to receive(:publish_group).with([updated_event])
        expect(::Gitlab::EventStore).to receive(:publish_group).with([deleted_event])

        publish
      end

      it 'does not publish resync events' do
        expect(::Gitlab::EventStore).not_to receive(:publish_group).with([resync_event])

        publish
      end
    end

    context 'when sync_reason is policy_change' do
      let(:publisher_options) { { sync_reason: :policy_change } }

      it 'publishes created, updated and deleted events' do
        expect(::Gitlab::EventStore).to receive(:publish_group).with([created_event])
        expect(::Gitlab::EventStore).to receive(:publish_group).with([updated_event])
        expect(::Gitlab::EventStore).to receive(:publish_group).with([deleted_event])

        publish
      end
    end

    context 'when sync_reason is configuration_assigned' do
      let(:publisher_options) { { sync_reason: :configuration_assigned } }

      it 'marks created events as triggered by assign and still publishes updated and deleted events' do
        allow(Security::PolicyCreatedEvent).to receive(:new)
          .with(data: { security_policy_id: created_policy.id, triggered_by_assign: true })
          .and_return(created_event)

        expect(::Gitlab::EventStore).to receive(:publish_group).with([created_event])
        expect(::Gitlab::EventStore).to receive(:publish_group).with([updated_event])
        expect(::Gitlab::EventStore).to receive(:publish_group).with([deleted_event])

        publish
      end
    end

    context 'when sync_reason is force_resync' do
      let(:publisher_options) { { sync_reason: :force_resync } }

      it 'publishes resync and deleted events for all undeleted policies' do
        expect(::Gitlab::EventStore).to receive(:publish_group).with([resync_event])
        expect(::Gitlab::EventStore).to receive(:publish_group).with([deleted_event])

        publish
      end

      it 'does not publish created or updated events' do
        expect(::Gitlab::EventStore).not_to receive(:publish_group).with([created_event])
        expect(::Gitlab::EventStore).not_to receive(:publish_group).with([updated_event])

        publish
      end
    end
  end
end
