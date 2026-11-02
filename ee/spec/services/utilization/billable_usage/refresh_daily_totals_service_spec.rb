# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Utilization::BillableUsage::RefreshDailyTotalsService, feature_category: :consumables_cost_management do
  let(:runtime_limiter) { Gitlab::Metrics::RuntimeLimiter.new }
  let(:now) { Time.current.change(usec: 0) }
  let(:today) { now.to_date }
  let(:yesterday) { today - 1.day }
  let(:margin) { described_class::WATERMARK_MARGIN }

  subject(:execute) { described_class.new(runtime_limiter: runtime_limiter).execute }

  def create_aggregate(*traits, **attributes)
    create(:billable_usage_daily_namespace_aggregate, *traits, updated_at: now, **attributes)
  end

  def total_for(usage_date, event_type: 'secrets_read', operation_type: nil)
    Utilization::BillableUsage::DailyTotal.find_by(
      usage_date: usage_date, event_type: event_type, operation_type: operation_type
    )
  end

  def totals
    Utilization::BillableUsage::DailyTotal.order(:usage_date, :event_type, :operation_type).map do |total|
      total.attributes.except('id')
    end
  end

  def expected_totals
    Utilization::BillableUsage::DailyNamespaceAggregate.all
      .group_by { |row| [row.usage_date, row.event_type, row.feature_qualified_name, row.operation_type] }
      .transform_values do |rows|
        {
          unit_of_measure: rows.map(&:unit_of_measure).min,
          schema_version: rows.map(&:schema_version).max,
          quantity: rows.sum(&:quantity),
          events_count: rows.sum(&:events_count),
          source_updated_at: rows.map(&:updated_at).max
        }
      end
  end

  def actual_totals
    Utilization::BillableUsage::DailyTotal.all.to_h do |total|
      [
        [total.usage_date, total.event_type, total.feature_qualified_name, total.operation_type],
        total.slice(:unit_of_measure, :schema_version, :quantity, :events_count, :source_updated_at).symbolize_keys
      ]
    end
  end

  def record_snapshot(root_namespace_id:, quantity:)
    Utilization::BillableUsage::RecordAggregateService.new(
      {
        event_type: 'secrets_stored',
        unit_of_measure: 'secret',
        quantity: quantity,
        timestamp: now.iso8601,
        root_namespace_id: root_namespace_id,
        metadata: { feature_qualified_name: 'secrets_stored' }
      },
      quantity_kind: Gitlab::BillingEvents::Client::SNAPSHOT
    ).execute
  end

  it 'sums counters across namespaces' do
    create_aggregate(root_namespace_id: 1, quantity: 3, events_count: 3, updated_at: now - 1.minute)
    create_aggregate(root_namespace_id: 2, quantity: 4.5, events_count: 4)

    expect(execute).to be_success
    expect(execute.payload).to eq(days_refreshed: 1, over_time: false)

    expect(total_for(today)).to have_attributes(
      quantity: 7.5, events_count: 7, unit_of_measure: 'request', source_updated_at: now
    )
  end

  it 'totals snapshots as the sum of the latest reading per root namespace' do
    record_snapshot(root_namespace_id: 1, quantity: 5)
    record_snapshot(root_namespace_id: 2, quantity: 3)
    execute

    expect(total_for(today, event_type: 'secrets_stored')).to have_attributes(quantity: 8, events_count: 2)

    record_snapshot(root_namespace_id: 1, quantity: 7)
    described_class.new.execute

    expect(total_for(today, event_type: 'secrets_stored')).to have_attributes(quantity: 10, events_count: 3)
  end

  it 'keeps operation types apart, including a null one' do
    create_aggregate(event_type: 'agent_llm', operation_type: nil, quantity: 1)
    create_aggregate(event_type: 'agent_llm', operation_type: 'regular', quantity: 2)

    execute

    expect(total_for(today, event_type: 'agent_llm')).to have_attributes(quantity: 1)
    expect(total_for(today, event_type: 'agent_llm', operation_type: 'regular')).to have_attributes(quantity: 2)
  end

  it 'overwrites a total rather than adding to it' do
    aggregate = create_aggregate(quantity: 5, events_count: 5)
    execute

    aggregate.update_columns(quantity: 6, events_count: 6, updated_at: now + 1.minute)
    described_class.new.execute

    expect(total_for(today)).to have_attributes(quantity: 6, events_count: 6, source_updated_at: now + 1.minute)
  end

  it 'picks up a late event on an earlier day in the next run' do
    create_aggregate(usage_date: today)
    execute

    create_aggregate(usage_date: yesterday, quantity: 2, updated_at: now + 1.minute)
    described_class.new.execute

    expect(total_for(yesterday)).to have_attributes(quantity: 2)
  end

  it 'does not refresh days last updated before the margin when nothing changed' do
    create_aggregate(usage_date: yesterday, updated_at: now - margin - 1.minute)
    create_aggregate(usage_date: today)
    execute

    expect { expect(described_class.new.execute.payload[:days_refreshed]).to eq(1) }.not_to change { totals }
  end

  it 'gives identical totals when run twice' do
    create_aggregate(usage_date: yesterday, root_namespace_id: 1, quantity: 2)
    create_aggregate(usage_date: today, root_namespace_id: 2, quantity: 3)

    execute
    first_totals = totals
    described_class.new.execute

    expect(totals).to eq(first_totals)
  end

  it 'rebuilds every day when the totals table is empty' do
    create_aggregate(usage_date: today - 40.days, updated_at: now - 1.day)
    create_aggregate(usage_date: yesterday, updated_at: now - margin - 1.minute)
    create_aggregate(usage_date: today)
    execute
    first_totals = totals

    Utilization::BillableUsage::DailyTotal.delete_all

    expect(described_class.new.execute.payload[:days_refreshed]).to eq(3)
    expect(totals.map { |total| total.except('created_at', 'updated_at') })
      .to eq(first_totals.map { |total| total.except('created_at', 'updated_at') })
  end

  describe 'watermark margin' do
    let!(:latest) { create_aggregate(usage_date: today, updated_at: now) }
    let!(:within_margin) { create_aggregate(usage_date: yesterday, quantity: 1, updated_at: now - 1.hour) }
    let!(:outside_margin) { create_aggregate(usage_date: today - 2.days, quantity: 1, updated_at: now - 1.hour) }

    before do
      execute
    end

    it 're-reads rows committed late with an updated_at within the margin before the watermark' do
      within_margin.update_columns(quantity: 5, updated_at: now - margin + 1.minute)

      described_class.new.execute

      expect(total_for(yesterday)).to have_attributes(quantity: 5)
    end

    it 'does not re-read rows with an updated_at beyond the margin' do
      outside_margin.update_columns(quantity: 5, updated_at: now - margin - 1.minute)

      described_class.new.execute

      expect(total_for(today - 2.days)).to have_attributes(quantity: 1)
    end
  end

  describe 'changed day limit' do
    before do
      stub_const('Utilization::BillableUsage::DailyNamespaceAggregate::MAX_CHANGED_DAYS', 2)

      # Spread further apart than the margin, so the next run's re-read does not refill the limit.
      create_aggregate(usage_date: today - 2.days, updated_at: now - 5.hours)
      create_aggregate(usage_date: yesterday, updated_at: now - 3.hours)
      create_aggregate(usage_date: today)
    end

    it 'refreshes the least recently changed days first, up to the limit', :aggregate_failures do
      expect(execute.payload[:days_refreshed]).to eq(2)
      expect(total_for(today)).to be_nil
    end

    it 'picks up the remaining days on the next run' do
      execute

      described_class.new.execute

      expect(actual_totals).to eq(expected_totals)
    end
  end

  context 'when the run stops early' do
    let(:runtime_limiter) do
      instance_double(Gitlab::Metrics::RuntimeLimiter, over_time?: true, was_over_time?: true)
    end

    before do
      # The earlier date changed more recently, so date order would process it first.
      create_aggregate(usage_date: yesterday, updated_at: now)
      create_aggregate(usage_date: today, updated_at: now - 1.hour)
    end

    it 'processes the least recently updated day first', :aggregate_failures do
      expect(execute.payload).to eq(days_refreshed: 1, over_time: true)
      expect(total_for(today)).to be_present
      expect(total_for(yesterday)).to be_nil
    end

    it 'does not move the watermark past the unprocessed day' do
      execute

      described_class.new.execute

      expect(total_for(yesterday)).to be_present
    end
  end

  it 'matches grouping the per-namespace rows' do
    create_aggregate(usage_date: yesterday, root_namespace_id: 1, quantity: 2.25, events_count: 2)
    create_aggregate(usage_date: yesterday, root_namespace_id: 2, quantity: 3, events_count: 1,
      updated_at: now - 1.minute)
    create_aggregate(usage_date: today, root_namespace_id: nil, quantity: 4, schema_version: 2)
    create_aggregate(:gauge, usage_date: today, root_namespace_id: 1, quantity: 9, events_count: 3)
    create_aggregate(usage_date: today, event_type: 'agent_llm', unit_of_measure: 'token',
      feature_qualified_name: 'software_development/v1', operation_type: 'regular', quantity: 1500.5)

    execute

    expect(actual_totals).to eq(expected_totals)
  end

  it 'returns without refreshing when there are no per-namespace rows' do
    expect(execute.payload).to eq(days_refreshed: 0, over_time: false)
    expect(Utilization::BillableUsage::DailyTotal.count).to eq(0)
  end
end
