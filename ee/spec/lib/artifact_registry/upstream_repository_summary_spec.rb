# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::UpstreamRepositorySummary, feature_category: :artifact_registry do
  let(:attributes) do
    {
      'id' => 'a1b2c3d4-0000-0000-0000-000000000000',
      'name' => 'payment-core',
      'format' => 'maven',
      'kind' => 'remote',
      'visibility' => 'private',
      'size_bytes' => 9_876_543_210,
      'settings' => { 'url' => 'https://repo.example.com/maven2', 'last_health_status' => 'healthy' }
    }
  end

  subject(:summary) { described_class.new(attributes) }

  describe 'rendered readers' do
    it 'exposes every documented field', :aggregate_failures do
      expect(summary.id).to eq('a1b2c3d4-0000-0000-0000-000000000000')
      expect(summary.name).to eq('payment-core')
      expect(summary.format).to eq('maven')
      expect(summary.kind).to eq('remote')
      expect(summary.visibility).to eq('private')
      expect(summary.size_bytes).to eq(9_876_543_210)
      expect(summary.settings).to eq(
        'url' => 'https://repo.example.com/maven2', 'last_health_status' => 'healthy'
      )
    end
  end

  describe '#size_bytes' do
    let(:attributes) { super().merge('size_bytes' => 0) }

    it 'returns zero rather than nil for an empty upstream' do
      expect(summary.size_bytes).to eq(0)
    end
  end

  describe '#settings' do
    context 'when settings is an empty hash' do
      let(:attributes) { super().merge('settings' => {}) }

      it 'returns nil' do
        expect(summary.settings).to be_nil
      end
    end

    context 'when settings is not a hash' do
      let(:attributes) { super().merge('settings' => 'https://repo.example.com/maven2') }

      it 'returns nil' do
        expect(summary.settings).to be_nil
      end
    end
  end

  describe 'fields the client does not read' do
    let(:attributes) { super().merge('newly_added_ar_field' => 'x') }

    it 'defines no reader for unknown keys', :aggregate_failures do
      expect(summary.name).to eq('payment-core')
      expect(summary).not_to respond_to(:newly_added_ar_field)
    end
  end

  describe 'absent fields' do
    let(:attributes) { { 'id' => 'a1b2c3d4-0000-0000-0000-000000000000' } }

    it 'returns nil for every absent field without raising', :aggregate_failures do
      expect(summary.id).to eq('a1b2c3d4-0000-0000-0000-000000000000')
      expect(summary.name).to be_nil
      expect(summary.format).to be_nil
      expect(summary.kind).to be_nil
      expect(summary.visibility).to be_nil
      expect(summary.size_bytes).to be_nil
      expect(summary.settings).to be_nil
    end
  end

  describe '#permissions' do
    it 'is nil when the client hands none in, even if the attributes carry a permissions object' do
      expect(described_class.new(attributes.merge('permissions' => { 'update_repository' => true })).permissions)
        .to be_nil
    end

    it 'exposes the verdicts the client hands in' do
      verdicts = ArtifactRegistry::Permissions::Verdicts.absent(
        scope: :repository, read: :upstream_repositories, slug: 'grp'
      )

      expect(described_class.new(attributes, verdicts).permissions).to be(verdicts)
    end
  end

  describe 'when constructed with nil attributes' do
    subject(:summary) { described_class.new(nil) }

    it 'treats it as an empty resource without raising', :aggregate_failures do
      expect(summary.id).to be_nil
      expect(summary.name).to be_nil
      expect(summary.format).to be_nil
      expect(summary.kind).to be_nil
      expect(summary.visibility).to be_nil
      expect(summary.size_bytes).to be_nil
      expect(summary.settings).to be_nil
    end
  end
end
