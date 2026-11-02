# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::FindingPolicy do
  it { expect(described_class).to delegate_to(Security::ScanPolicy) }
end
