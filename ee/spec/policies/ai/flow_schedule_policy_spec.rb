# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowSchedulePolicy, feature_category: :dap_triggers do
  it { expect(described_class).to delegate_to(::ProjectPolicy) }
end
