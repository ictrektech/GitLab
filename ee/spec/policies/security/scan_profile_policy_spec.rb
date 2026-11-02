# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanProfilePolicy, feature_category: :security_testing_configuration do
  it { expect(described_class).to delegate_to(GroupPolicy) }
end
