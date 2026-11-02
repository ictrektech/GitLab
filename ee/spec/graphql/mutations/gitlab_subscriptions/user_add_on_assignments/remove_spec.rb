# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::GitlabSubscriptions::UserAddOnAssignments::Remove, feature_category: :seat_cost_management do
  it { expect(described_class).to require_graphql_authorizations(:delete_add_on_assignment) }
end
