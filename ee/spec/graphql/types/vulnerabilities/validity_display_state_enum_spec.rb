# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Vulnerabilities::ValidityDisplayStateEnum, feature_category: :secret_detection do
  specify do
    expect(described_class.values.keys).to match_array(%w[
      ACTIVE
      INACTIVE
      UNKNOWN
      PENDING_VERIFICATION
      NOT_CHECKED_BY_ANALYZER
      NO_VENDOR_SUPPORT
    ])
  end

  # The resolvers pass stored statuses through this enum unmapped, so a
  # status added to Security::TokenStatus must be declared here too.
  it 'covers every stored token status' do
    stored_statuses = Security::TokenStatus::STATUSES.keys.map(&:to_s)

    expect(described_class.values.each_value.map(&:value)).to include(*stored_statuses)
  end
end
