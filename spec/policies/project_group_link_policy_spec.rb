# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProjectGroupLinkPolicy, feature_category: :system_access do
  let(:user) { build_stubbed(:user) }
  let(:project_group_link) { build_stubbed(:project_group_link) }

  subject(:policy) { described_class.new(user, project_group_link) }

  it { is_expected.to delegate_to(ProjectPolicy) }
end
