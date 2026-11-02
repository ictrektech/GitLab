# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::ServicePolicy, feature_category: :continuous_delivery do
  let(:user) { build_stubbed(:user) }
  let(:record) { build_stubbed(:cd_service) }

  subject(:policy) { described_class.new(user, record) }

  it { is_expected.to delegate_to(Cd::ApplicationPolicy) }
end
