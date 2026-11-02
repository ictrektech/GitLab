# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Security::MttrOverTimeBySeverityType, feature_category: :vulnerability_management do
  include GraphqlHelpers

  let(:expected_fields) { %i[severity sum_days count mttr] }

  subject { described_class }

  it { is_expected.to have_graphql_fields(expected_fields) }

  it 'resolves the finder severity name to the enum value' do
    expect(resolve_field(:severity, { 'severity' => 'CRITICAL' })).to eq('critical')
  end
end
