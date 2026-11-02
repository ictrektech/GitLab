# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Issuables::CustomFieldPolicy, feature_category: :team_planning do
  let(:user) { build_stubbed(:user) }
  let(:custom_field) { build_stubbed(:custom_field, namespace: build_stubbed(:group)) }

  subject(:policy) { described_class.new(user, custom_field) }

  it { is_expected.to delegate_to(GroupPolicy) }
end
