# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::StatusPolicy, feature_category: :team_planning do
  let(:user) { build_stubbed(:user) }
  let(:status) { build_stubbed(:work_item_custom_status, namespace: build_stubbed(:group)) }

  subject(:policy) { described_class.new(user, status) }

  it { is_expected.to delegate_to(GroupPolicy) }
end
