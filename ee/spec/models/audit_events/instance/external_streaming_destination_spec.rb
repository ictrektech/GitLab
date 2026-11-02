# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AuditEvents::Instance::ExternalStreamingDestination, feature_category: :audit_events do
  subject(:destination) { build(:audit_events_instance_external_streaming_destination) }

  describe 'Associations' do
    it { is_expected.to have_many(:event_type_filters).class_name('AuditEvents::Instance::EventTypeFilter') }
    it { is_expected.to have_many(:event_type_denylist_filters).class_name('AuditEvents::Instance::EventTypeFilter') }
    it { is_expected.to have_many(:namespace_filters).class_name('AuditEvents::Instance::NamespaceFilter') }
  end

  describe 'Validations' do
    it 'validates uniqueness of name scoped to category' do
      create(:audit_events_instance_external_streaming_destination, name: 'Test Destination')
      destination = build(:audit_events_instance_external_streaming_destination, name: 'Test Destination')

      expect(destination).not_to be_valid
      expect(destination.errors.full_messages).to include('Name has already been taken')
    end

    it 'allows name to be used across different categories' do
      http_destination = create(:audit_events_instance_external_streaming_destination, name: 'Test Destination')
      gcp_destination = create(:audit_events_instance_external_streaming_destination, :gcp, name: 'Test Destination')
      aws_destination = create(:audit_events_instance_external_streaming_destination, :aws, name: 'Test Destination')

      expect(http_destination).to be_valid
      expect(gcp_destination).to be_valid
      expect(aws_destination).to be_valid
    end

    context 'when the destination already has more namespace filters than the limit' do
      let_it_be(:over_limit_destination, refind: true) { create(:audit_events_instance_external_streaming_destination) }

      before_all do
        create_list(:audit_events_streaming_instance_namespace_filters, 5,
          external_streaming_destination: over_limit_destination)

        # Simulates a row persisted before the limit was enforced at filter create.
        build(:audit_events_streaming_instance_namespace_filters,
          external_streaming_destination: over_limit_destination).save!(validate: false)
      end

      it 'stays saveable so the destination is not bricked' do
        over_limit_destination.name = 'Renamed destination'

        expect(over_limit_destination).to be_valid
        expect(over_limit_destination.save).to be true
      end
    end
  end

  it_behaves_like 'includes Limitable concern' do
    subject { build(:audit_events_instance_external_streaming_destination) }
  end

  it_behaves_like 'includes ExternallyStreamable concern', :audit_events_instance_external_streaming_destination do
    subject { build(:audit_events_instance_external_streaming_destination) }

    let(:model_factory_name) { :audit_events_instance_external_streaming_destination }
  end

  it_behaves_like 'includes LegacyDestinationMappable concern',
    :audit_events_instance_external_streaming_destination,
    described_class

  it_behaves_like 'includes Activatable concern' do
    let(:model_factory_name) { :audit_events_instance_external_streaming_destination }
  end

  describe 'denylist event type filtering' do
    let_it_be(:destination) { create(:audit_events_instance_external_streaming_destination) }
    let_it_be(:audit_event) { create(:audit_events_instance_audit_event) }

    before_all do
      create(:audit_events_instance_event_type_filters,
        external_streaming_destination: destination,
        audit_event_type: 'event_type_filters_deleted',
        kind: :deny)
    end

    it 'separates allowlist and denylist filters' do
      expect(destination.event_type_filters).to be_empty
      expect(destination.event_type_denylist_filters.map(&:audit_event_type))
        .to contain_exactly('event_type_filters_deleted')
    end

    it 'blocks the denylisted event' do
      expect(destination.allowed_to_stream?('event_type_filters_deleted', audit_event)).to be false
    end

    it 'streams events that are not denylisted' do
      expect(destination.allowed_to_stream?('event_type_filters_created', audit_event)).to be true
    end

    context 'when filters are preloaded' do
      let(:preloaded_destination) { described_class.preload_filters.find(destination.id) }

      it 'blocks the denylisted event from the preloaded filters' do
        expect(preloaded_destination.event_type_filters).to be_loaded
        expect(preloaded_destination.event_type_denylist_filters).to be_loaded
        expect(preloaded_destination.allowed_to_stream?('event_type_filters_deleted', audit_event)).to be false
      end
    end
  end

  describe ".configs_of_parent" do
    let!(:http_destinations) { create_list(:audit_events_instance_external_streaming_destination, 3) }
    let!(:non_http_destination) { create(:audit_events_instance_external_streaming_destination, :aws) }

    it 'returns configs of other destinations of same category' do
      configs = described_class.all.configs_of_parent(destination.id, 'http')

      expect(configs.length).to eq(http_destinations.length)
      expect(configs).to match_array(http_destinations.pluck(:config))
      expect(configs).to exclude(non_http_destination.config)
    end
  end
end
