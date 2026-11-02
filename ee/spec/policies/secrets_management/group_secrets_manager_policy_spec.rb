# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::GroupSecretsManagerPolicy, feature_category: :secrets_management do
  it { expect(described_class).to delegate_to(::GroupPolicy) }
end
