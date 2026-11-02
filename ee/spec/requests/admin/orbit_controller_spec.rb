# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Admin::OrbitController, :enable_admin_mode, feature_category: :knowledge_graph do
  include AdminModeHelper
  include StubENV

  let_it_be(:admin) { create(:admin) }
  let_it_be(:user) { create(:user) }

  before do
    stub_env('IN_MEMORY_APPLICATION_SETTINGS', 'false')
    ApplicationSetting.create_from_defaults unless ApplicationSetting.current_without_cache
    stub_licensed_features(orbit: true)
    allow(Analytics::KnowledgeGraph).to receive(:enabled_for?).with(admin).and_return(true)
    allow(Analytics::KnowledgeGraph).to receive(:enabled_for?).with(user).and_return(true)
  end

  describe 'GET /admin/orbit' do
    it 'mounts the Orbit page with the current settings for an administrator' do
      sign_in(admin)
      enable_admin_mode!(admin)

      get admin_orbit_path

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to include("data-settings-path=\"#{admin_orbit_path(format: :json)}\"")
      expect(response.body).to include('data-auto-index-enabled="false"')
      expect(response.body).to include('data-duo-default-enabled="true"')
      expect(response.body).to include('data-orbit-platform="{&quot;saas&quot;:false}"')
    end

    it 'sends only the platform saas and asks CustomersDot nothing under the trial flow', :request_store do
      sign_in(admin)
      enable_admin_mode!(admin)
      stub_feature_flags(orbit_promo_access_gate: true, orbit_trial: true)
      current_license = ::License.current || build(:license)
      allow(::License).to receive(:current).and_return(current_license)
      allow(current_license).to receive(:online_cloud_license?).and_return(true)
      expect(::Gitlab::SubscriptionPortal::Client).not_to receive(:product_trial)

      get admin_orbit_path

      expect(response.body).to include('data-orbit-platform="{&quot;saas&quot;:false}"')
    end

    it 'opens the page when Orbit is unlicensed, so the admin sees "not available"' do
      sign_in(admin)
      enable_admin_mode!(admin)
      stub_licensed_features(orbit: false)

      get admin_orbit_path

      expect(response).to have_gitlab_http_status(:ok)
      expect(response.body).to include("data-settings-path=\"#{admin_orbit_path(format: :json)}\"")
    end

    it 'returns not found for a non-administrator' do
      sign_in(user)

      get admin_orbit_path

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  describe 'PATCH /admin/orbit' do
    def update_settings(settings)
      patch admin_orbit_path(format: :json), params: { application_setting: settings }, as: :json
    end

    before do
      sign_in(admin)
      enable_admin_mode!(admin)
    end

    it 'updates the DAP default setting and returns the Orbit settings' do
      update_settings(orbit_dap_enabled_by_default: false)

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response).to eq(
        'orbit_auto_index_root_namespace' => false,
        'orbit_dap_enabled_by_default' => false
      )
      expect(ApplicationSetting.current.orbit_dap_enabled_by_default).to be(false)
    end

    it 'updates the auto-index setting' do
      update_settings(orbit_auto_index_root_namespace: true)

      expect(response).to have_gitlab_http_status(:ok)
      expect(ApplicationSetting.current.orbit_auto_index_root_namespace).to be(true)
    end

    it 'does not permit settings outside the Orbit registry' do
      update_settings(orbit_auto_index_root_namespace: false, repository_size_limit: 999_999)

      expect(response).to have_gitlab_http_status(:ok)
      expect(ApplicationSetting.current.repository_size_limit).to eq(0)
    end

    context 'when the update fails' do
      let(:setting) { ApplicationSetting.current_without_cache }

      before do
        allow(ApplicationSetting).to receive(:current_without_cache).and_return(setting)
        allow_next_instance_of(::ApplicationSettings::UpdateService) do |service|
          allow(service).to receive(:execute) do
            setting.errors.add(:base, 'Orbit settings are invalid')
            false
          end
        end
      end

      it 'returns the error message' do
        update_settings(orbit_auto_index_root_namespace: true)

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
        expect(json_response).to eq('message' => 'Orbit settings are invalid')
      end
    end

    it 'returns not found without update access' do
      allow(Ability).to receive(:allowed?).and_call_original
      allow(Ability).to receive(:allowed?)
        .with(admin, :update_knowledge_graph_setting, :global)
        .and_return(false)

      update_settings(orbit_auto_index_root_namespace: true)

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end
end
