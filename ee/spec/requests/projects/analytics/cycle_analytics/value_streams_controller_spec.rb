# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::Analytics::CycleAnalytics::ValueStreamsController, feature_category: :value_stream_management do
  let_it_be(:user) { create(:user) }
  let_it_be(:another_user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be_with_refind(:project) { create(:project, namespace: group) }
  let_it_be(:namespace) { project.project_namespace }

  let(:path_prefix) { %i[namespace project] }
  let(:params) { { namespace_id: group.to_param, project_id: project.to_param } }
  let(:license_name) { :cycle_analytics_for_projects }

  it_behaves_like 'value stream controller actions' do
    describe 'GET index' do
      subject(:request) { get path_for(%i[analytics cycle_analytics value_streams]) }

      context 'when user is member of the project' do
        context 'when not licensed' do
          before do
            stub_licensed_features(license_name => false)
          end

          it 'succeeds and returns the default value stream' do
            request

            expect(response).to have_gitlab_http_status(:ok)
            expect(json_response.size).to eq(1)
            expect(json_response.first['id']).to eq('default')
          end
        end
      end
    end

    context 'when the project has lower visibility level' do
      subject(:request) { delete path_for(value_streams.first) }

      before do
        project.update!(visibility_level: Project::PUBLIC)
      end

      it 'disallows deleting the record' do
        login_as(another_user)

        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  context 'when the project is in a personal namespace' do
    let_it_be(:owner) { create(:user, :with_namespace) }
    let_it_be(:personal_project) { create(:project, namespace: owner.namespace) }
    let_it_be(:value_stream) do
      create(:cycle_analytics_value_stream, namespace: personal_project.project_namespace)
    end

    let(:path_params) { { namespace_id: owner.namespace.to_param, project_id: personal_project.to_param } }

    before do
      stub_licensed_features(license_name => true)
      login_as(owner)
    end

    def vsa_settings_app
      Nokogiri::HTML.parse(response.body).at_css('#js-vsa-settings-app')
    end

    it 'renders the new page without a group path' do
      get new_namespace_project_analytics_cycle_analytics_value_stream_path(**path_params)

      expect(response).to have_gitlab_http_status(:ok)
      expect(vsa_settings_app['data-full-path']).to eq(personal_project.full_path)
      expect(vsa_settings_app['data-group-path']).to be_nil
    end

    it 'renders the edit page without a group path' do
      get edit_namespace_project_analytics_cycle_analytics_value_stream_path(**path_params, id: value_stream)

      expect(response).to have_gitlab_http_status(:ok)
      expect(vsa_settings_app['data-full-path']).to eq(personal_project.full_path)
      expect(vsa_settings_app['data-group-path']).to be_nil
    end
  end
end
