# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DastSiteValidationPolicy, feature_category: :dynamic_application_security_testing do
  let(:user) { build_stubbed(:user) }
  let(:record) { build_stubbed(:dast_site_validation) }

  subject(:policy) { described_class.new(user, record) }

  it { is_expected.to delegate_to(ProjectPolicy) }
end
