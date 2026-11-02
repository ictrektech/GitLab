# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickHouse::DataIngestion::DuoWorkflowsModelAliasesSyncService, :click_house,
  feature_category: :duo_agent_platform do
  let(:connection) { ::ClickHouse::Connection.new(:main) }

  let(:catalog_models) do
    [
      { 'identifier' => 'claude_sonnet_4_6', 'name' => 'Claude Sonnet 4.6', 'provider' => 'Anthropic' },
      { 'identifier' => 'claude_sonnet_4_6_vertex', 'name' => 'Claude Sonnet 4.6', 'provider' => 'Vertex' },
      { 'identifier' => 'claude_haiku_4_5_bedrock', 'name' => 'Claude Haiku 4.5 - Bedrock', 'provider' => 'Bedrock' }
    ]
  end

  let(:spellings) do
    ['claude_sonnet_4_6', 'claude_sonnet_4_6_vertex', 'Claude Sonnet 4.6', 'us.anthropic.claude-haiku-4-5-v1:0',
      'model_gamma_preview']
  end

  subject(:execute) { described_class.new.execute }

  before do
    stub_catalog(catalog_models)

    clickhouse_fixture(:duo_workflow_session_enrichments,
      [*spellings, ''].each_with_index.map { |model_used, id| { workflow_id: id + 1, model_used: model_used } })
  end

  # The dictionary outlives table truncation and the model dimension groups
  # through it, so aliases written here must not reach later examples.
  after do
    ClickHouse::Client.execute('TRUNCATE TABLE duo_workflows_model_aliases', :main)
    ClickHouse::Client.execute('SYSTEM RELOAD DICTIONARY duo_workflows_model_aliases_dict',
      click_house_admin_database)
  end

  def stub_catalog(models)
    response = if models
                 ServiceResponse.success(payload: { 'models' => models })
               else
                 ServiceResponse.error(message: 'down')
               end

    allow(::Ai::ModelSelection::ModelDefinitions).to receive(:fetch)
      .and_return(::Ai::ModelSelection::ModelDefinitions.new(response))
  end

  def synced
    connection.select(<<~SQL).to_h { |row| [row['model_used'], [row['model_key'], row['hosting']]] }
      SELECT model_used, argMax(model_key, version) AS model_key, argMax(hosting, version) AS hosting
      FROM duo_workflows_model_aliases
      GROUP BY model_used
    SQL
  end

  it 'maps every resolvable spelling to its hosting-neutral key' do
    expect(execute.payload).to eq(spellings: 5, records_written: 4, catalog_available: true)

    expect(synced).to eq(
      'claude_sonnet_4_6' => %w[claude_sonnet_4_6 gitlab],
      'claude_sonnet_4_6_vertex' => %w[claude_sonnet_4_6 gitlab],
      'Claude Sonnet 4.6' => %w[claude_sonnet_4_6 gitlab],
      'us.anthropic.claude-haiku-4-5-v1:0' => %w[claude_haiku_4_5_bedrock gitlab]
    )
  end

  it 'writes nothing when no mapping changed' do
    described_class.new.execute

    expect(described_class.new.execute.payload[:records_written]).to eq(0)
  end

  it 'remaps existing spellings when the catalog changes' do
    stub_catalog(catalog_models.drop(1))
    described_class.new.execute
    expect(synced['claude_sonnet_4_6_vertex']).to eq(%w[claude_sonnet_4_6_vertex gitlab])

    stub_catalog(catalog_models)
    described_class.new.execute

    expect(synced['claude_sonnet_4_6_vertex']).to eq(%w[claude_sonnet_4_6 gitlab])
  end

  it 'picks up a spelling once the catalog learns it' do
    described_class.new.execute
    expect(synced).not_to have_key('model_gamma_preview')

    stub_catalog(catalog_models + [{ 'identifier' => 'model_gamma_preview', 'name' => 'Gamma', 'provider' => 'X' }])
    described_class.new.execute

    expect(synced['model_gamma_preview']).to eq(%w[model_gamma_preview gitlab])
  end

  context 'when there are no spellings to resolve' do
    let(:spellings) { [] }

    it 'does not fetch the model catalog' do
      expect(::Ai::ModelSelection::ModelDefinitions).not_to receive(:fetch)
      expect(execute.payload).to eq(spellings: 0, records_written: 0)
    end
  end

  context 'when the model catalog is unavailable' do
    it 'keeps the mappings resolved while it was reachable' do
      described_class.new.execute
      before_outage = synced

      stub_catalog(nil)
      response = described_class.new.execute

      expect(response.payload).to include(records_written: 0, catalog_available: false)
      expect(synced).to eq(before_outage)
    end
  end

  context 'with a self-hosted model sharing a catalog name' do
    let_it_be(:self_hosted_model) do
      create(:ai_self_hosted_model, name: 'Claude Sonnet 4.6', identifier: 'provider/sonnet')
    end

    let(:spellings) { ['provider/sonnet', 'claude_sonnet_4_6'] }

    it 'keys it apart from the catalog model' do
      execute

      expect(synced).to eq(
        'provider/sonnet' => ["self_hosted/#{self_hosted_model.id}", 'self_hosted'],
        'claude_sonnet_4_6' => %w[claude_sonnet_4_6 gitlab]
      )
    end

    it 'serves key and hosting through the dictionary, falling back to the raw value' do
      execute
      ClickHouse::Client.execute('SYSTEM RELOAD DICTIONARY duo_workflows_model_aliases_dict',
        click_house_admin_database)

      lookup = connection.select(<<~SQL).map { |row| row.values_at('model_key', 'hosting') }
        SELECT
          dictGetOrDefault('duo_workflows_model_aliases_dict', 'model_key', tuple(raw), raw) AS model_key,
          dictGetOrDefault('duo_workflows_model_aliases_dict', 'hosting', tuple(raw), '') AS hosting
        FROM (SELECT arrayJoin(['provider/sonnet', 'claude_sonnet_4_6', 'model_gamma_preview']) AS raw)
      SQL

      expect(lookup).to eq([
        ["self_hosted/#{self_hosted_model.id}", 'self_hosted'],
        %w[claude_sonnet_4_6 gitlab],
        ['model_gamma_preview', '']
      ])
    end
  end

  context 'when an alias is deleted' do
    def vertex_lookup
      ClickHouse::Client.execute('SYSTEM RELOAD DICTIONARY duo_workflows_model_aliases_dict',
        click_house_admin_database)

      connection.select(<<~SQL).first['model_key']
        SELECT dictGetOrDefault('duo_workflows_model_aliases_dict', 'model_key',
          tuple('claude_sonnet_4_6_vertex'), 'claude_sonnet_4_6_vertex') AS model_key
      SQL
    end

    before do
      described_class.new.execute

      connection.execute(<<~SQL)
        INSERT INTO duo_workflows_model_aliases (model_used, model_key, hosting, deleted)
        VALUES ('claude_sonnet_4_6_vertex', 'claude_sonnet_4_6', 'gitlab', true)
      SQL
    end

    it 'drops it from the dictionary' do
      expect(vertex_lookup).to eq('claude_sonnet_4_6_vertex')
    end

    it 'writes it again on the next run while it still resolves' do
      expect(described_class.new.execute.payload[:records_written]).to eq(1)
      expect(vertex_lookup).to eq('claude_sonnet_4_6')
    end
  end

  context 'when ClickHouse is not configured' do
    before do
      allow(::Gitlab::ClickHouse).to receive(:configured?).and_return(false)
    end

    it 'returns an error without writing' do
      expect(execute).to be_error
      expect(execute.reason).to eq(:db_not_configured)
    end
  end

  context 'when another job holds the lease' do
    it 'skips rather than running concurrently' do
      expect_next_instance_of(described_class) do |service|
        allow(service).to receive(:in_lock).and_raise(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
      end

      response = described_class.new.execute

      expect(response).to be_error
      expect(response.reason).to eq(:skipped)
    end
  end
end
