# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ProjectSecurityExclusionPolicy, feature_category: :secret_detection do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user) }
  let_it_be(:security_exclusion) { create(:project_security_exclusion, :with_raw_value, :active, project: project) }

  subject { described_class.new(user, security_exclusion) }

  it { is_expected.to delegate_to(ProjectPolicy) }
end
