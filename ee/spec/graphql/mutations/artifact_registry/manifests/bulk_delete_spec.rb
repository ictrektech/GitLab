# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::ArtifactRegistry::Manifests::BulkDelete, feature_category: :artifact_registry do
  include GraphqlHelpers

  subject(:mutation) { described_class }

  it { is_expected.to have_graphql_name('ArtifactRegistryManifestsBulkDelete') }

  it { is_expected.to have_graphql_fields(:repository, :errors, :client_mutation_id) }

  it { is_expected.to have_graphql_arguments(:name, :image_id, :ids, :client_mutation_id) }

  it 'leaves granular-token authorization to Artifact Registry' do
    directive = mutation.directives.find { |d| d.is_a?(Directives::Authz::GranularScope) }

    expect(directive.arguments[:skip_reason]).to eq('external_service_authorizes')
  end
end
