# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Analytics::CustomDashboards::SystemDashboardResolver, feature_category: :custom_dashboards_foundation do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }

  let(:slug) { 'dap_impact' }
  let(:args) { { slug: slug } }
  let(:current_user) { user }

  subject(:resolved_dashboard) do
    sync(resolve(described_class, args: args, ctx: { current_user: current_user }))
  end

  describe '#resolve' do
    context 'when the user is authenticated' do
      it 'returns the matching system dashboard' do
        expect(resolved_dashboard).to have_attributes(slug: slug)
      end

      context 'when dap_impact_v1 is disabled' do
        before do
          stub_feature_flags(dap_impact_v1: false)
        end

        it 'creates a resource-not-available graphql error' do
          expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ResourceNotAvailable) do
            resolved_dashboard
          end
        end
      end

      context 'when no dashboard matches the slug' do
        let(:slug) { 'non_existing_slug' }

        it 'returns nil' do
          expect(resolved_dashboard).to be_nil
        end
      end
    end

    context 'when the user is unauthenticated' do
      let(:current_user) { nil }

      it 'creates a resource-not-available graphql error' do
        expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ResourceNotAvailable) do
          resolved_dashboard
        end
      end

      context 'when no dashboard matches the slug' do
        let(:slug) { 'non_existing_slug' }

        it 'returns nil without checking authorization' do
          expect(resolved_dashboard).to be_nil
        end
      end
    end
  end
end
