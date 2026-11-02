# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::StateTransitionPolicy, feature_category: :vulnerability_management do
  it { expect(described_class).to delegate_to(ProjectPolicy) }
end
