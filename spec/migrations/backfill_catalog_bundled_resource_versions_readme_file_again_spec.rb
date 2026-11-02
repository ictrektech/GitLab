# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe BackfillCatalogBundledResourceVersionsReadmeFileAgain, migration: :gitlab_main_cell_local,
  feature_category: :pipeline_composition do
  let(:bundled_resources) { table(:catalog_bundled_resources) }
  let(:versions) { table(:catalog_bundled_resource_versions) }

  let(:bundled_resource) do
    bundled_resources.create!(
      server_fqdn: 'cell.example.com', full_path: 'acme/widgets', name: 'Widgets'
    )
  end

  def create_version(**attrs)
    versions.create!(
      {
        catalog_bundled_resource_id: bundled_resource.id,
        semver_major: 1, semver_minor: 0, semver_patch: 0
      }.merge(attrs)
    )
  end

  it 'picks up a row the old code wrote after the pre-deploy backfill ran' do
    version = create_version(file_store: 2)

    migrate!

    version.reload
    expect(version.readme_file).to eq('readme.json')
    expect(version.readme_file_store).to eq(2)
  end

  it 'leaves rows the pre-deploy backfill already set alone' do
    version = create_version(file_store: 2, readme_file: 'readme.json', readme_file_store: 1)

    migrate!

    version.reload
    expect(version.readme_file).to eq('readme.json')
    expect(version.readme_file_store).to eq(1)
  end
end
