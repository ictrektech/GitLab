# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Admin::RolePromotionRequestsController, :enable_admin_mode, feature_category: :seat_cost_management do
  let(:admin) { create(:admin) }

  let_it_be(:license) { create(:license, plan: License::ULTIMATE_PLAN) }
  let(:feature_settings) { true }

  before do
    stub_application_setting(enable_member_promotion_management: feature_settings)
    allow(License).to receive(:current).and_return(license)
    sign_in(admin)
  end

  describe 'GET #index' do
    context 'when member promotion management is enabled' do
      it 'renders the index template' do
        get admin_role_promotion_requests_path

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to have_css('#js-admin-users-role-promotion-requests-app')
      end
    end
  end
end
