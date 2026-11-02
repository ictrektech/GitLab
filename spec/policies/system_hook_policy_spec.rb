# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SystemHookPolicy, feature_category: :webhooks do
  let(:user) { build_stubbed(:user) }
  let(:hook) { build_stubbed(:system_hook) }

  subject(:policy) { described_class.new(user, hook) }

  it { is_expected.to delegate_to(Organizations::OrganizationPolicy) }
end
