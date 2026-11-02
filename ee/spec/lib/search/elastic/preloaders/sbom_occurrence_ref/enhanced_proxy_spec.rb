# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::Elastic::Preloaders::SbomOccurrenceRef::EnhancedProxy,
  feature_category: :dependency_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:occurrence_ref) { create(:sbom_occurrence_ref, project: project) }

  let(:records) { ::Sbom::OccurrenceRef.id_in([occurrence_ref.id]).preload_indexing_data }
  let(:ref) { ::Search::Elastic::References::Sbom::OccurrenceRef.new(occurrence_ref.id, occurrence_ref.es_parent) }
  let(:refs) { [ref] }

  describe '.default_value_for' do
    it 'reads a fixed default by field name' do
      expect(described_class.default_value_for(:policy_violations, occurrence_ref))
        .to eq(::Security::PolicyViolations::NOT_APPLICABLE)
    end

    it 'resolves a callable default from the record' do
      expect(described_class.default_value_for('malware', occurrence_ref)).to be(false)
    end

    it 'returns nil for an unknown field' do
      expect(described_class.default_value_for(:nope, occurrence_ref)).to be_nil
    end
  end

  describe '#preload_and_enhance!' do
    it 'assigns a proxy that answers for every preloaded field' do
      described_class.new(refs, records).preload_and_enhance!

      proxy = ref.database_record

      expect(proxy).to be_an_instance_of(::Search::Elastic::RecordProxy::SbomOccurrenceRef)
      expect(proxy.policy_violations).to eq(::Security::PolicyViolations::NOT_APPLICABLE)
      expect(proxy.malware).to be(false)
    end

    it 'delegates unenhanced methods to the underlying record' do
      described_class.new(refs, records).preload_and_enhance!

      expect(ref.database_record.sbom_occurrence_id).to eq(occurrence_ref.sbom_occurrence_id)
    end

    context 'when a ref has no matching record' do
      let(:refs) do
        [::Search::Elastic::References::Sbom::OccurrenceRef.new(non_existing_record_id, occurrence_ref.es_parent)]
      end

      it 'memoizes nil so the reference resolves to a delete without a further lookup' do
        described_class.new(refs, records).preload_and_enhance!

        recorder = ActiveRecord::QueryRecorder.new(skip_cached: false) do
          expect(refs.first.operation).to eq(:delete)
        end

        expect(recorder.count).to eq(0)
      end
    end

    context 'when a preloader returns no value for the record' do
      before do
        described_class::PROXIES.each_value do |config|
          allow_next_instance_of(config[:preloader]) do |instance|
            allow(instance).to receive(:preload).and_return({})
          end
        end
      end

      it 'falls back to the declared default for each field' do
        described_class.new(refs, records).preload_and_enhance!

        proxy = ref.database_record

        expect(proxy.policy_violations).to eq(::Security::PolicyViolations::NOT_APPLICABLE)
        expect(proxy.malware).to be(false)
      end
    end

    context 'when a preloader raises' do
      before do
        described_class::PROXIES.each_value do |config|
          allow_next_instance_of(config[:preloader]) do |instance|
            allow(instance).to receive(:perform_preload).and_raise(StandardError, 'Database error')
          end
        end

        allow(::Gitlab::ErrorTracking).to receive(:track_exception)
      end

      it 'degrades to the declared default without raising' do
        expect { described_class.new(refs, records).preload_and_enhance! }.not_to raise_error

        proxy = ref.database_record

        expect(proxy.policy_violations).to eq(::Security::PolicyViolations::NOT_APPLICABLE)
        expect(proxy.malware).to be(false)
        expect(::Gitlab::ErrorTracking).to have_received(:track_exception).twice
      end
    end
  end
end
