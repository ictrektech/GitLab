# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['CiMinutesProjectMonthlyUsage'], feature_category: :consumables_cost_management do
  it 'exposes only the minutes, shared runners duration, and project fields' do
    expect(described_class).to have_graphql_fields(
      :minutes,
      :shared_runners_duration,
      :project
    )
  end
end
