# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::Ascp::ScanPolicy, feature_category: :static_application_security_testing do
  it { expect(described_class).to delegate_to(ProjectPolicy) }
end
