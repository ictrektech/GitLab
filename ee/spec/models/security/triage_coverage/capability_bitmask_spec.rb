# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::TriageCoverage::CapabilityBitmask, feature_category: :security_asset_inventories do
  describe 'BITS' do
    it 'is an append-only, frozen mapping of trigger types to bit positions' do
      expect(described_class::BITS).to eq(
        sbom_ingested: 0,
        sast_false_positive: 1,
        sast_vulnerability_resolution: 2,
        secret_detection_false_positive: 3,
        vulnerability_enrichment: 4
      )
      expect(described_class::BITS).to be_frozen
    end

    it 'keeps every bit value below 15 to avoid overflowing the 2-byte integer columns' do
      expect(described_class::BITS.values).to all(be < 15)
    end
  end

  describe '.trigger_types' do
    it 'returns the trigger types in bit order' do
      expect(described_class.trigger_types).to eq(
        %i[sbom_ingested sast_false_positive sast_vulnerability_resolution secret_detection_false_positive
          vulnerability_enrichment]
      )
    end
  end

  describe '.mask_for' do
    it 'returns the bitmask for a known trigger type' do
      expect(described_class.mask_for(:sast_false_positive)).to eq(0b10)
    end

    it 'accepts a string trigger type' do
      expect(described_class.mask_for('sast_false_positive')).to eq(0b10)
    end

    it 'returns nil for an unknown trigger type' do
      expect(described_class.mask_for(:unknown)).to be_nil
    end

    it 'returns nil when given nil' do
      expect(described_class.mask_for(nil)).to be_nil
    end
  end

  describe '.encode' do
    it 'sets the on bit for each enabled trigger and the auto bit only when marked auto' do
      capabilities = {
        sbom_ingested: [true, true],
        sast_false_positive: [true, false],
        sast_vulnerability_resolution: [false, false]
      }

      expect(described_class.encode(capabilities)).to eq(
        triage_capabilities_on: 0b11,
        triage_capabilities_auto: 0b1
      )
    end

    it 'ignores unknown trigger types' do
      expect(described_class.encode(unknown: [true, true])).to eq(
        triage_capabilities_on: 0,
        triage_capabilities_auto: 0
      )
    end

    it 'returns zeroed-out masks for an empty hash' do
      expect(described_class.encode({})).to eq(triage_capabilities_on: 0, triage_capabilities_auto: 0)
    end
  end

  describe '.decode' do
    it 'reports sbom_ingested as enabled with no run_mode, since it is two-state' do
      entry = described_class.decode(0b1, 0b1).find { |c| c[:trigger_type] == :sbom_ingested }

      expect(entry).to eq(trigger_type: :sbom_ingested, enabled: true, run_mode: nil)
    end

    it 'reports a three-state trigger as manual when the on bit is set but the auto bit is not' do
      entry = described_class.decode(0b10, 0b0).find { |c| c[:trigger_type] == :sast_false_positive }

      expect(entry).to eq(trigger_type: :sast_false_positive, enabled: true, run_mode: :manual)
    end

    it 'reports a three-state trigger as auto when both bits are set' do
      entry = described_class.decode(0b10, 0b10).find { |c| c[:trigger_type] == :sast_false_positive }

      expect(entry).to eq(trigger_type: :sast_false_positive, enabled: true, run_mode: :auto)
    end

    it 'reports every trigger as disabled with no run_mode when both masks are zero' do
      expect(described_class.decode(0, 0)).to contain_exactly(
        { trigger_type: :sbom_ingested, enabled: false, run_mode: nil },
        { trigger_type: :sast_false_positive, enabled: false, run_mode: nil },
        { trigger_type: :sast_vulnerability_resolution, enabled: false, run_mode: nil },
        { trigger_type: :secret_detection_false_positive, enabled: false, run_mode: nil },
        { trigger_type: :vulnerability_enrichment, enabled: false, run_mode: nil }
      )
    end
  end
end
