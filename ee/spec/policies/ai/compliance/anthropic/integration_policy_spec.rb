# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Compliance::Anthropic::IntegrationPolicy, feature_category: :ai_governance do
  let(:user) { build_stubbed(:user) }
  let(:integration) { build_stubbed(:ai_compliance_anthropic_integration, namespace: build_stubbed(:group)) }

  subject(:policy) { described_class.new(user, integration) }

  it { is_expected.to delegate_to(GroupPolicy) }
end
