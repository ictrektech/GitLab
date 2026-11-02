# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Clusters::Agents::ActivityEventPolicy do
  let(:user) { build_stubbed(:user) }
  let(:record) { build_stubbed(:agent_activity_event) }

  subject(:policy) { described_class.new(user, record) }

  it { is_expected.to delegate_to(Clusters::AgentPolicy) }
end
