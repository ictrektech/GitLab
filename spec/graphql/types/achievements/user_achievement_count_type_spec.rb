# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['UserAchievementCount'], feature_category: :user_profile do
  include GraphqlHelpers

  let(:fields) do
    %w[
      achievement
      count
      first_awarded_at
      latest_user_achievement
    ]
  end

  it { expect(described_class.graphql_name).to eq('UserAchievementCount') }
  it { expect(described_class).to have_graphql_fields(fields) }
  it { expect(described_class).to require_graphql_authorizations(:read_achievement) }
end
