# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GroupGroupLinkPolicy, feature_category: :system_access do
  let(:user) { build_stubbed(:user) }
  let(:group_group_link) { build_stubbed(:group_group_link) }

  subject(:policy) { described_class.new(user, group_group_link) }

  it { is_expected.to delegate_to(GroupPolicy) }
end
