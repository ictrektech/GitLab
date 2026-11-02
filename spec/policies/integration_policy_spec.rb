# frozen_string_literal: true

require 'spec_helper'

RSpec.describe IntegrationPolicy, :models do
  let(:user) { build_stubbed(:user) }
  let(:integration) { build_stubbed(:confluence_integration) }

  subject(:policy) { described_class.new(user, integration) }

  it { is_expected.to delegate_to(ProjectPolicy) }
end
