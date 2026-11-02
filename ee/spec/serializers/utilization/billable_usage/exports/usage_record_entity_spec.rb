# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Utilization::BillableUsage::Exports::UsageRecordEntity, feature_category: :consumables_cost_management do
  # A row as DailyTotal holds it. What matters here is the mapping onto the wire shape,
  # which needs no database.
  let(:grouped_row) do
    Struct.new(
      :usage_date, :event_type, :feature_qualified_name, :operation_type,
      :unit_of_measure, :schema_version, :quantity, :events_count,
      keyword_init: true
    ).new(
      usage_date: Date.new(2026, 8, 10),
      event_type: 'secrets_read',
      feature_qualified_name: 'secrets_read',
      operation_type: nil,
      unit_of_measure: 'request',
      schema_version: 1,
      quantity: BigDecimal('1420.0'),
      events_count: 1420
    )
  end

  subject(:record) { described_class.represent(grouped_row).as_json }

  it 'exposes the fields the billing schema names, and no others' do
    expect(record.keys).to match_array(
      %i[event_id event_type timestamp quantity unit_of_measure metadata]
    )
  end

  it 'carries no namespace, since the export is billed per instance' do
    expect(record.to_s).not_to include('root_namespace')
  end

  it 'puts the fields the schema has no top-level slot for inside metadata' do
    expect(record[:metadata].keys).to match_array(
      %i[feature_qualified_name schema_version events_count quantity_kind]
    )
  end

  it 'timestamps the day at midday UTC, so it cannot drift across a day boundary' do
    expect(record[:timestamp]).to eq('2026-08-10T12:00:00Z')
  end

  describe 'event_id' do
    subject(:event_id) { record[:event_id] }

    let(:key) do
      {
        usage_date: grouped_row.usage_date,
        event_type: grouped_row.event_type,
        feature_qualified_name: grouped_row.feature_qualified_name,
        operation_type: grouped_row.operation_type
      }
    end

    def represented_event_id(overrides)
      row = grouped_row.dup
      overrides.each { |attribute, value| row[attribute] = value }

      described_class.represent(row).as_json[:event_id]
    end

    it 'returns a uuid' do
      expect(event_id).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'is namespaced by the instance, so two instances cannot collide on one key' do
      theirs = Digest::UUID.uuid_v5(SecureRandom.uuid, "#{described_class::EVENT_ID_PREFIX}:#{key.values.to_json}")

      expect(event_id).not_to eq(theirs)
    end

    # Every part of the export key has to move the id, or two distinct records would
    # be deduped into one by CustomersDot.
    {
      usage_date: Date.new(2026, 8, 11),
      event_type: 'secrets_stored',
      feature_qualified_name: 'code_review/v1',
      operation_type: 'compaction_auto'
    }.each do |attribute, value|
      it "changes when #{attribute} changes" do
        expect(represented_event_id(attribute => value)).not_to eq(event_id)
      end
    end

    # A record sums several stored rows, so it must never carry any one row's id.
    # RecordAggregateService derives a row's id from the five-column tuple with no
    # prefix; the prefix here is what keeps the two apart, even for a row with no
    # namespace, whose tuple otherwise matches the export key most closely.
    it 'can never equal a stored row id, including a namespace-less row' do
      row_uuid = Digest::UUID.uuid_v5(
        Gitlab::GlobalAnonymousId.instance_uuid,
        [key[:usage_date], key[:event_type], key[:feature_qualified_name], nil, key[:operation_type]].to_json
      )

      expect(event_id).not_to eq(row_uuid)
    end

    describe 'how usage_date is rendered' do
      it 'accepts a Date and its ISO-8601 string interchangeably' do
        expect(represented_event_id(usage_date: '2026-08-10')).to eq(event_id)
      end

      it 'does not accept a differently formatted date as the same day' do
        expect(represented_event_id(usage_date: '10/08/2026')).not_to eq(event_id)
      end
    end
  end

  describe 'quantity' do
    # SUM on a numeric column returns a BigDecimal, and BigDecimal#as_json renders a
    # JSON string. CustomersDot reads this with JSONExtractFloat, so it has to be a
    # number on the wire.
    it 'serialises as a JSON number rather than a string' do
      expect(Gitlab::Json.dump(record)).to include('"quantity":1420.0')
    end

    it 'is a Float once represented' do
      expect(record[:quantity]).to be_a(Float)
    end
  end

  describe 'quantity_kind' do
    it 'is counter for a tallied event type' do
      expect(record[:metadata][:quantity_kind]).to eq('counter')
    end

    context 'when the event type is reported as a snapshot' do
      before do
        grouped_row.event_type = 'secrets_stored'
      end

      it 'is snapshot, so a reader knows not to sum it across days' do
        expect(record[:metadata][:quantity_kind]).to eq('snapshot')
      end
    end
  end

  describe 'operation_type' do
    it 'is omitted rather than sent as null when a product reports none' do
      expect(record[:metadata]).not_to have_key(:operation_type)
    end

    context 'when a product reports one' do
      before do
        grouped_row.operation_type = 'regular'
      end

      it 'travels in metadata' do
        expect(record[:metadata][:operation_type]).to eq('regular')
      end

      it 'changes the event id, since CustomersDot bills operation types differently' do
        with_operation = record[:event_id]
        grouped_row.operation_type = nil

        expect(described_class.represent(grouped_row).as_json[:event_id]).not_to eq(with_operation)
      end
    end
  end
end
