# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Vulnerabilities::ValidityDisplayStateResolver, feature_category: :secret_detection do
  include GraphqlHelpers

  specify do
    expect(described_class)
      .to have_nullable_graphql_type(Types::Vulnerabilities::ValidityDisplayStateEnum)
  end
end
