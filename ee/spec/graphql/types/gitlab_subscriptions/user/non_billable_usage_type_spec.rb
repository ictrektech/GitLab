# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['GitlabSubscriptionUserCreditsUsageNonBillableUsage'],
  feature_category: :consumables_cost_management do
  it { expect(described_class.graphql_name).to eq('GitlabSubscriptionUserCreditsUsageNonBillableUsage') }

  it { expect(described_class).to require_graphql_authorizations(:read_user) }

  it 'has expected fields' do
    expect(described_class).to have_graphql_fields([:product_id, :skip_reason, :total_credits_used, :daily_usage])
  end

  it 'defines productId as a non-null string' do
    expect(described_class.fields['productId'].type.to_type_signature).to eq('String!')
  end

  it 'defines skipReason as nullable' do
    expect(described_class.fields['skipReason'].type.to_type_signature).to eq('String')
  end

  it 'defines totalCreditsUsed as a non-null float' do
    expect(described_class.fields['totalCreditsUsed'].type.to_type_signature).to eq('Float!')
  end

  it 'resolves dailyUsage through the self-scoped daily usage type' do
    expect(described_class.fields['dailyUsage'].type.to_type_signature)
      .to eq('[GitlabSubscriptionUserCreditsUsageDailyUsage!]!')
  end
end
