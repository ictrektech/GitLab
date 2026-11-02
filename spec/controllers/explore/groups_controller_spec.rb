# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Explore::GroupsController, feature_category: :groups_and_projects do
  let_it_be(:user) { create(:user) }

  before do
    sign_in(user)
  end

  describe '#index' do
    describe 'finder selection' do
      let_it_be(:matching_group) { create(:group, :public, name: 'chef-public') }
      let_it_be(:unmatching_child) { create(:group, :public, name: 'unrelated', parent: matching_group) }

      context 'when the advanced finder flag is enabled' do
        before do
          stub_feature_flags(namespaces_advanced_groups_finder: true)
        end

        it 'uses Namespaces::GroupsFinder and passes the filter as search' do
          expect(::Namespaces::GroupsFinder).to receive(:new)
            .with(user, hash_including(search: 'chef', search_include_parents: false))
            .and_call_original

          get :index, params: { filter: 'chef' }, format: :json

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when the advanced finder flag is disabled' do
        before do
          stub_feature_flags(namespaces_advanced_groups_finder: false)
        end

        it 'uses GroupsFinder and still filters' do
          expect(::Namespaces::GroupsFinder).not_to receive(:new)

          get :index, params: { filter: 'chef' }, format: :json

          expect(response).to have_gitlab_http_status(:ok)
          expect(assigns(:groups)).to include(matching_group)
        end
      end

      # Namespace.search defaults to include_parents: false, which the tree relied on.
      %w[on off].each do |flag_state|
        context "with matching semantics and the flag #{flag_state}" do
          before do
            stub_feature_flags(namespaces_advanced_groups_finder: flag_state == 'on')
          end

          it 'does not return a descendant whose own name does not match' do
            get :index, params: { filter: 'chef' }, format: :json

            expect(assigns(:groups)).not_to include(unmatching_child)
          end
        end
      end
    end

    context 'when html format' do
      render_views

      it 'renders index template' do
        get :index

        expect(response).to render_template('explore/groups/index')
      end
    end

    context 'when json format' do
      it 'only includes public and internal groups', :aggregate_failures do
        private_group = create(:group, :private, developers: [user])
        internal_group = create(:group, :internal)
        public_group = create(:group, :public)

        get :index, format: :json

        expect(response).to have_gitlab_http_status(:ok)

        group_ids = json_response.pluck('id')
        expect(group_ids).to include(internal_group.id, public_group.id)
        expect(group_ids).not_to include(private_group.id)
      end

      it_behaves_like 'groups controller with active parameter'
    end

    context 'when restricted visibility level is public' do
      before do
        sign_out(user)

        stub_application_setting(restricted_visibility_levels: [Gitlab::VisibilityLevel::PUBLIC])
      end

      it 'redirects to login page' do
        get :index

        expect(response).to redirect_to new_user_session_path
      end
    end
  end
end
