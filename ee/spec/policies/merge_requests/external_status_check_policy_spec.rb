# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::ExternalStatusCheckPolicy, feature_category: :security_policy_management do
  let(:user) { build_stubbed(:user) }
  let(:external_status_check) { build_stubbed(:external_status_check) }

  subject(:policy) { described_class.new(user, external_status_check) }

  it { is_expected.to delegate_to(ProjectPolicy) }
end
