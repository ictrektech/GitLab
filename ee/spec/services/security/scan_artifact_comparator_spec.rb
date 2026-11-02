# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanArtifactComparator, feature_category: :vulnerability_management do
  shared_examples 'compares artifacts by source priority' do |artifact_a_name, artifact_b_name, expected_result|
    it "returns #{expected_result} when comparing #{artifact_a_name} to #{artifact_b_name}" do
      artifact_a = public_send(artifact_a_name)
      artifact_b = public_send(artifact_b_name)

      result = described_class.compare(artifact_a, artifact_b)

      case expected_result
      when :negative
        expect(result).to be < 0
      when :positive
        expect(result).to be > 0
      when :zero
        expect(result).to eq(0)
      end
    end
  end

  shared_examples 'uses scanner ordering as tiebreaker' do
    before do
      allow(report_1).to receive(:scanner_order_to).and_return(1)
    end

    it 'uses scanner ordering when source priority is equal' do
      result = described_class.compare(artifact_1, artifact_2)

      expect(result).to be > 0
    end
  end

  describe '#compare' do
    context 'when comparing artifacts with different source priorities' do
      let(:sep_source) { build_stubbed(:ci_build_source, source: :scan_execution_policy) }
      let(:project_source) { build_stubbed(:ci_build_source, source: :web) }

      let(:sep_build) { build_stubbed(:ee_ci_build, job_source: sep_source) }
      let(:project_build) { build_stubbed(:ee_ci_build, job_source: project_source) }

      let(:sep_artifact) { build_stubbed(:ee_ci_job_artifact, :sast, job: sep_build) }
      let(:project_artifact) { build_stubbed(:ee_ci_job_artifact, :sast, job: project_build) }

      let(:sep_report) { build(:ci_reports_security_report, pipeline: sep_build.pipeline) }
      let(:project_report) { build(:ci_reports_security_report, pipeline: project_build.pipeline) }

      before do
        allow(sep_artifact).to receive(:security_report).and_return(sep_report)
        allow(project_artifact).to receive(:security_report).and_return(project_report)

        allow(sep_report).to receive(:scanner_order_to).and_return(0)
        allow(project_report).to receive(:scanner_order_to).and_return(0)
      end

      context 'when comparing SEP and Project artifacts with same scanner' do
        it_behaves_like 'compares artifacts by source priority', :sep_artifact, :project_artifact, :negative
      end

      context 'when comparing Project and SEP artifacts with same scanner' do
        it_behaves_like 'compares artifacts by source priority', :project_artifact, :sep_artifact, :positive
      end

      context 'when comparing SEP and SEP artifacts' do
        it_behaves_like 'compares artifacts by source priority', :sep_artifact, :sep_artifact, :zero
      end
    end

    context 'when source priorities are equal' do
      let(:build_1) { build_stubbed(:ee_ci_build, job_source: job_source_1) }
      let(:build_2) { build_stubbed(:ee_ci_build, job_source: job_source_2) }

      let(:artifact_1) { build_stubbed(:ee_ci_job_artifact, :sast, job: build_1) }
      let(:artifact_2) { build_stubbed(:ee_ci_job_artifact, :sast, job: build_2) }

      let(:report_1) { build(:ci_reports_security_report) }
      let(:report_2) { build(:ci_reports_security_report) }

      before do
        allow(artifact_1).to receive(:security_report).and_return(report_1)
        allow(artifact_2).to receive(:security_report).and_return(report_2)
      end

      context 'when both artifacts are from SEP with different scanners' do
        let(:job_source_1) { build_stubbed(:ci_build_source, source: :scan_execution_policy) }
        let(:job_source_2) { build_stubbed(:ci_build_source, source: :scan_execution_policy) }

        it_behaves_like 'uses scanner ordering as tiebreaker'
      end

      context 'when both artifacts are from unknown sources with different scanners' do
        let(:job_source_1) { build_stubbed(:ci_build_source, source: :web) }
        let(:job_source_2) { build_stubbed(:ci_build_source, source: :schedule) }

        it_behaves_like 'uses scanner ordering as tiebreaker'
      end

      context 'when both artifacts have the same scanner' do
        let(:job_source_1) { build_stubbed(:ci_build_source, source: :scan_execution_policy) }
        let(:job_source_2) { build_stubbed(:ci_build_source, source: :scan_execution_policy) }

        before do
          allow(report_1).to receive(:scanner_order_to).and_return(0)
        end

        it 'returns 0' do
          result = described_class.compare(artifact_1, artifact_2)

          expect(result).to eq(0)
        end
      end
    end

    context 'when security report is not present' do
      let(:build_without_report) { build_stubbed(:ee_ci_build, job_source: nil) }
      let(:build_with_report) { build_stubbed(:ee_ci_build, job_source: nil) }

      let(:artifact_with_report) { build_stubbed(:ee_ci_job_artifact, :sast, job: build_with_report) }
      let(:artifact_without_report) { build_stubbed(:ee_ci_job_artifact, :sast, job: build_without_report) }

      let(:report) { build(:ci_reports_security_report) }

      before do
        allow(artifact_with_report).to receive(:security_report).and_return(report)
        allow(artifact_without_report).to receive(:security_report).and_return(nil)
      end

      it 'puts artifact without report last' do
        result = described_class.compare(artifact_with_report, artifact_without_report)
        expect(result).to be(-1)
      end

      it 'puts artifact with report first' do
        result = described_class.compare(artifact_without_report, artifact_with_report)
        expect(result).to be(1)
      end
    end

    context 'when both security reports are nil' do
      let(:build_a) { build_stubbed(:ee_ci_build, job_source: nil) }
      let(:build_b) { build_stubbed(:ee_ci_build, job_source: nil) }

      let(:artifact_a) { build_stubbed(:ee_ci_job_artifact, :sast, job: build_a) }
      let(:artifact_b) { build_stubbed(:ee_ci_job_artifact, :sast, job: build_b) }

      before do
        allow(artifact_a).to receive(:security_report).and_return(nil)
        allow(artifact_b).to receive(:security_report).and_return(nil)
      end

      it 'returns 0' do
        result = described_class.compare(artifact_a, artifact_b)

        expect(result).to eq(0)
      end
    end

    context 'when artifacts have no associated job' do
      let(:artifact_a) { build_stubbed(:ee_ci_job_artifact, :sast) }
      let(:artifact_b) { build_stubbed(:ee_ci_job_artifact, :sast) }

      let(:report_a) { build(:ci_reports_security_report) }
      let(:report_b) { build(:ci_reports_security_report) }

      before do
        allow(artifact_a).to receive_messages(job: nil, security_report: report_a)
        allow(artifact_b).to receive_messages(job: nil, security_report: report_b)
        allow(report_a).to receive(:scanner_order_to).and_return(1)
      end

      it 'falls through to scanner ordering' do
        result = described_class.compare(artifact_a, artifact_b)

        expect(result).to eq(1)
      end
    end

    context 'when job source is not present' do
      let(:job_source) { build_stubbed(:ci_build_source, source: :scan_execution_policy) }

      let(:build_with_source) { build_stubbed(:ee_ci_build, job_source: job_source) }
      let(:build_without_source) { build_stubbed(:ee_ci_build, job_source: nil) }

      let(:artifact_with_source) { build_stubbed(:ee_ci_job_artifact, :sast, job: build_with_source) }
      let(:artifact_without_source) { build_stubbed(:ee_ci_job_artifact, :sast, job: build_without_source) }

      let(:report_with_source) { build(:ci_reports_security_report) }
      let(:report_without_source) { build(:ci_reports_security_report) }

      before do
        allow(artifact_with_source).to receive(:security_report).and_return(report_with_source)
        allow(artifact_without_source).to receive(:security_report).and_return(report_without_source)
      end

      context 'when comparing artifact with source to artifact without source' do
        it_behaves_like 'compares artifacts by source priority', :artifact_with_source,
          :artifact_without_source,
          :negative
      end

      context 'when both artifacts have no source' do
        let(:build_without_source_1) { build_stubbed(:ee_ci_build, job_source: nil) }
        let(:build_without_source_2) { build_stubbed(:ee_ci_build, job_source: nil) }

        let(:artifact_1) { build_stubbed(:ee_ci_job_artifact, :sast, job: build_without_source_1) }
        let(:artifact_2) { build_stubbed(:ee_ci_job_artifact, :sast, job: build_without_source_2) }

        let(:report_1) { build(:ci_reports_security_report) }
        let(:report_2) { build(:ci_reports_security_report) }

        before do
          allow(artifact_1).to receive(:security_report).and_return(report_1)
          allow(artifact_2).to receive(:security_report).and_return(report_2)

          allow(report_1).to receive(:scanner_order_to).and_return(1)
          allow(report_2).to receive(:scanner_order_to).and_return(-1)
        end

        it_behaves_like 'uses scanner ordering as tiebreaker'
      end
    end
  end
end
