# frozen_string_literal: true
require 'spec_helper'

RSpec.describe AppSec::Fuzzing::Coverage::CorpusPolicy, feature_category: :fuzz_testing do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:user) { create(:user) }

  let_it_be(:corpus) { create(:corpus, project: project) }

  subject { described_class.new(user, corpus) }

  before do
    stub_licensed_features(coverage_fuzzing: true)
  end

  it { is_expected.to delegate_to(ProjectPolicy) }

  context 'when the user is a developer' do
    before_all do
      project.add_developer(user)
    end

    it { expect_allowed(:read_coverage_fuzzing) }

    context 'when coverage_fuzzing licensed feature is not available' do
      before do
        stub_licensed_features(coverage_fuzzing: false)
      end

      it { expect_disallowed(:read_coverage_fuzzing) }
    end
  end
end
