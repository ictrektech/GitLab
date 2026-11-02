# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Group.aiCatalogItems', :with_current_organization, feature_category: :ai_catalog_curation do
  include Ai::Catalog::TestHelpers
  include GraphqlHelpers

  let_it_be(:reporter_user) { create(:user) }
  let_it_be(:developer_user) { create(:user) }
  let_it_be(:group) { create(:group, developers: developer_user, reporters: reporter_user) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:other_project) { create(:project) }

  let_it_be_with_reload(:public_flow) { create(:ai_catalog_flow, :public, project: project) }
  let_it_be_with_reload(:restricted_agent) { create(:ai_catalog_agent, :restricted, project: project) }
  let_it_be(:private_agent) { create(:ai_catalog_agent, :private, project: project) }

  let_it_be_with_reload(:public_agent_of_other_project) do
    create(:ai_catalog_agent, :public, project: other_project)
  end

  let_it_be(:restricted_agent_of_other_project) { create(:ai_catalog_agent, :restricted, project: other_project) }

  let(:current_user) { developer_user }
  let(:args) { {} }

  let(:nodes) { graphql_data_at(:group, :ai_catalog_items, :nodes) }

  let(:query) do
    graphql_query_for(
      :group,
      { full_path: group.full_path },
      query_graphql_field(
        :ai_catalog_items,
        attributes_to_graphql(args).to_s,
        query_graphql_field(:nodes, {}, all_graphql_fields_for('AiCatalogItem'))
      )
    )
  end

  subject(:execute_query) { post_graphql(query, current_user: current_user) }

  shared_examples 'returns success' do
    it 'returns success' do
      execute_query
      expect(response).to have_gitlab_http_status(:success)
    end
  end

  before do
    enable_ai_catalog
  end

  context 'without filters' do
    it_behaves_like 'returns success'

    it 'returns the public and restricted items the group can enable' do
      execute_query

      expect(nodes).to contain_exactly(
        a_graphql_entity_for(public_flow),
        a_graphql_entity_for(restricted_agent),
        a_graphql_entity_for(public_agent_of_other_project)
      )
    end
  end

  context 'when filtering by `enabled_by`' do
    before_all do
      create(:ai_catalog_item_consumer, :inheritance, group: group, item: public_flow)
      create(:ai_catalog_item_consumer, project: project, item: restricted_agent)
    end

    context 'when `enabled_by` is `INHERITANCE`' do
      let(:args) { { enabled_by: [:INHERITANCE] } }

      it_behaves_like 'returns success'

      it 'returns items enabled through group inheritance' do
        execute_query

        expect(nodes).to contain_exactly(a_graphql_entity_for(public_flow))
      end

      context 'when the ai_catalog_group_inherited_consumers feature flag is disabled' do
        before do
          stub_feature_flags(ai_catalog_group_inherited_consumers: false)
        end

        it 'returns no items' do
          execute_query

          expect(nodes).to be_empty
        end
      end
    end

    context 'when `enabled_by` is `PROJECT_DIRECT`' do
      let(:args) { { enabled_by: [:PROJECT_DIRECT] } }

      it 'returns items enabled directly in projects in the group' do
        execute_query

        expect(nodes).to contain_exactly(a_graphql_entity_for(restricted_agent))
      end
    end

    context 'when `enabled_by` is `INHERITANCE` and `PROJECT_DIRECT`' do
      let(:args) { { enabled_by: [:INHERITANCE, :PROJECT_DIRECT] } }

      it 'returns items enabled in either way' do
        execute_query

        expect(nodes).to contain_exactly(
          a_graphql_entity_for(public_flow),
          a_graphql_entity_for(restricted_agent)
        )
      end
    end
  end

  context 'when user is a reporter of the group' do
    let(:current_user) { reporter_user }

    it_behaves_like 'returns success'

    it 'returns no items' do
      execute_query

      expect(nodes).to be_empty
    end
  end

  context 'when user is not a member of the group' do
    let(:current_user) { create(:user) }

    it_behaves_like 'returns success'

    it 'returns no items' do
      execute_query

      expect(nodes).to be_empty
    end
  end

  context 'when filtering by `item_types`' do
    let(:args) { super().merge(item_types: [:AGENT]) }

    it 'returns only agents' do
      execute_query

      expect(nodes).to contain_exactly(
        a_graphql_entity_for(restricted_agent),
        a_graphql_entity_for(public_agent_of_other_project)
      )
    end
  end

  context 'when filtering by `search`' do
    let(:args) { super().merge(search: 'triage') }

    let_it_be(:issue_label_agent) do
      create(:ai_catalog_agent, :public, name: 'Autotriager', project: project)
    end

    let_it_be(:mr_review_flow) do
      create(:ai_catalog_flow, :public, project: project, description: 'Flow to triage issues')
    end

    it 'returns items matching name or description' do
      execute_query

      expect(nodes).to contain_exactly(
        a_graphql_entity_for(issue_label_agent),
        a_graphql_entity_for(mr_review_flow)
      )
    end
  end

  context 'when sorting' do
    let(:args) { super().merge(sort: :STAR_COUNT_DESC) }

    before do
      public_flow.update!(star_count: 5)
      restricted_agent.update!(star_count: 20)
      public_agent_of_other_project.update!(star_count: 10)
    end

    it 'returns items in the requested order' do
      execute_query

      expect(nodes).to match([
        a_graphql_entity_for(restricted_agent),
        a_graphql_entity_for(public_agent_of_other_project),
        a_graphql_entity_for(public_flow)
      ])
    end
  end
end
