# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::SessionCredits::IngestService, :click_house, feature_category: :duo_agent_platform do
  let(:updated_at) { '2026-10-08T10:15:30.123456Z' }
  let(:nodes) do
    [
      {
        workflowId: '101',
        creditsUsed: 12.3456,
        modelsUsed: %w[claude-sonnet gpt-4o],
        updatedAt: updated_at,
        creditsByModel: [{ model: 'claude-sonnet', creditsUsed: 10.3456 }, { model: 'gpt-4o', creditsUsed: 2.0 }]
      },
      {
        workflowId: 'gid://gitlab/Ai::DuoWorkflows::Workflow/102',
        creditsUsed: 0,
        modelsUsed: [],
        updatedAt: '2026-10-08T10:16:00.000001Z',
        creditsByModel: []
      }
    ]
  end

  subject(:execute) { described_class.new(nodes: nodes).execute }

  def rows
    ClickHouse::Client.select(<<~SQL, :main)
      SELECT workflow_id, credits_used, model_used, credits_by_model, updated_at
      FROM duo_workflow_session_enrichments FINAL
      ORDER BY workflow_id
    SQL
  end

  it 'writes one row per node with CustomersDot values and clock, exactly' do
    expect(execute).to be_success
    newest_us = (Time.utc(2026, 10, 8, 10, 16, 0, 1).to_r * 1_000_000).to_i

    expect(execute.payload).to eq(rows_written: 2, max_updated_at_us: newest_us)

    expect(rows).to eq([
      {
        'workflow_id' => 101,
        'credits_used' => BigDecimal('12.3456'),
        'model_used' => 'claude-sonnet',
        'credits_by_model' => { 'claude-sonnet' => BigDecimal('10.3456'), 'gpt-4o' => BigDecimal(2) },
        'updated_at' => Time.utc(2026, 10, 8, 10, 15, 30, 123_456)
      },
      {
        'workflow_id' => 102,
        'credits_used' => BigDecimal(0),
        'model_used' => '',
        'credits_by_model' => {},
        'updated_at' => Time.utc(2026, 10, 8, 10, 16, 0, 1)
      }
    ])
  end

  it 'quotes model names that carry CSV and literal delimiters' do
    nodes.first[:modelsUsed] = ["o'brien, v2\\beta"]
    nodes.first[:creditsByModel] = [{ model: "o'brien, v2\\beta", creditsUsed: 12.3456 }]

    expect(execute).to be_success

    expect(rows.first['model_used']).to eq("o'brien, v2\\beta")
    expect(rows.first['credits_by_model']).to eq("o'brien, v2\\beta" => BigDecimal('12.3456'))
  end

  it 'skips a node with null credits but keeps an explicit zero', :aggregate_failures do
    nodes.first[:creditsUsed] = nil
    nodes.first[:updatedAt] = '2026-10-08T12:00:00.000000Z'

    expect(execute).to be_success
    expect(execute.payload[:rows_written]).to eq(1)
    expect(rows.map { |row| row['workflow_id'] }).to eq([102])
    # The skipped node still moves the cursor, or a window of null-credit sessions would never advance.
    expect(execute.payload[:max_updated_at_us]).to eq((Time.utc(2026, 10, 8, 12).to_r * 1_000_000).to_i)
  end

  it 'reports invalid rows and writes nothing when creditsUsed is not a number' do
    nodes.first[:creditsUsed] = 'twelve'

    expect(ClickHouse::Client).not_to receive(:insert_csv)

    expect(execute).to be_error
    expect(execute.reason).to eq(:invalid_rows)
  end

  it 'reports invalid rows and writes nothing when updatedAt is unparsable' do
    nodes.first[:updatedAt] = 'yesterday'

    expect(ClickHouse::Client).not_to receive(:insert_csv)

    expect(execute).to be_error
    expect(execute.reason).to eq(:invalid_rows)
  end

  it 'reports invalid rows and writes nothing when a workflow id has no digits' do
    nodes.first[:workflowId] = 'not-an-id'

    expect(ClickHouse::Client).not_to receive(:insert_csv)

    expect(execute).to be_error
    expect(execute.reason).to eq(:invalid_rows)
    expect(rows).to be_empty
  end

  it 'does not insert when there is nothing to write' do
    expect(ClickHouse::Client).not_to receive(:insert_csv)

    result = described_class.new(nodes: []).execute

    expect(result).to be_success
    expect(result.payload).to eq(rows_written: 0, max_updated_at_us: nil)
  end

  it 'replaces the whole row when a later CustomersDot version arrives' do
    execute

    later = nodes.first.merge(creditsUsed: 20, modelsUsed: ['gpt-4o'], updatedAt: '2026-10-08T11:00:00.000000Z',
      creditsByModel: [{ model: 'gpt-4o', creditsUsed: 20 }])
    described_class.new(nodes: [later]).execute

    row = rows.find { |r| r['workflow_id'] == 101 }
    expect(row['credits_used']).to eq(BigDecimal(20))
    expect(row['model_used']).to eq('gpt-4o')
    expect(row['credits_by_model']).to eq('gpt-4o' => BigDecimal(20))
  end
end
