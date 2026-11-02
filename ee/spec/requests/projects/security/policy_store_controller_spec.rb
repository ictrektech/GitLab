# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::Security::PolicyStoreController, feature_category: :security_policy_management do
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }

  let(:instance_enabled) { true }
  let(:group_enabled) { true }

  subject(:request) { get project_security_policy_store_index_url(project) }

  before_all do
    project.add_developer(user)
  end

  before do
    sign_in(user)

    stub_licensed_features(security_orchestration_policies: true)
    stub_application_setting(policy_store_experiment_enabled: instance_enabled)
    group.namespace_settings.update!(policy_store_experiment_enabled: group_enabled)
  end

  context 'when the experiment is active for the project' do
    it 'renders the policy store page mounting the v2 app' do
      request

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to include('js-policy-store')
    end

    it 'mounts the app as a project container with no authoring paths' do
      request

      expect(response.body).to include('data-namespace-type="project"')
      expect(response.body).not_to include('data-new-policy-path')
    end
  end

  # The project surface is read-only and list-only: authoring lives at the group
  # and the organization, and the detail page lands with the project query
  # documents, so none of these paths is routed. The catch-all route turns them
  # into a 404 rather than a routing error.
  describe 'unrouted paths' do
    %w[new 1 1/edit].each do |path|
      it "returns 404 for #{path}" do
        get "#{project_security_policy_store_index_url(project)}/#{path}"

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  context 'when the user cannot read policies' do
    let_it_be(:guest) { create(:user) }

    before_all do
      project.add_guest(guest)
    end

    before do
      sign_in(guest)
    end

    it 'returns 404' do
      request

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  context 'when the security_policies_v2 feature flag is disabled' do
    before do
      stub_feature_flags(security_policies_v2: false)
    end

    it 'returns 404' do
      request

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  context 'when the instance setting is off' do
    let(:instance_enabled) { false }

    it 'returns 404' do
      request

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  context 'when the top-level group toggle is off' do
    let(:group_enabled) { false }

    it 'returns 404' do
      request

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  context 'when the project is in a subgroup' do
    let_it_be(:subgroup) { create(:group, parent: group) }
    let_it_be(:subgroup_project) { create(:project, group: subgroup) }

    subject(:request) { get project_security_policy_store_index_url(subgroup_project) }

    before_all do
      subgroup_project.add_developer(user)
    end

    it "renders the page under its top-level group's opt-in" do
      request

      expect(response).to have_gitlab_http_status(:ok)
    end
  end

  context 'when the project has no group' do
    let_it_be(:personal_project) { create(:project) }

    subject(:request) { get project_security_policy_store_index_url(personal_project) }

    before_all do
      personal_project.add_developer(user)
    end

    it 'returns 404' do
      request

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  context 'when the feature is not licensed' do
    before do
      stub_licensed_features(security_orchestration_policies: false)
    end

    it 'returns 404' do
      request

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end
end
