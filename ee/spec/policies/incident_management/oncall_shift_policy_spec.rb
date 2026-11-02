# frozen_string_literal: true

require 'spec_helper'

RSpec.describe IncidentManagement::OncallShiftPolicy do
  it { expect(described_class).to delegate_to(IncidentManagement::OncallRotationPolicy) }
end
