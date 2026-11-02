# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Security::MttrOverTimeByReportTypeType, feature_category: :vulnerability_management do
  include GraphqlHelpers

  let(:expected_fields) { %i[report_type sum_days count mttr] }

  subject { described_class }

  it { is_expected.to have_graphql_fields(expected_fields) }

  it 'resolves the finder report type name to the enum value' do
    expect(resolve_field(:report_type, { 'report_type' => 'DEPENDENCY_SCANNING' })).to eq('dependency_scanning')
  end
end
