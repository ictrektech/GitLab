# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::SkillDefinition, feature_category: :ai_catalog_curation do
  let(:definition) do
    {
      'path' => 'skills/cosign-blob/SKILL.md',
      'git_ref' => 'main',
      'blob_sha' => 'b' * 40,
      'commit_sha' => 'c' * 40,
      'author_name' => 'Jane Doe'
    }
  end

  let(:item) { build_stubbed(:ai_catalog_skill) }
  let(:version) { build_stubbed(:ai_catalog_skill_version, item: item, definition: definition) }

  subject(:skill_definition) { described_class.new(item, version) }

  it 'inherits from BaseDefinition' do
    expect(described_class.superclass).to eq(Ai::Catalog::BaseDefinition)
  end

  it 'reads the pointer and provenance from the version definition', :aggregate_failures do
    expect(skill_definition.path).to eq('skills/cosign-blob/SKILL.md')
    expect(skill_definition.git_ref).to eq('main')
    expect(skill_definition.blob_sha).to eq('b' * 40)
    expect(skill_definition.commit_sha).to eq('c' * 40)
    expect(skill_definition.author_name).to eq('Jane Doe')
  end

  describe '#directory' do
    it 'returns the directory containing SKILL.md' do
      expect(skill_definition.directory).to eq('skills/cosign-blob')
    end
  end

  context 'when the optional provenance properties are absent' do
    let(:definition) { super().except('commit_sha', 'author_name') }

    it 'returns nil for them', :aggregate_failures do
      expect(skill_definition.commit_sha).to be_nil
      expect(skill_definition.author_name).to be_nil
    end
  end
end
