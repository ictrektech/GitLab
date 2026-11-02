# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::LifecyclePolicy, feature_category: :team_planning do
  let(:user) { build_stubbed(:user) }
  let(:lifecycle) { build_stubbed(:work_item_custom_lifecycle, namespace: build_stubbed(:group)) }

  subject(:policy) { described_class.new(user, lifecycle) }

  it { is_expected.to delegate_to(GroupPolicy) }
end
