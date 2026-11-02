# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::BoardsController, feature_category: :planning_views do
  let_it_be(:project) { create(:project) }
  let_it_be(:user)    { create(:user, maintainer_of: project) }

  before do
    sign_in(user)
  end

  describe 'GET index' do
    subject(:request) { get project_boards_path(project) }

    context 'when self-hosted with correct license' do
      before do
        stub_licensed_features(wip_limits: true)
      end

      it 'pushes wip limits to frontend' do
        request

        expect(response.body).to include('"wipLimits":true')
      end
    end

    context 'on .com', :saas do
      before do
        enable_namespace_license_check!
      end

      context 'for group with correct plan' do
        before do
          create(:gitlab_subscription, namespace: project.namespace, hosted_plan: create(:bronze_plan))
        end

        it 'pushes wip limits to frontend' do
          request

          expect(response.body).to include('"wipLimits":true')
        end
      end

      context 'for group with incorrect or no plan' do
        it 'does not push wip limits to frontend', :aggregate_failures do
          request

          expect(response).to have_gitlab_http_status(:ok)
          expect(response.body).not_to include('wipLimits')
        end
      end
    end
  end
end
