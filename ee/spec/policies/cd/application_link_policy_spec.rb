# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cd::ApplicationLinkPolicy, feature_category: :continuous_delivery do
  let(:user) { build_stubbed(:user) }
  let(:record) { build_stubbed(:cd_application_link) }

  subject(:policy) { described_class.new(user, record) }

  it { is_expected.to delegate_to(Cd::ApplicationPolicy) }
end
