# frozen_string_literal: true

require 'spec_helper'

RSpec.describe EE::MergeRequestMetricsService, feature_category: :code_review_workflow do
  subject do
    service = MergeRequestMetricsService.new(merge_request.metrics)
    service.merge(event)
    service.merge_request.metrics.reload

    service
  end

  describe '#merge' do
    let(:merge_request) { create(:merge_request, :merged) }
    let(:expected_commit_count) { 21 }
    let(:event) { instance_double(Event, author_id: merge_request.author.id, created_at: Time.current) }

    it 'saves metrics with productivity_data' do
      allow(merge_request).to receive(:commits_count).and_return(expected_commit_count)

      expect { subject }.to change { merge_request.metrics.commits_count }.to(expected_commit_count)
    end

    context 'when the data was prepared beforehand' do
      it 'reuses it instead of reading the diff again' do
        service = MergeRequestMetricsService.new(merge_request.metrics)
        service.prepare_merge_data

        expect(Analytics::MergeRequestMetricsCalculator).not_to receive(:new)

        expect { service.merge(event) }.to change { merge_request.metrics.reload.added_lines }.from(nil).to(118)
      end
    end

    context 'when computing productivity data times out' do
      before do
        allow_next_instance_of(Analytics::MergeRequestMetricsCalculator) do |calculator|
          allow(calculator).to receive(:productivity_data).and_raise(ActiveRecord::QueryCanceled)
        end
      end

      context 'when the data was prepared beforehand' do
        it 'tracks the error and still saves the merge metrics without calculated data' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
            an_instance_of(ActiveRecord::QueryCanceled),
            { merge_request_id: merge_request.id, project_id: merge_request.target_project_id },
            { merged_manually_detection: 'productivity_metrics_fallback' }
          )

          service = MergeRequestMetricsService.new(merge_request.metrics)
          service.prepare_merge_data

          expect { service.merge(event) }.to change { merge_request.metrics.reload.merged_at }.from(nil)
            .and not_change { merge_request.metrics.added_lines }.from(nil)
        end
      end

      context 'when the data was not prepared beforehand' do
        it 'raises and does not track the error' do
          expect(Gitlab::ErrorTracking).not_to receive(:track_exception)

          expect { subject }.to raise_error(ActiveRecord::QueryCanceled)
        end
      end
    end

    describe 'storing line counts' do
      let(:expected_added_lines) { 118 }
      let(:expected_removed_lines) { 9 }

      it 'updates `added_lines`' do
        expect { subject }.to change { merge_request.metrics.added_lines }.from(nil).to(expected_added_lines)
      end

      it 'updates `removed_lines`' do
        expect { subject }.to change { merge_request.metrics.removed_lines }.from(nil).to(expected_removed_lines)
      end
    end
  end
end
