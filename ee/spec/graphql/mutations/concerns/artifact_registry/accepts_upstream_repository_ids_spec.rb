# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::AcceptsUpstreamRepositoryIds, feature_category: :artifact_registry do
  [
    ::Mutations::ArtifactRegistry::Repositories::Create,
    ::Mutations::ArtifactRegistry::Repositories::Update
  ].each do |mutation_class|
    context "with #{mutation_class}" do
      subject(:argument) { mutation_class.arguments['upstreamRepositoryIds'] }

      it 'declares the upstream list as an optional list of IDs', :aggregate_failures do
        expect(argument).to be_present
        expect(argument.type.to_type_signature).to eq('[ID!]')
      end

      it 'declares the refused upstream id as a nullable ID field' do
        expect(mutation_class.fields['refusedUpstreamRepositoryId'].type.to_type_signature).to eq('ID')
      end
    end
  end
end
