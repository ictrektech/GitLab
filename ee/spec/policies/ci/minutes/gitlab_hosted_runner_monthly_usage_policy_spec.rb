# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::Minutes::GitlabHostedRunnerMonthlyUsagePolicy, feature_category: :hosted_runners do
  let(:user) { build_stubbed(:user) }
  let(:usage) { build_stubbed(:ci_hosted_runner_monthly_usage) }

  subject(:policy) { described_class.new(user, usage) }

  it { is_expected.to delegate_to(GlobalPolicy) }
end
