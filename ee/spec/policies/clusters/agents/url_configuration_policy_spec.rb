# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Clusters::Agents::UrlConfigurationPolicy, feature_category: :deployment_management do
  let(:user) { build_stubbed(:user) }
  let(:record) { build_stubbed(:cluster_agent_url_configuration) }

  subject(:policy) { described_class.new(user, record) }

  it { is_expected.to delegate_to(Clusters::AgentPolicy) }
end
