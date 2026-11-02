# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onboarding::FeatureLibraryController, feature_category: :onboarding do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, developers: user) }

  describe 'GET /-/onboarding/feature_library/ai_search', :saas, :clean_gitlab_redis_rate_limiting do
    let_it_be(:gitlab_subscription) do
      create(:gitlab_subscription, :active_trial, :ultimate_trial, namespace: group, trial_ends_on: Date.tomorrow)
    end

    before do
      sign_in(user)
    end

    context 'when AI search is available for the namespace' do
      before do
        allow_next_instance_of(Gitlab::Llm::AiGateway::Completions::FeatureDiscoverySearch) do |completion|
          allow(completion).to receive(:execute).and_return(%w[group_merge_request_list])
        end
      end

      it 'returns the AI Gateway matched ids and ai_search_available: true', :aggregate_failures do
        get onboarding_feature_library_ai_search_path,
          params: { query: 'completelyrandom', panel: 'group', resource_id: group.id }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['ids']).to eq(%w[group_merge_request_list])
        expect(json_response['ai_search_available']).to be(true)
      end
    end

    context 'when the query exceeds MAX_QUERY_LENGTH' do
      let(:long_query) { 'x' * (described_class::MAX_QUERY_LENGTH + 50) }

      before do
        allow_next_instance_of(Gitlab::Llm::AiGateway::Completions::FeatureDiscoverySearch) do |completion|
          allow(completion).to receive(:execute).and_return([])
        end
      end

      it 'truncates the query before handing it to the AI Gateway completion' do
        expect(Gitlab::Llm::AiGateway::Completions::FeatureDiscoverySearch)
          .to receive(:new)
          .with(anything, anything, a_hash_including(query: 'x' * described_class::MAX_QUERY_LENGTH))

        get onboarding_feature_library_ai_search_path,
          params: { query: long_query, panel: 'group', resource_id: group.id }

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when AI search is not available for the namespace' do
      it 'returns an empty ids array and ai_search_available: false without calling the AI Gateway',
        :aggregate_failures do
        expect(Gitlab::Llm::AiGateway::Completions::FeatureDiscoverySearch).not_to receive(:new)

        get onboarding_feature_library_ai_search_path, params: { query: 'completelyrandom', panel: 'group' }

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['ids']).to eq([])
        expect(json_response['ai_search_available']).to be(false)
      end
    end

    context 'when the feature_discovery_gemini_search flag is disabled' do
      before do
        stub_feature_flags(feature_discovery_gemini_search: false)
      end

      it 'returns 404' do
        get onboarding_feature_library_ai_search_path,
          params: { query: 'completelyrandom', panel: 'group', resource_id: group.id }

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the rate limit is exceeded' do
      before do
        allow(Gitlab::ApplicationRateLimiter)
          .to receive(:throttled_request?)
          .with(anything, anything, :feature_library_ai_search, scope: { user: user })
          .and_return(true)
      end

      it 'returns 429 with a JSON error message', :aggregate_failures do
        get onboarding_feature_library_ai_search_path,
          params: { query: 'completelyrandom', panel: 'group', resource_id: group.id }

        expect(response).to have_gitlab_http_status(:too_many_requests)
        expect(json_response['error']).to be_present
      end
    end
  end

  describe 'GET /-/onboarding/feature_library/catalog' do
    let_it_be(:owner) { create(:user) }
    let_it_be(:owned_group) { create(:group, owners: owner, developers: user) }
    let_it_be(:project) { create(:project, group: owned_group) }

    let(:params) { { panel: 'project', resource_id: project.id } }
    let(:current_user) { owner }

    subject(:request) { get onboarding_feature_library_catalog_path, params: params }

    before do
      sign_in(current_user)
    end

    def plans
      json_response['pages'].map { |page| page['plan'] }
    end

    def ctas
      json_response['pages'].to_h { |page| [page['plan'], page['cta']&.dig('type')] }
    end

    context 'on GitLab.com', :saas_gitlab_com_subscriptions do
      before do
        allow_next_instance_of(GitlabSubscriptions::FetchSubscriptionPlansService) do |service|
          allow(service).to receive(:execute).and_return([Hashie::Mash.new(id: 'ultimate-id', code: 'ultimate')])
        end
      end

      it 'returns both pages with upgrade CTAs for a Free group owner', :aggregate_failures do
        request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['current_plan_context']).to include(
          'edition' => 'ee', 'deployment' => 'saas', 'current_plan' => 'free', 'base_plan' => 'free', 'trial' => false
        )
        expect(plans).to eq(%w[premium ultimate])
        expect(ctas).to eq('premium' => 'upgrade', 'ultimate' => 'upgrade')
      end

      it 'includes the compute minutes highlight' do
        request

        expect(json_response['pages'].first['highlights'].pluck('id')).to include('compute_minutes_premium')
      end

      context 'with an active Ultimate trial' do
        before do
          create(:gitlab_subscription, :active_trial, :ultimate_trial, namespace: owned_group)
        end

        it 'compares against Free and returns both pages', :aggregate_failures do
          request

          expect(json_response['current_plan_context']).to include(
            'current_plan' => 'ultimate', 'base_plan' => 'free', 'trial' => true
          )
          expect(plans).to eq(%w[premium ultimate])
        end
      end

      context 'with a Premium subscription' do
        before do
          create(:gitlab_subscription, :premium, namespace: owned_group)
        end

        it 'returns only the Ultimate page with the in-place upgrade', :aggregate_failures do
          request

          expect(plans).to eq(%w[ultimate])
          expect(ctas).to eq('ultimate' => 'upgrade')
          expect(json_response['pages'].first['cta']['url']).to include("/gitlab/namespaces/#{owned_group.id}/upgrade/")
        end

        it 'compares compute minutes against Premium' do
          request

          highlights = json_response['pages'].first['highlights']
          highlight = highlights.find { |item| item['id'] == 'compute_minutes_ultimate' }

          expect(highlight['description'])
            .to eq('Get 50,000 compute minutes a month, up from 10,000 minutes on Premium')
        end
      end

      context 'with an Ultimate subscription' do
        before do
          create(:gitlab_subscription, :ultimate, namespace: owned_group)
        end

        it 'returns no pages' do
          request

          expect(plans).to eq([])
        end
      end

      context 'when the viewer is not an owner' do
        let(:current_user) { user }

        it 'returns the pages without a CTA' do
          request

          expect(ctas).to eq('premium' => nil, 'ultimate' => nil)
        end
      end
    end

    context 'on self-managed', :enable_admin_mode do
      let_it_be(:admin) { create(:admin) }

      let(:current_user) { admin }

      before do
        allow(License).to receive_messages(current: nil, billable_license: nil)
      end

      it 'returns both pages with purchase CTAs for an admin without a license', :aggregate_failures do
        request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['current_plan_context']).to include(
          'deployment' => 'self_managed', 'current_plan' => 'free', 'base_plan' => 'free'
        )
        expect(plans).to eq(%w[premium ultimate])
        expect(ctas).to eq('premium' => 'upgrade', 'ultimate' => 'upgrade')
      end

      it 'leaves out the compute minutes highlights' do
        request

        expect(json_response['pages'].flat_map { |page| page['highlights'] }.map { |item| item['id'] })
          .not_to include('compute_minutes_premium', 'compute_minutes_ultimate')
      end

      context 'with a Premium cloud license' do
        let(:license) { build_stubbed(:license, cloud: true, plan: License::PREMIUM_PLAN) }

        before do
          allow(license).to receive_messages(trial?: false, expired?: false, subscription_name: 'A-S00012345')
          allow(License).to receive_messages(current: license, billable_license: license)
        end

        it 'returns only the Ultimate page with the subscription upgrade', :aggregate_failures do
          request

          expect(plans).to eq(%w[ultimate])
          expect(json_response['pages'].first['cta']).to include('type' => 'upgrade')
          expect(json_response['pages'].first['cta']['url']).to include('/subscriptions/A-S00012345/upgrade/new')
        end
      end

      context 'when the viewer is not an admin' do
        let(:current_user) { owner }

        it 'returns the pages without a CTA' do
          request

          expect(ctas).to eq('premium' => nil, 'ultimate' => nil)
        end
      end
    end
  end

  describe 'GET /-/onboarding/feature_library/catalog access and payload', :clean_gitlab_redis_rate_limiting do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:private_project) { create(:project, :private) }

    let(:params) { { panel: 'project', resource_id: project.id } }

    subject(:request) { get onboarding_feature_library_catalog_path, params: params }

    before do
      sign_in(user)
      # The EE test license is Ultimate, which has no pages. Pin a Free viewer so the shape is asserted;
      # the plan context is covered by its own specs.
      allow_next_instance_of(Onboarding::FeatureLibrary::CurrentPlanContext) do |plan_context|
        allow(plan_context).to receive_messages(base_plan: :free, tier_pages: %i[premium ultimate])
      end
    end

    it 'returns the plan context and both pages', :aggregate_failures do
      request

      expect(response).to have_gitlab_http_status(:ok)
      expect(json_response['current_plan_context']).to include('current_plan', 'base_plan', 'deployment', 'trial')
      expect(json_response['pages'].map { |page| page['plan'] }).to eq(%w[premium ultimate])
      expect(json_response['pages']).to all(include('plan', 'cta', 'highlights', 'credits', 'categories'))
    end

    it 'serializes items with the contract keys', :aggregate_failures do
      request

      item = json_response['pages'].first['categories'].first['items'].first

      expect(item.keys).to contain_exactly('id', 'source', 'title', 'description', 'icon', 'docs_url', 'label')
      expect(item['source']).to eq('nav_item')
      expect(item['docs_url']).to start_with('/help/')
      expect(item['label']).to include('type' => be_in(%w[new enhanced add_on]), 'plan' => 'premium')
    end

    context 'with a group panel' do
      let(:params) { { panel: 'group', resource_id: group.id } }

      it 'returns the group pages' do
        request

        expect(response).to have_gitlab_http_status(:ok)
        expect(json_response['pages'].map { |page| page['plan'] }).to eq(%w[premium ultimate])
      end
    end

    context 'when the flag is enabled for a different root namespace' do
      before do
        stub_feature_flags(feature_catalog_explore_pages: create(:group))
      end

      it 'returns 404' do
        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the resource is missing' do
      let(:params) { { panel: 'project' } }

      it 'returns 404' do
        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the user cannot read the resource' do
      let(:params) { { panel: 'project', resource_id: private_project.id } }

      it 'returns 404' do
        request

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end

    context 'when the user can read the resource but is not a member' do
      let_it_be(:public_group) { create(:group, :public) }
      let_it_be(:public_project) { create(:project, :public, group: public_group) }

      where(:panel, :resource) do
        'group'   | ref(:public_group)
        'project' | ref(:public_project)
      end

      with_them do
        let(:params) { { panel: panel, resource_id: resource.id } }

        it 'returns 404' do
          request

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when the user is an admin', :enable_admin_mode do
        let_it_be(:admin) { create(:admin) }
        let(:params) { { panel: 'group', resource_id: public_group.id } }

        before do
          sign_in(admin)
        end

        it 'returns the pages' do
          request

          expect(response).to have_gitlab_http_status(:ok)
        end
      end
    end

    context 'with an invalid panel' do
      let(:params) { { panel: 'invalid', resource_id: project.id } }

      it 'returns 422' do
        request

        expect(response).to have_gitlab_http_status(:unprocessable_entity)
      end
    end
  end
end
