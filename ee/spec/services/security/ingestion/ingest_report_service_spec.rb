# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::Ingestion::IngestReportService, feature_category: :vulnerability_management do
  let(:service_object) { described_class.new(security_scan) }

  describe '#execute' do
    let(:security_scan) { create(:security_scan, :with_findings, scan_type: :sast) }

    subject(:ingest_report) { service_object.execute }

    before do
      create_list(:security_finding, 2, scan: security_scan, deduplicated: true)

      stub_const("Security::IngestionConstants::COMPONENTS_BATCH_SIZE", 1)

      allow(Security::Ingestion::FindingMapCollection).to receive(:new).with(security_scan.pipeline, security_scan).and_return([:foo, :bar])
      allow(Security::Ingestion::IngestReportSliceService).to receive(:execute).with(security_scan.pipeline, [:foo]).and_return([1])
      allow(Security::Ingestion::IngestReportSliceService).to receive(:execute).with(security_scan.pipeline, [:bar]).and_return([2])
    end

    it 'calls IngestReportSliceService for each slice of findings and accumulates the return values' do
      expect(ingest_report).to eq([1, 2])

      expect(Security::Ingestion::IngestReportSliceService).to have_received(:execute).twice
    end

    context 'when ingesting a slice of vulnerabilities fails' do
      let(:exception) { RuntimeError.new }
      let(:expected_processing_error) { { 'type' => 'IngestionError', 'message' => 'Ingestion failed for some vulnerabilities' } }

      before do
        allow(Security::Ingestion::IngestReportSliceService).to receive(:execute).with(security_scan.pipeline, [:foo]).and_raise(exception)
        allow(Gitlab::ErrorTracking).to receive(:track_exception)
      end

      it 'tracks the exception' do
        ingest_report

        expect(Gitlab::ErrorTracking).to have_received(:track_exception).with(exception)
      end

      it 'captures the error and sets the processing error for security scan record' do
        expect { ingest_report }.to change { security_scan.processing_errors }.from([]).to([expected_processing_error])
      end

      it 'accumulates the return value of only the succeeded executions' do
        expect(ingest_report).to eq([2])
      end
    end

    # `SecApplicationRecord.transaction` without `requires_new: true` joins an open
    # transaction, so a caller wrapping this chain would silently fold the namespace
    # statistics commit back into the slice. `:delete` is required: with transactional
    # fixtures the caller's transaction joins the test's and this passes either way.
    context 'when invoking the slice service', :delete do
      let(:observed) { [] }

      before do
        allow(Security::Ingestion::IngestReportSliceService).to receive(:execute) do
          observed << SecApplicationRecord.connection.transaction_open?
          []
        end
      end

      it 'does so outside of any sec transaction' do
        ingest_report

        expect(observed).to all(be(false))
      end
    end
  end
end
