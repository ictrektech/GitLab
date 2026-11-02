# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProjectStatisticsPolicy, feature_category: :source_code_management do
  let(:user) { build_stubbed(:user) }
  let(:statistics) { ProjectStatistics.new(project: build_stubbed(:project)) }

  subject(:policy) { described_class.new(user, statistics) }

  it { is_expected.to delegate_to(ProjectPolicy) }
end
