# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Terraform::StateProtectionRulePolicy, feature_category: :infrastructure_as_code do
  let(:user) { build_stubbed(:user) }
  let(:record) { build_stubbed(:terraform_state_protection_rule) }

  subject(:policy) { described_class.new(user, record) }

  it { is_expected.to delegate_to(ProjectPolicy) }
end
