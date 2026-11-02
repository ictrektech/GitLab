# frozen_string_literal: true

require 'spec_helper'

RSpec.describe IncidentManagement::OncallSchedulePolicy do
  it { expect(described_class).to delegate_to(ProjectPolicy) }
end
