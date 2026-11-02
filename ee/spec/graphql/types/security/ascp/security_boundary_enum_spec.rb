# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Security::Ascp::SecurityBoundaryEnum, feature_category: :static_application_security_testing do
  specify { expect(described_class.graphql_name).to eq('AscpSecurityBoundary') }

  it 'exposes every boundary the model accepts' do
    expect(described_class.values.keys).to match_array(::Security::Ascp::SecurityContext::SECURITY_BOUNDARIES)
  end
end
