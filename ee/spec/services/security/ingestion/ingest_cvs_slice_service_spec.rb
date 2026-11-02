# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::Ingestion::IngestCvsSliceService, feature_category: :vulnerability_management do
  let_it_be(:finding_maps) { [create(:finding_map)] }

  describe '.execute' do
    subject(:ingest_cvs_slice) { described_class.execute(finding_maps) }

    before do
      described_class::SEC_DB_TASKS.each do |task_name|
        task = Object.const_get("Security::Ingestion::Tasks::#{task_name}", false)

        allow(task).to receive(:execute)
      end

      described_class::MAIN_DB_TASKS.each do |task_name|
        task = Object.const_get("Security::Ingestion::Tasks::#{task_name}", false)

        allow(task).to receive(:execute)
      end
    end

    it 'runs the series of tasks with a nil pipeline' do
      ingest_cvs_slice

      expect(Security::Ingestion::Tasks::IngestCvsSecurityScanners)
        .to have_received(:execute).ordered.with(nil, finding_maps)
      expect(Security::Ingestion::Tasks::IngestIdentifiers)
        .to have_received(:execute).ordered.with(nil, finding_maps)
      expect(Security::Ingestion::Tasks::IngestFindings)
        .to have_received(:execute).ordered.with(nil, finding_maps)
      expect(Security::Ingestion::Tasks::IngestVulnerabilities)
        .to have_received(:execute).ordered.with(nil, finding_maps)
      expect(Security::Ingestion::Tasks::AttachFindingsToVulnerabilities)
        .to have_received(:execute).ordered.with(nil, finding_maps)
      expect(Security::Ingestion::Tasks::IngestFindingIdentifiers)
        .to have_received(:execute).ordered.with(nil, finding_maps)
      expect(Security::Ingestion::Tasks::IngestFindingLinks)
        .to have_received(:execute).ordered.with(nil, finding_maps)
      expect(Security::Ingestion::Tasks::IngestFindingSignatures)
        .to have_received(:execute).ordered.with(nil, finding_maps)
      expect(Security::Ingestion::Tasks::IngestFindingEvidence)
        .to have_received(:execute).ordered.with(nil, finding_maps)
      expect(Security::Ingestion::Tasks::IngestVulnerabilityFlags)
        .to have_received(:execute).ordered.with(nil, finding_maps)
      expect(Security::Ingestion::Tasks::IngestVulnerabilityReads)
        .to have_received(:execute).ordered.with(nil, finding_maps)
      expect(Security::Ingestion::Tasks::IngestFindingRiskScores)
        .to have_received(:execute).ordered.with(nil, finding_maps)
      expect(Security::Ingestion::Tasks::IncreaseCountersTask)
        .to have_received(:execute).ordered.with(nil, finding_maps)
      expect(Security::Ingestion::Tasks::IngestVulnerabilityStatistics)
        .to have_received(:execute).ordered.with(nil, finding_maps)
      expect(Security::Ingestion::Tasks::HooksExecution)
        .to have_received(:execute).ordered.with(nil, finding_maps)
    end

    it 'runs IngestVulnerabilityNamespaceStatistics after the rest of the slice' do
      ingest_cvs_slice

      expect(Security::Ingestion::Tasks::HooksExecution)
        .to have_received(:execute).ordered.with(nil, finding_maps)
      expect(Security::Ingestion::Tasks::IngestVulnerabilityNamespaceStatistics)
        .to have_received(:execute).ordered.with(nil, finding_maps)
    end

    context 'when the ingest_namespace_statistics_in_own_transaction feature flag is disabled' do
      before do
        stub_feature_flags(ingest_namespace_statistics_in_own_transaction: false)
      end

      it 'runs IngestVulnerabilityNamespaceStatistics in its place in the slice task list' do
        ingest_cvs_slice

        expect(Security::Ingestion::Tasks::IngestFindingRiskScores)
          .to have_received(:execute).ordered.with(nil, finding_maps)
        expect(Security::Ingestion::Tasks::IncreaseCountersTask)
          .to have_received(:execute).ordered.with(nil, finding_maps)
        expect(Security::Ingestion::Tasks::IngestVulnerabilityStatistics)
          .to have_received(:execute).ordered.with(nil, finding_maps)
        expect(Security::Ingestion::Tasks::IngestVulnerabilityNamespaceStatistics)
          .to have_received(:execute).ordered.with(nil, finding_maps)
        expect(Security::Ingestion::Tasks::HooksExecution)
          .to have_received(:execute).ordered.with(nil, finding_maps)
      end
    end

    it 'runs MarkCvsProjectsAsVulnerable in the main db tasks' do
      ingest_cvs_slice

      expect(Security::Ingestion::Tasks::MarkCvsProjectsAsVulnerable).to have_received(:execute).with(nil, finding_maps)
    end

    it 'returns the vulnerability ids' do
      expect(ingest_cvs_slice).to eq(finding_maps.map(&:vulnerability_id))
    end
  end

  describe 'SEC_DB_TASKS ordering' do
    it 'runs the aggregate counter tasks after every other database task' do
      counters = %i[IncreaseCountersTask IngestVulnerabilityStatistics IngestVulnerabilityNamespaceStatistics]
      writes = described_class::SEC_DB_TASKS - %i[HooksExecution]

      expect(writes.last(3)).to eq(counters)
    end
  end
end
