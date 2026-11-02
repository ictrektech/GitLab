# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::AllBranchesRulePolicy, feature_category: :source_code_management do
  let(:user) { build_stubbed(:user) }
  let(:branch_rule) { Projects::AllBranchesRule.new(build_stubbed(:project)) }

  subject(:policy) { described_class.new(user, branch_rule) }

  it { is_expected.to delegate_to(ProjectPolicy) }
end
