# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::StatisticPolicy, feature_category: :security_asset_inventories do
  let_it_be(:project) { create(:project) }
  let_it_be(:statistic) { build(:vulnerability_statistic, project: project) }

  subject(:policy) { described_class.new(build_stubbed(:user), statistic) }

  it { is_expected.to delegate_to(ProjectPolicy) }
end
