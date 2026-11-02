# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ClickHouse::DuoWorkflowsModelAliasesSyncCronWorker, :click_house,
  feature_category: :duo_agent_platform do
  it_behaves_like 'an idempotent worker'

  it 'delegates to the sync service' do
    expect_next_instance_of(ClickHouse::DataIngestion::DuoWorkflowsModelAliasesSyncService) do |service|
      expect(service).to receive(:execute).and_return(ServiceResponse.success(payload: {}))
    end

    described_class.new.perform
  end

  context 'with a sync response' do
    let(:worker) { described_class.new }

    before do
      allow_next_instance_of(ClickHouse::DataIngestion::DuoWorkflowsModelAliasesSyncService) do |service|
        allow(service).to receive(:execute).and_return(response)
      end
    end

    context 'when the sync succeeds' do
      let(:response) { ServiceResponse.success(payload: { aliases: 3 }) }

      it 'logs the result' do
        expect(worker).to receive(:log_extra_metadata_on_done).with(:result, { aliases: 3 })

        worker.perform
      end
    end

    context 'when the sync fails' do
      let(:response) { ServiceResponse.error(message: 'catalog unavailable') }

      it 'does not log a result' do
        expect(worker).not_to receive(:log_extra_metadata_on_done)

        worker.perform
      end
    end
  end

  context 'when ClickHouse is not configured' do
    before do
      allow(::Gitlab::ClickHouse).to receive(:configured?).and_return(false)
    end

    it 'does not run the sync' do
      expect(ClickHouse::DataIngestion::DuoWorkflowsModelAliasesSyncService).not_to receive(:new)

      described_class.new.perform
    end
  end
end
