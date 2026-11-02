# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['GitlabSubscriptionUsageNonBillableUsage'], feature_category: :consumables_cost_management do
  it { expect(described_class.graphql_name).to eq('GitlabSubscriptionUsageNonBillableUsage') }
  it { expect(described_class).to require_graphql_authorizations(:read_subscription_usage) }

  it 'has expected fields' do
    expect(described_class).to have_graphql_fields([:product_id, :skip_reason, :total_credits_used, :daily_usage])
  end

  it 'defines field types' do
    expect(described_class.fields.transform_values { |field| field.type.to_type_signature }).to eq(
      'productId' => 'String!',
      'skipReason' => 'String',
      'totalCreditsUsed' => 'Float!',
      'dailyUsage' => '[GitlabSubscriptionDailyUsage!]!'
    )
  end
end
