# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['SecurityTrackedContextQuota'], feature_category: :vulnerability_management do
  specify { expect(described_class.graphql_name).to eq('SecurityTrackedContextQuota') }

  it 'exposes the expected fields' do
    expect(described_class).to have_graphql_fields(
      :limit,
      :usage,
      :remaining,
      :explicitly_set
    )
  end
end
