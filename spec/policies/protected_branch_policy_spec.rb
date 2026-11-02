# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProtectedBranchPolicy, feature_category: :source_code_management do
  let(:user) { build_stubbed(:user) }

  subject(:policy) { described_class.new(user, protected_branch) }

  context 'when the protected branch belongs to a project' do
    let(:protected_branch) { build_stubbed(:protected_branch) }

    it { is_expected.to delegate_to(ProjectPolicy) }
  end

  context 'when the protected branch belongs to a group' do
    let(:protected_branch) { build_stubbed(:protected_branch, project: nil, group: build_stubbed(:group)) }

    it { is_expected.to delegate_to(GroupPolicy) }
  end
end
