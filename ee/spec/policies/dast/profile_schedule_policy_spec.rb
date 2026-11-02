# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dast::ProfileSchedulePolicy, feature_category: :dynamic_application_security_testing do
  let(:user) { build_stubbed(:user) }
  let(:record) { build_stubbed(:dast_profile_schedule) }

  subject(:policy) { described_class.new(user, record) }

  it { is_expected.to delegate_to(ProjectPolicy) }
end
