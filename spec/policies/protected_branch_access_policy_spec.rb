# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProtectedBranchAccessPolicy, feature_category: :source_code_management do
  let(:user) { build_stubbed(:user) }
  let(:protected_branch_access) { build_stubbed(:protected_branch_merge_access_level) }

  subject(:policy) { described_class.new(user, protected_branch_access) }

  it { is_expected.to delegate_to(ProtectedBranchPolicy) }
end
