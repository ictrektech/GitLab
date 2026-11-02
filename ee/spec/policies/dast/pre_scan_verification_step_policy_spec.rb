# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dast::PreScanVerificationStepPolicy, :dynamic_analysis,
  feature_category: :dynamic_application_security_testing do
  let(:user) { build_stubbed(:user) }
  let(:record) { build_stubbed(:dast_pre_scan_verification_step) }

  subject(:policy) { described_class.new(user, record) }

  it { is_expected.to delegate_to(Dast::PreScanVerificationPolicy) }
end
