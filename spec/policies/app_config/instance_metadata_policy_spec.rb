# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AppConfig::InstanceMetadataPolicy, feature_category: :api do
  subject(:policy) { described_class.new(build_stubbed(:user), AppConfig::InstanceMetadata.new) }

  it { is_expected.to delegate_to(GlobalPolicy) }
end
