# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Ai::Catalog::SkillType, feature_category: :ai_catalog_curation do
  it 'has the correct name' do
    expect(described_class.graphql_name).to eq('AiCatalogSkill')
  end

  it 'implements the correct interface' do
    expect(described_class.interfaces).to include(Types::Ai::Catalog::ItemInterface)
  end

  it 'exposes the repository pointer fields', :aggregate_failures do
    expect(described_class).to have_graphql_field(:path)
    expect(described_class).to have_graphql_field(:directory)
    expect(described_class).to have_graphql_field(:git_ref)
    expect(described_class).to have_graphql_field(:blob_sha)
    expect(described_class).to have_graphql_field(:commit_sha)
    expect(described_class).to have_graphql_field(:author_name)
  end

  it { expect(described_class).to require_graphql_authorizations(:read_ai_catalog_item) }

  describe 'granular token boundaries' do
    let(:directives) { described_class.directives.select { |d| d.is_a?(::Directives::Authz::GranularScope) } }

    # A skill always belongs to a project, so the project is the only boundary it can be read in.
    it 'accepts a project as boundary', :aggregate_failures do
      expect(directives.map { |d| d.arguments[:boundary_type] }).to contain_exactly('project')
      expect(directives.map { |d| d.arguments[:permissions] }).to all(eq(%w[read_ai_catalog_item]))
    end
  end
end
