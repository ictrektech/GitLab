# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Query single custom system dashboard', feature_category: :custom_dashboards_foundation do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }

  let(:slug) { 'duo_and_sdlc_trends' }
  let(:config) { { 'title' => 'Duo and SDLC trends', 'version' => '2', 'panels' => [] } }
  let(:dashboard) do
    Analytics::CustomDashboards::SystemDashboard.new(slug: slug, config: config)
  end

  let(:fields) do
    <<~GRAPHQL
      id
      name
      description
      slug
      system
      config
    GRAPHQL
  end

  let(:query) do
    graphql_query_for(:custom_system_dashboard, { slug: slug }, fields)
  end

  subject(:execute_query) do
    post_graphql(query, current_user: current_user)
  end

  before do
    allow(Analytics::CustomDashboards::SystemDashboardsLoader)
      .to receive(:find_by_slug).with(slug).and_return(dashboard)
  end

  context 'when the user is authenticated' do
    it 'returns the dashboard for the given slug' do
      execute_query

      expect(graphql_data_at(:custom_system_dashboard)).to include(
        'name' => 'Duo and SDLC trends',
        'slug' => slug,
        'system' => true,
        'config' => config
      )
    end
  end

  context 'when the dashboard failed schema validation' do
    let(:fields) { 'slug errors' }
    let(:dashboard) do
      Analytics::CustomDashboards::SystemDashboard.new(
        slug: slug, config: { 'panels' => [] }, errors: ['root is missing required keys: title']
      )
    end

    it 'returns the errors' do
      execute_query

      expect(graphql_data_at(:custom_system_dashboard, :errors)).to eq(['root is missing required keys: title'])
    end
  end

  context 'when the dashboard is valid' do
    let(:fields) { 'errors' }

    it 'returns null errors' do
      execute_query

      expect(graphql_data_at(:custom_system_dashboard)).to eq({ 'errors' => nil })
    end
  end

  context 'when the user is anonymous' do
    let(:current_user) { nil }

    it 'returns nil' do
      execute_query

      expect(graphql_data_at(:custom_system_dashboard)).to be_nil
    end
  end

  context 'when the dashboard is gated by a feature flag enabled for a root group' do
    let_it_be(:enabled_group) { create(:group) }

    let(:config) { super().merge('constraints' => { 'feature_flag' => 'dap_impact_v1' }) }

    before do
      stub_feature_flags(dap_impact_v1: enabled_group)
    end

    context 'when the user is a member of the root group' do
      before_all do
        enabled_group.add_reporter(current_user)
      end

      it 'returns the dashboard' do
        execute_query

        expect(graphql_data_at(:custom_system_dashboard)).to include('slug' => slug)
      end
    end

    context 'when the user is not a member of the root group' do
      it 'returns a not-authorized error' do
        execute_query

        expect(graphql_data_at(:custom_system_dashboard)).to be_nil
        expect_graphql_errors_to_include(Gitlab::Graphql::Authorize::AuthorizeResource::RESOURCE_ACCESS_ERROR)
      end
    end
  end

  context 'when no dashboard matches the slug' do
    let(:dashboard) { nil }

    it 'returns nil' do
      execute_query

      expect(graphql_data_at(:custom_system_dashboard)).to be_nil
    end
  end
end
