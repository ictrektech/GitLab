# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::ArtifactRegistry::Versions::BulkDelete, feature_category: :artifact_registry do
  include GraphqlHelpers

  subject(:mutation) { described_class }

  it { is_expected.to have_graphql_name('ArtifactRegistryVersionsBulkDelete') }

  # No count field: Artifact Registry reports acceptance, not a result. Asserted on the declared
  # fields because a request spec cannot see a payload field no query selects.
  it { is_expected.to have_graphql_fields(:repository, :errors, :client_mutation_id) }

  # The exact list pins the absence of a whole-collection argument.
  it { is_expected.to have_graphql_arguments(:name, :package_id, :ids, :client_mutation_id) }

  it 'leaves granular-token authorization to Artifact Registry' do
    directive = mutation.directives.find { |d| d.is_a?(Directives::Authz::GranularScope) }

    expect(directive.arguments[:skip_reason]).to eq('external_service_authorizes')
  end
end
