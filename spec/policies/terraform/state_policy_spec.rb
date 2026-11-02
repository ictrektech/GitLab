# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Terraform::StatePolicy do
  let(:user) { build_stubbed(:user) }
  let(:record) { build_stubbed(:terraform_state) }

  subject(:policy) { described_class.new(user, record) }

  it { is_expected.to delegate_to(ProjectPolicy) }
end
