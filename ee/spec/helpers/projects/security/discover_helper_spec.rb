# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::Security::DiscoverHelper, feature_category: :activation do
  describe '#project_security_discover_data' do
    let(:user) { build_stubbed(:user) }
    let(:project) { build_stubbed(:project, namespace: build_stubbed(:user_namespace, owner: user)) }

    let(:content) { 'discover-project-security' }

    let(:expected_project_security_discover_data) do
      {
        project: {
          id: project.id,
          name: project.name,
          personal: "true"
        },
        link: {
          main: new_trial_registration_path(glm_source: 'gitlab.com', glm_content: content),
          secondary: profile_billings_path(project.group, source: content)
        }
      }
    end

    subject(:project_security_discover_data) do
      helper.project_security_discover_data(project)
    end

    before do
      allow(helper).to receive(:current_user).and_return(user)
    end

    it 'builds correct hash' do
      expect(project_security_discover_data).to eq(expected_project_security_discover_data)
    end
  end
end
