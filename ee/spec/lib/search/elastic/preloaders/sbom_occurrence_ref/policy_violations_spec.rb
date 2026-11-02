# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::Elastic::Preloaders::SbomOccurrenceRef::PolicyViolations,
  feature_category: :dependency_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:dismissed_record) { create(:sbom_occurrence_ref, project: project) }
  let_it_be(:undismissed_record) { create(:sbom_occurrence_ref, project: project) }

  let_it_be(:dismissal) do
    create(:policy_dismissal, :preserved, project: project,
      license_occurrence_uuids: [dismissed_record.occurrence.uuid])
  end

  subject(:preloader) { described_class.new(records) }

  describe '#preload' do
    let(:records) { [dismissed_record, undismissed_record] }

    it 'keys the resolved violation by occurrence ref id' do
      expect(preloader.preload).to eq(
        dismissed_record.id => ::Security::PolicyViolations::DISMISSED_IN_MR,
        undismissed_record.id => ::Security::PolicyViolations::NOT_APPLICABLE
      )
    end

    it 'resolves the batch with a single dismissal lookup' do
      recorder = ActiveRecord::QueryRecorder.new(skip_cached: false) { preloader.preload }

      expect(recorder.log.count { |sql| sql.include?('security_policy_dismissals') }).to eq(1)
    end

    context 'when the dismissal is still open' do
      let_it_be(:project) { create(:project) }
      let_it_be(:open_record) { create(:sbom_occurrence_ref, project: project) }
      let_it_be(:open_dismissal) do
        create(:policy_dismissal, project: project, license_occurrence_uuids: [open_record.occurrence.uuid])
      end

      let(:records) { [open_record] }

      it 'resolves to not_applicable' do
        expect(preloader.preload).to eq(open_record.id => ::Security::PolicyViolations::NOT_APPLICABLE)
      end
    end

    context 'when records are empty' do
      let(:records) { [] }

      it 'returns an empty hash without querying' do
        recorder = ActiveRecord::QueryRecorder.new(skip_cached: false) { expect(preloader.preload).to eq({}) }

        expect(recorder.count).to eq(0)
      end
    end

    context 'when the lookup raises' do
      let(:records) { [dismissed_record] }

      before do
        allow(::Security::PolicyDismissal).to receive(:dismissed_license_occurrence_uuids)
          .and_raise(StandardError, 'Database error')
        allow(::Gitlab::ErrorTracking).to receive(:track_exception)
      end

      it 'tracks the exception and returns an empty hash' do
        expect(preloader.preload).to eq({})
        expect(::Gitlab::ErrorTracking).to have_received(:track_exception)
          .with(instance_of(StandardError), class: described_class.name)
      end
    end
  end
end
