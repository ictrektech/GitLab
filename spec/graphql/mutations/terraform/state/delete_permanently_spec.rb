# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Terraform::State::DeletePermanently, feature_category: :infrastructure_as_code do
  it 'has the expected GraphQL name' do
    expect(described_class.graphql_name).to eq('TerraformStateDeletePermanently')
  end

  it { expect(described_class).to require_graphql_authorizations(:delete_terraform_state) }
end
