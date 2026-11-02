# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Security::MttrOverTimeBucketType, feature_category: :vulnerability_management do
  let(:expected_fields) { %i[start_date end_date sum_days count mttr by_severity by_report_type] }

  subject { described_class }

  it { is_expected.to have_graphql_fields(expected_fields) }
end
