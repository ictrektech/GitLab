# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::Security::PolicyStoreController, feature_category: :security_policy_management do
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:group) { create(:group) }

  let(:instance_enabled) { true }
  let(:group_enabled) { true }

  subject(:request) { get group_security_policy_store_index_url(group) }

  # Owners are the only group role holding create/update; auditors hold read only.
  before_all do
    group.add_owner(user)
  end

  before do
    sign_in(user)

    stub_licensed_features(security_orchestration_policies: true)
    stub_application_setting(policy_store_experiment_enabled: instance_enabled)
    group.namespace_settings.update!(policy_store_experiment_enabled: group_enabled)
  end

  context 'when the experiment is active for the group' do
    it 'renders the policy store page mounting the v2 app' do
      request

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to include('js-policy-store')
    end

    it 'renders the new page mounting the v2 app' do
      get new_group_security_policy_store_url(group)

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to include('js-policy-store')
    end

    it 'renders the edit page mounting the v2 app' do
      get edit_group_security_policy_store_url(group, '1')

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to include('js-policy-store')
    end

    it 'renders the detail page mounting the detail app' do
      get group_security_policy_store_url(group, '1')

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to include('js-policy-store-detail')
    end

    it 'tells the index the user may create a policy' do
      request

      expect(response.body).to include('data-can-create-policy="true"')
    end

    it 'tells the detail page which actions the user may take', :aggregate_failures do
      get group_security_policy_store_url(group, '1')

      expect(response.body).to include('data-can-update-policy="true"')
      expect(response.body).to include('data-can-delete-policy="true"')
    end
  end

  # An auditor is the only real role that reads the store without being able to
  # write it: every member role below owner is denied the read as well.
  context 'when the user is an auditor' do
    let_it_be(:auditor) { create(:user, :auditor) }

    before do
      stub_licensed_features(security_orchestration_policies: true, auditor_user: true)
      sign_in(auditor)
    end

    it 'tells the index not to offer the create action' do
      request

      expect(response.body).to include('data-can-create-policy="false"')
    end

    it 'tells the detail page the user may take no action', :aggregate_failures do
      get group_security_policy_store_url(group, '1')

      expect(response.body).to include('data-can-update-policy="false"')
      expect(response.body).to include('data-can-delete-policy="false"')
    end
  end

  # No membership role below owner holds create or update, so a developer stands in for
  # every member who should never reach the editor.
  context 'when the user is a developer' do
    let_it_be(:developer) { create(:user) }

    before_all do
      group.add_developer(developer)
    end

    before do
      sign_in(developer)
    end

    it 'returns 404 for the new page' do
      get new_group_security_policy_store_url(group)

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns 404 for the edit page' do
      get edit_group_security_policy_store_url(group, '1')

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  # No default role separates create from update, so denying one ability is the only way
  # to tell the two editor guards apart.
  context 'when the user cannot create policies' do
    before do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(user, :create_govern_policy, group).and_return(false)
    end

    it 'returns 404 for the new page' do
      get new_group_security_policy_store_url(group)

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'still renders the edit page', :aggregate_failures do
      get edit_group_security_policy_store_url(group, '1')

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to include('js-policy-store')
    end
  end

  context 'when the user cannot update policies' do
    before do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(user, :update_govern_policy, group).and_return(false)
    end

    it 'still renders the index (read) page' do
      request

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'still renders the new page', :aggregate_failures do
      get new_group_security_policy_store_url(group)

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to include('js-policy-store')
    end

    it 'returns 404 for the edit page' do
      get edit_group_security_policy_store_url(group, '1')

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'still renders the detail (read) page' do
      get group_security_policy_store_url(group, '1')

      expect(response).to have_gitlab_http_status(:ok)
    end
  end

  context 'when the user cannot read policies' do
    before do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?).with(user, :read_govern_policy, group).and_return(false)
    end

    it 'returns 404 for the index page' do
      request

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns 404 for the detail page' do
      get group_security_policy_store_url(group, '1')

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

    it 'returns 404 for the new page' do
      get new_group_security_policy_store_url(group)

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns 404 for the edit page' do
      get edit_group_security_policy_store_url(group, '1')

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns 404 for the detail page' do
      get group_security_policy_store_url(group, '1')

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

  context 'when the group toggle is off' do
    let(:group_enabled) { false }

    it 'returns 404' do
      request

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  context 'when the group is a subgroup' do
    let_it_be_with_reload(:subgroup) { create(:group, parent: group) }

    subject(:request) { get group_security_policy_store_index_url(subgroup) }

    it "renders the page under its top-level group's opt-in" do
      request

      expect(response).to have_gitlab_http_status(:ok)
    end

    context 'when only the subgroup opted in' do
      let(:group_enabled) { false }

      before do
        subgroup.namespace_settings.update!(policy_store_experiment_enabled: true)
      end

      it 'returns 404' do
        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
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
