# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['GitlabSubscription'], feature_category: :consumables_cost_management do
  it { expect(described_class.graphql_name).to eq('GitlabSubscription') }
  it { expect(described_class).to have_graphql_fields(:active) }
  it { expect(described_class).to require_graphql_authorizations(:read_gitlab_subscription) }
end
