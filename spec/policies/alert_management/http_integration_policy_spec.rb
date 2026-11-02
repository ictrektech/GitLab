# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AlertManagement::HttpIntegrationPolicy, :models do
  let(:user) { build_stubbed(:user) }
  let(:integration) { build_stubbed(:alert_management_http_integration) }

  subject(:policy) { described_class.new(user, integration) }

  it { is_expected.to delegate_to(ProjectPolicy) }
end
