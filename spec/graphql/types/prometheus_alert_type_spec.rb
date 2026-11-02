# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['PrometheusAlert'], feature_category: :incident_management do
  specify { expect(described_class.graphql_name).to eq('PrometheusAlert') }

  it 'has the expected fields' do
    expected_fields = %w[
      id humanized_text
    ]

    expect(described_class).to have_graphql_fields(*expected_fields)
  end
end
