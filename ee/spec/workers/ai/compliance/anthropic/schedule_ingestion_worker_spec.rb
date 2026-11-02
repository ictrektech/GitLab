# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Compliance::Anthropic::ScheduleIngestionWorker, feature_category: :ai_governance do
  let_it_be(:enabled_integration) { create(:ai_compliance_anthropic_integration, enabled: true) }
  let_it_be(:other_enabled_integration) { create(:ai_compliance_anthropic_integration, enabled: true) }
  let_it_be(:disabled_integration) { create(:ai_compliance_anthropic_integration, enabled: false) }

  subject(:worker) { described_class.new }

  it_behaves_like 'an idempotent worker' do
    before do
      stub_request(:get, %r{\Ahttps://api\.anthropic\.com/v1/compliance/apps/sessions/local})
        .to_return(status: 200, body: { data: [], next_page: nil }.to_json,
          headers: { 'Content-Type' => 'application/json' })
    end
  end

  describe '#perform' do
    let(:sync_worker) { Ai::Compliance::Anthropic::SyncSessionsWorker }

    def scheduled_jobs
      sync_worker.jobs.map do |job|
        { args: job['args'], at: job['at'].to_i, root_namespace: job['meta.root_namespace'] }
      end
    end

    def job_for(integration, at:)
      { args: [integration.id, nil], at: at.from_now.to_i, root_namespace: integration.namespace.full_path }
    end

    around do |example|
      freeze_time { example.run }
    end

    it 'schedules one session list walk per enabled integration with its namespace context' do
      worker.perform

      expect(scheduled_jobs).to contain_exactly(
        job_for(enabled_integration, at: 1.second),
        job_for(other_enabled_integration, at: 1.second)
      )
    end

    it 'does not enqueue walks immediately' do
      worker.perform

      expect(sync_worker.jobs).to all(include('at'))
    end

    it 'schedules each wave after the previous one, counting jobs across batches' do
      stub_const("#{described_class}::BATCH_SIZE", 1)
      stub_const("#{described_class}::WAVE_SIZE", 1)

      worker.perform

      expect(scheduled_jobs.pluck(:at)).to contain_exactly(
        1.second.from_now.to_i,
        (1.second + 5.minutes).from_now.to_i
      )
      expect(scheduled_jobs.pluck(:root_namespace)).to contain_exactly(
        enabled_integration.namespace.full_path,
        other_enabled_integration.namespace.full_path
      )
    end

    context 'when the waves do not fit in the spread window at the maximum delay' do
      before do
        stub_const("#{described_class}::WAVE_SIZE", 1)
        stub_const("#{described_class}::SPREAD_WINDOW", 4.minutes)
      end

      it 'shortens the delay between waves to fit the window' do
        worker.perform

        expect(scheduled_jobs.pluck(:at)).to contain_exactly(
          1.second.from_now.to_i,
          (1.second + 2.minutes).from_now.to_i
        )
      end
    end

    context 'when the spread window is shorter than one second per wave' do
      before do
        stub_const("#{described_class}::WAVE_SIZE", 1)
        stub_const("#{described_class}::SPREAD_WINDOW", 1.second)
      end

      it 'keeps waves at least one second apart' do
        worker.perform

        expect(scheduled_jobs.pluck(:at)).to contain_exactly(
          1.second.from_now.to_i,
          2.seconds.from_now.to_i
        )
      end
    end

    it 'does not query the namespace route once per integration' do
      control = ActiveRecord::QueryRecorder.new { worker.perform }

      create(:ai_compliance_anthropic_integration, enabled: true)

      expect { worker.perform }.not_to exceed_query_limit(control)
    end

    context 'when the feature flag is enabled for only one top-level group' do
      before do
        stub_feature_flags(claude_code_compliance_api_ingestion: enabled_integration.namespace)
      end

      it 'schedules a walk for that group only' do
        worker.perform

        expect(scheduled_jobs).to contain_exactly(job_for(enabled_integration, at: 1.second))
      end
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(claude_code_compliance_api_ingestion: false)
      end

      it 'schedules nothing' do
        worker.perform

        expect(sync_worker.jobs).to be_empty
      end
    end
  end
end
