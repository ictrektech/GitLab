# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Utilization::BillableUsage::Exports::Checksum, feature_category: :consumables_cost_management do
  describe '.digest' do
    let(:document) { { 'a' => 1, 'b' => { 'c' => [1, 2, 3] } } }

    it 'is stable across calls for the same document' do
      first_digest = described_class.digest(document)
      second_digest = described_class.digest(document)

      expect(first_digest).to eq(second_digest)
    end

    it 'changes when a nested value changes' do
      changed = { 'a' => 1, 'b' => { 'c' => [1, 2, 4] } }

      expect(described_class.digest(changed)).not_to eq(described_class.digest(document))
    end

    it 'is the same regardless of hash key order' do
      reordered = { 'b' => { 'c' => [1, 2, 3] }, 'a' => 1 }

      expect(described_class.digest(reordered)).to eq(described_class.digest(document))
    end

    it 'is the same regardless of symbol vs string keys' do
      symbolized = { a: 1, b: { c: [1, 2, 3] } }

      expect(described_class.digest(symbolized)).to eq(described_class.digest(document))
    end

    it 'changes when array order changes, since record order is meaningful' do
      swapped = { 'a' => 1, 'b' => { 'c' => [2, 1, 3] } }

      expect(described_class.digest(swapped)).not_to eq(described_class.digest(document))
    end

    it 'is unaffected by the presence of the checksum keys' do
      with_checksum_keys = document.merge('checksum' => 'whatever', 'checksum_algorithm' => 'sha256')

      expect(described_class.digest(with_checksum_keys)).to eq(described_class.digest(document))
    end
  end

  describe '.seal' do
    let(:document) { { a: 1, b: { c: [1, 2, 3] } } }

    subject(:sealed) { described_class.seal(document) }

    it 'returns a string-keyed document' do
      expect(sealed.keys).to all(be_a(String))
    end

    it 'carries the checksum algorithm' do
      expect(sealed['checksum_algorithm']).to eq('sha256')
    end

    it 'carries a 64-character hex checksum' do
      expect(sealed['checksum']).to match(/\A[0-9a-f]{64}\z/)
    end

    # Pins the canonical form CustomersDot recomputes: SHA-256 of {"a":1,"b":{"c":[1,2,3]}}.
    it 'digests to a fixed value' do
      expect(sealed['checksum']).to eq('82fa3f154b5230c58284b6f306fac23340082c0a505d0e3e2c43652b35ecaccf')
    end

    it 'carries a checksum a verifier can recompute after stripping the checksum keys' do
      expect(described_class.digest(sealed)).to eq(sealed['checksum'])
    end

    it 'preserves the original content under its canonical (string-keyed) form' do
      expect(sealed).to include('a' => 1, 'b' => { 'c' => [1, 2, 3] })
    end

    it 'seals a document larger than the safe JSON parser allows' do
      large = { records: Array.new(Gitlab::Json::PARSE_LIMITS[:max_array_size] + 1) { |i| i } }

      expect(described_class.digest(described_class.seal(large))).to eq(described_class.seal(large)['checksum'])
    end
  end
end
