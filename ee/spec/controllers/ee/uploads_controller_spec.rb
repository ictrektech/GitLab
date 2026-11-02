# frozen_string_literal: true

require 'spec_helper'

RSpec.describe UploadsController, feature_category: :system_access do
  let!(:user) { create(:user) }
  let!(:project) { create(:project) }

  describe "GET show" do
    context 'when viewing issuable metric images' do
      let(:incident) { create(:incident, project: project) }
      let(:metric_image) { create(:issuable_metric_image, issue: incident) }

      before do
        project.add_developer(user)
        sign_in(user)
      end

      it "responds with status 200" do
        get :show, params: { model: "issuable_metric_image", mounted_as: 'file', id: metric_image.id, filename: metric_image.filename }

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when viewing issuable metric images in a public project without membership' do
      let_it_be(:public_project) { create(:project, :public) }
      let(:metric_image) { create(:issuable_metric_image, issue: incident) }

      subject(:get_metric_image) do
        get :show, params: { model: "issuable_metric_image", mounted_as: 'file', id: metric_image.id, filename: metric_image.filename }
      end

      context 'when the incident is public' do
        let(:incident) { create(:incident, project: public_project) }

        it 'responds with status 200 to an anonymous user' do
          get_metric_image

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when the incident is confidential' do
        let(:incident) { create(:incident, :confidential, project: public_project) }

        it 'responds with status 401 to an anonymous user' do
          get_metric_image

          expect(response).to have_gitlab_http_status(:unauthorized)
        end

        it 'responds with status 404 to a signed in non-member' do
          sign_in(user)

          get_metric_image

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when issues are only visible to project members' do
        let_it_be(:public_project) { create(:project, :public, :issues_private) }
        let(:incident) { create(:incident, project: public_project) }

        it 'responds with status 401 to an anonymous user' do
          get_metric_image

          expect(response).to have_gitlab_http_status(:unauthorized)
        end

        it 'responds with status 404 to a signed in non-member' do
          sign_in(user)

          get_metric_image

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end
  end
end
