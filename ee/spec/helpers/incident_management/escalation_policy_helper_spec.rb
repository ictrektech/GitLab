# frozen_string_literal: true

require 'spec_helper'

RSpec.describe IncidentManagement::EscalationPolicyHelper, feature_category: :incident_management do
  let(:user) { build_stubbed(:user) }
  let(:project) { build_stubbed(:project, namespace: build_stubbed(:namespace)) }

  describe '#escalation_policy_data' do
    subject(:data) { helper.escalation_policy_data(project) }

    before do
      allow(helper).to receive(:current_user) { user }
      allow(helper).to receive(:can?).with(user, :create_escalation_policy, project).and_return(false)
    end

    it 'returns escalation policies data' do
      is_expected.to eq(
        'project-path' => project.full_path,
        'empty_escalation_policies_svg_path' => helper.image_path('illustrations/status/status-new-md.svg'),
        'user_can_create_escalation_policy' => 'false',
        'access_level_description_path' => Gitlab::Routing.url_helpers.project_project_members_url(
          project,
          sort: 'access_level_desc'
        )
      )
    end
  end
end
