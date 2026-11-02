# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ci::CoverageApprovalCheck, feature_category: :code_testing do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:project) { create(:project, :repository) }
  let_it_be_with_refind(:merge_request) { create(:merge_request, source_project: project) }

  let(:head_pipeline) { create(:ci_pipeline, :success, project: project, ref: merge_request.source_branch) }
  let(:threshold) { nil }

  subject(:result) do
    described_class.check(merge_request: merge_request, pipeline: head_pipeline, threshold: threshold)
  end

  def create_build_with_coverage(pipeline, coverage)
    create(:ci_build, :success, pipeline: pipeline, coverage: coverage)
  end

  def create_base_pipeline_with_coverage(coverage)
    base_pipeline = create(:ci_pipeline, :success,
      project: project, ref: merge_request.target_branch, sha: merge_request.diff_base_sha)

    create_build_with_coverage(base_pipeline, coverage)
  end

  describe '.check' do
    context 'with a base pipeline' do
      before do
        create_build_with_coverage(head_pipeline, head_coverage)
        create_base_pipeline_with_coverage(base_coverage)
      end

      context 'when approval is required' do
        where(:head_coverage, :base_coverage, :threshold, :reason, :expected_threshold, :expected_base_coverage) do
          70.0 | 80.0 | nil  | :decreased             | nil  | 80.0
          70.0 | nil  | nil  | :missing_base_coverage | nil  | nil
          70.0 | 60.0 | 75.0 | :below_threshold       | 75.0 | nil
          70.0 | 80.0 | 75.0 | :below_threshold       | 75.0 | nil
          80.0 | 90.0 | 75.0 | :decreased             | nil  | 90.0
          80.0 | nil  | 75.0 | :missing_base_coverage | nil  | nil
        end

        with_them do
          it 'returns the reason with the coverage details' do
            expect(result).to have_attributes(
              required?: true,
              reason: reason,
              coverage: head_coverage,
              threshold: expected_threshold,
              base_coverage: expected_base_coverage
            )
          end
        end
      end

      context 'when approval is not required' do
        where(:head_coverage, :base_coverage, :threshold) do
          80.0 | 80.0 | nil
          90.0 | 80.0 | nil
          75.0 | 60.0 | 75.0
          90.0 | 80.0 | 75.0
        end

        with_them do
          it { is_expected.to eq(described_class::NOT_REQUIRED) }
        end
      end
    end

    context 'without a base pipeline' do
      where(:head_coverage, :threshold, :reason) do
        70.0 | nil  | nil
        70.0 | 75.0 | :below_threshold
        80.0 | 75.0 | nil
      end

      with_them do
        before do
          create_build_with_coverage(head_pipeline, head_coverage)
        end

        it 'only enforces the threshold' do
          expect(result.reason).to eq(reason)
        end
      end
    end

    context 'when the head pipeline has no coverage' do
      let(:threshold) { 75.0 }

      before do
        create_build_with_coverage(head_pipeline, nil)
        create_base_pipeline_with_coverage(80.0)
      end

      it { is_expected.to eq(described_class::NOT_REQUIRED) }
    end

    context 'when there is no head pipeline' do
      let(:head_pipeline) { nil }
      let(:threshold) { 75.0 }

      it { is_expected.to eq(described_class::NOT_REQUIRED) }
    end

    context 'when the coverage_minimum_threshold feature flag is disabled' do
      let(:threshold) { 75.0 }

      before do
        stub_feature_flags(coverage_minimum_threshold: false)
        create_build_with_coverage(head_pipeline, 70.0)
      end

      it 'ignores the threshold when coverage did not decrease' do
        create_base_pipeline_with_coverage(60.0)

        expect(result).to eq(described_class::NOT_REQUIRED)
      end

      it 'still requires approval when coverage decreased' do
        create_base_pipeline_with_coverage(80.0)

        expect(result).to have_attributes(required?: true, reason: :decreased, threshold: nil)
      end
    end
  end
end
