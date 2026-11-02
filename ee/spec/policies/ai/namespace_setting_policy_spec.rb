# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::NamespaceSettingPolicy, feature_category: :chat_engine do
  let(:user) { build_stubbed(:user) }
  let(:namespace_setting) { build_stubbed(:namespace_ai_settings, namespace: build_stubbed(:group)) }

  subject(:policy) { described_class.new(user, namespace_setting) }

  it { is_expected.to delegate_to(GroupPolicy) }
end
