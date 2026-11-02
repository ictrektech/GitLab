# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProjectMemberPolicy, feature_category: :groups_and_projects do
  let_it_be(:project) { create(:project) }
  let_it_be(:maintainer) { create(:user, maintainer_of: project) }
  let(:current_user) { maintainer }

  subject { described_class.new(current_user, member) }

  context 'with a security policy bot member', :aggregate_failures do
    let_it_be(:member) { create(:project_member, project: project, user: create(:user, :security_policy_bot)) }

    it { is_expected.not_to be_allowed(:destroy_project_member) }
    it { is_expected.not_to be_allowed(:update_project_member) }
  end
end
