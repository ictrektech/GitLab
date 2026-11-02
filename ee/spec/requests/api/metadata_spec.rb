# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Metadata, feature_category: :api do
  let_it_be(:user) { create(:user) }

  shared_examples_for 'exposing the instance plan' do
    before do
      allow(::License).to receive(:current).and_return(license)
    end

    context 'when the instance runs under a license' do
      let(:license) { build(:license, plan: ::License::ULTIMATE_PLAN) }

      it 'reports the plan to a caller who is not an administrator' do
        expect(user).not_to be_admin

        get api(endpoint, user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['plan']).to eq(::License::ULTIMATE_PLAN)
      end
    end

    context 'when the instance has no license' do
      let(:license) { nil }

      it 'reports the free plan' do
        get api(endpoint, user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['plan']).to eq('free')
      end
    end

    context 'when subscriptions are held per namespace', :saas_gitlab_com_subscriptions do
      let(:license) { build(:license, plan: ::License::ULTIMATE_PLAN) }

      it 'reports no plan rather than one the caller could read as their own' do
        get api(endpoint, user)

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response).to have_key('plan')
        expect(json_response['plan']).to be_nil
      end
    end
  end

  describe 'GET /metadata' do
    let(:endpoint) { '/metadata' }

    it_behaves_like 'exposing the instance plan'
  end

  describe 'GET /version' do
    let(:endpoint) { '/version' }

    it_behaves_like 'exposing the instance plan'
  end
end
