# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Terraform::StateVersionPolicy do
  let(:user) { build_stubbed(:user) }
  let(:record) { build_stubbed(:terraform_state_version) }

  subject(:policy) { described_class.new(user, record) }

  it { is_expected.to delegate_to(Terraform::StatePolicy) }
end
