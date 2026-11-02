# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::ScopeCriterion, feature_category: :security_policy_management do
  describe '#ids' do
    it 'reads a bare id and an { id } hash alike' do
      expect(described_class.from([1, { 'id' => 2 }]).ids).to match_array([1, 2])
    end

    it 'skips an entry carrying no numeric id' do
      criterion = described_class.from([1, { 'type' => 'archived' }, { 'id' => 'two' }, nil, 'three'])

      expect(criterion.ids).to eq([1])
    end

    it 'coerces an integer-like string the way the store transpiler compiles it' do
      rego = Gitlab::PolicyStore::ScopeTranspiler
               .new({ 'projects' => { 'including' => ['42'] } }, policy_name: 'parity')
               .transpile

      expect(rego).to include('input.project.id in {42}')
      expect(described_class.from(['42', { 'id' => '7' }]).ids).to match_array([42, 7])
    end

    it 'skips an id outside the range the store accepts' do
      criterion = described_class.from([0, -3, (2**63), '0', 1.5, true])

      expect(criterion.ids).to be_empty
    end

    it 'is empty for anything that is not a list' do
      [nil, {}, 'projects', 7].each do |raw|
        expect(described_class.from(raw).ids).to be_empty
      end
    end
  end

  describe '#includes_type?' do
    it 'finds a typed entry' do
      criterion = described_class.from([{ 'id' => 1 }, { 'type' => 'archived' }])

      expect(criterion).to be_includes_type('archived')
      expect(criterion).not_to be_includes_type('personal')
    end

    it 'is false when nothing is typed' do
      expect(described_class.from([1, 2])).not_to be_includes_type('archived')
    end
  end
end
