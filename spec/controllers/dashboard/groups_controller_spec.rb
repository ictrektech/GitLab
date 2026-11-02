# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dashboard::GroupsController, feature_category: :groups_and_projects do
  include ExternalAuthorizationServiceHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:current_organization) { user.organization }

  render_views

  before do
    sign_in(user)
  end

  it 'renders group trees' do
    expect(described_class).to include(GroupTree)
  end

  describe '#index' do
    it 'only includes groups the user is a member of' do
      member_of_group = create(:group)
      member_of_group.add_developer(user)
      create(:group, :public)

      get :index

      expect(assigns(:groups)).to contain_exactly(member_of_group)
    end

    context 'when rendering an expanded hierarchy with public groups you are not a member of' do
      let_it_be(:top_level_result) { create(:group, name: 'chef-top', maintainers: user) }
      let_it_be(:top_level_a) { create(:group, name: 'top-a', maintainers: user) }
      let_it_be(:sub_level_result_a) { create(:group, name: 'chef-sub-a', parent: top_level_a) }
      let_it_be(:other_group) { create(:group, name: 'other') }

      it 'renders only groups the user is a member of when searching hierarchy correctly' do
        get :index, params: { filter: 'chef' }, format: :json

        expect(response).to have_gitlab_http_status(:ok)
        all_groups = [top_level_result, top_level_a, sub_level_result_a]
        expect(assigns(:groups)).to match_array(all_groups)
      end
    end

    # Namespace.search defaults to include_parents: false, which the tree relied on when
    # it searched the relation itself. Moving the term into the finder must not widen this
    # to full-path matching.
    describe 'matching semantics' do
      let_it_be(:matching_parent) { create(:group, name: 'chef-parent', owners: user) }
      let_it_be(:unmatching_child) { create(:group, name: 'unrelated', parent: matching_parent) }

      %w[on off].each do |flag_state|
        context "with the advanced finder flag #{flag_state}" do
          before do
            stub_feature_flags(namespaces_advanced_groups_finder: flag_state == 'on')
          end

          it 'does not return a descendant whose own name does not match' do
            get :index, params: { filter: 'chef' }, format: :json

            expect(assigns(:groups)).to include(matching_parent)
            expect(assigns(:groups)).not_to include(unmatching_child)
          end
        end
      end
    end

    describe 'finder selection' do
      # The filter is passed to the finder as `search` so it can be served from
      # Elasticsearch, rather than applied to the relation afterwards by GroupTree.
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

      # namespaces_advanced_groups_finder is already fully enabled, so this flag is the
      # one that actually gates the rollout.
      context 'when group_children_advanced_finder is disabled' do
        let_it_be(:chef_group) { create(:group, name: 'chef-group', owners: user) }
        let_it_be(:other_group) { create(:group, name: 'unrelated', owners: user) }

        before do
          stub_feature_flags(group_children_advanced_finder: false)
        end

        it 'uses GroupsFinder and still filters' do
          expect(::Namespaces::GroupsFinder).not_to receive(:new)

          get :index, params: { filter: 'chef' }, format: :json

          expect(response).to have_gitlab_http_status(:ok)
          expect(assigns(:groups)).to include(chef_group)
          expect(assigns(:groups)).not_to include(other_group)
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
          expect(assigns(:groups).map(&:name)).to all(include('chef').or(eq('top-a')))
        end
      end
    end

    it 'works when the external authorization service is enabled' do
      enable_external_authorization_service_check

      get :index

      expect(response).to have_gitlab_http_status(:ok)
    end

    it_behaves_like 'groups controller with active parameter'
  end
end
