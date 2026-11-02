# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::BranchRulePolicy, feature_category: :source_code_management do
  let(:user) { build_stubbed(:user) }
  let(:protected_branch) { build_stubbed(:protected_branch) }
  let(:branch_rule) { Projects::BranchRule.new(protected_branch.project, protected_branch) }

  subject(:policy) { described_class.new(user, branch_rule) }

  it { is_expected.to delegate_to(ProjectPolicy) }
end
