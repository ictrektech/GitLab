# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Admin::SubscriptionsController, :cloud_licenses, feature_category: :seat_cost_management do
  include AdminModeHelper

  describe 'GET /subscriptions' do
    context 'when the user is not admin' do
      let_it_be(:user) { create(:user) }

      it 'responds with 404' do
        sign_in(user)

        send_request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the user an admin' do
      let_it_be(:admin) { create(:admin) }

      before do
        login_as(admin)
        enable_admin_mode!(admin)
      end

      it 'renders the Activation Form' do
        send_request

        expect(response).to render_template(:show)
        expect(response.body).to include('js-show-subscription-page')
      end
    end
  end

  describe 'GET /admin/subscription/billable_usage', :enable_admin_mode,
    feature_category: :consumables_cost_management do
    let_it_be(:admin) { create(:admin) }

    subject(:show_report) { get billable_usage_admin_subscription_path }

    before do
      sign_in(admin)
      stub_feature_flags(billable_usage_export: true)
      allow_next_instance_of(::Gitlab::BillingEvents::Client) do |client|
        allow(client).to receive(:local_persistence_enabled?).and_return(true)
      end
    end

    context 'without a current license' do
      before do
        allow(License).to receive(:current).and_return(nil)
      end

      it 'redirects to the license settings' do
        show_report

        expect(response).to redirect_to(general_admin_application_settings_path)
      end
    end

    context 'with a current license' do
      let_it_be(:license) do
        create_current_license(cloud_licensing_enabled: true, offline_cloud_licensing_enabled: true)
      end

      it 'renders the report page' do
        show_report

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to include('js-billable-usage-report')
      end

      context 'with the feature flag disabled' do
        before do
          stub_feature_flags(billable_usage_export: false)
        end

        it 'returns not found' do
          show_report

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when the instance does not persist billable usage locally' do
        before do
          allow_next_instance_of(::Gitlab::BillingEvents::Client) do |client|
            allow(client).to receive(:local_persistence_enabled?).and_return(false)
          end
        end

        it 'returns not found' do
          show_report

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when the user is not an admin' do
        let_it_be(:user) { create(:user) }

        before do
          sign_in(user)
        end

        it 'returns not found' do
          show_report

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end
  end

  def send_request
    get admin_subscription_path
  end
end
