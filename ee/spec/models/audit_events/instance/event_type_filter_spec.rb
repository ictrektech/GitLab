# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::Instance::EventTypeFilter, feature_category: :audit_events do
  subject(:event_type_filter) { build(:audit_events_instance_event_type_filters) }

  describe 'Associations' do
    it 'belongs to an external audit event destination' do
      expect(event_type_filter.external_streaming_destination).not_to be_nil
    end
  end

  describe 'Validations' do
    it { is_expected.to belong_to(:external_streaming_destination) }
    it { is_expected.to validate_uniqueness_of(:audit_event_type).scoped_to(:external_streaming_destination_id) }
  end

  it_behaves_like 'audit event streaming filter' do
    let(:factory_name) { "audit_events_instance_event_type_filters" }
  end

  describe '#kind' do
    it 'defaults to allow' do
      expect(event_type_filter).to be_allow
    end

    it 'can be set to deny' do
      expect(build(:audit_events_instance_event_type_filters, kind: :deny)).to be_deny
    end
  end

  describe 'scopes' do
    let_it_be(:destination) { create(:audit_events_instance_external_streaming_destination) }
    let_it_be(:allow_filter) do
      create(:audit_events_instance_event_type_filters,
        external_streaming_destination: destination,
        audit_event_type: 'event_type_filters_created')
    end

    let_it_be(:deny_filter) do
      create(:audit_events_instance_event_type_filters,
        external_streaming_destination: destination,
        audit_event_type: 'event_type_filters_deleted',
        kind: :deny)
    end

    describe '.allowlist' do
      it 'returns only kind: allow filters' do
        expect(described_class.allowlist).to contain_exactly(allow_filter)
      end
    end

    describe '.denylist' do
      it 'returns only kind: deny filters' do
        expect(described_class.denylist).to contain_exactly(deny_filter)
      end
    end
  end
end
