# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::PolicyDismissalPolicy, feature_category: :security_policy_management do
  it { expect(described_class).to delegate_to(ProjectPolicy) }
end
