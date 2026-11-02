# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::SquashOptionPolicy, feature_category: :source_code_management do
  let(:user) { build_stubbed(:user) }

  subject(:policy) { described_class.new(user, squash_option) }

  context 'when the squash option belongs to a protected branch' do
    let(:squash_option) { build_stubbed(:branch_rule_squash_option) }

    it { is_expected.to delegate_to(Projects::BranchRulePolicy) }
  end

  context 'when the squash option is a project setting' do
    let(:squash_option) { build_stubbed(:project_setting) }

    it { is_expected.to delegate_to(Projects::AllBranchesRulePolicy) }
  end
end
