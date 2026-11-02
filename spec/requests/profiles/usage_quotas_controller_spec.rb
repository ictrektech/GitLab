# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Profiles::UsageQuotasController, feature_category: :consumables_cost_management do
  let_it_be(:user) { create(:user, :with_namespace) }

  describe 'GET /-/profile/usage_quotas' do
    context 'when signed in' do
      before do
        sign_in(user)
      end

      it 'renders usage quota page', :aggregate_failures do
        get profile_usage_quotas_path

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to have_css('#js-storage-usage-app')
      end
    end

    context 'when signed out' do
      it 'redirects to the sign in page' do
        get profile_usage_quotas_path

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
