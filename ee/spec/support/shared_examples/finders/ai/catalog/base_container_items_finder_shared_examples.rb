# frozen_string_literal: true

# Requires the including spec to define:
#   container   - the project or group passed to the finder, from the fixtures below
#   owned_items - items the container itself manages
#   all_items_params - params that return every item the container can enable
#   expected_default_order - the items expected with `all_items_params`, in the default order
RSpec.shared_examples Ai::Catalog::BaseContainerItemsFinder do
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be(:project) { create(:project, developers: user, group: group) }
  let_it_be(:other_project) { create(:project, developers: user) }
  let_it_be(:sibling_project) { create(:project, group: group, developers: user) }

  let_it_be_with_reload(:public_flow) { create(:ai_catalog_flow, :public, project: project) }
  let_it_be_with_reload(:private_agent) { create(:ai_catalog_agent, :private, project: project) }
  let_it_be_with_reload(:private_third_party_flow) do
    create(:ai_catalog_third_party_flow, project: project)
  end

  let_it_be(:deleted_flow) { create(:ai_catalog_flow, :soft_deleted, project: project) }
  let_it_be(:private_flow_of_other_project) do
    create(:ai_catalog_flow, :private, project: other_project)
  end

  let_it_be_with_reload(:public_flow_of_other_project) { create(:ai_catalog_flow, :public, project: other_project) }
  let_it_be(:public_flow_of_other_org) do
    create(:ai_catalog_flow, :public, organization: create(:organization))
  end

  let_it_be(:deleted_public_flow_of_other_project) do
    create(:ai_catalog_flow, :public, :soft_deleted, project: other_project)
  end

  let_it_be_with_reload(:foundational_flow) do
    create(:ai_catalog_flow, :public, verification_level: :gitlab_maintained, organization: project.organization)
  end

  let_it_be_with_reload(:public_flow_of_sibling_project) do
    create(:ai_catalog_flow, :public, project: sibling_project)
  end

  let_it_be(:private_flow_of_sibling_project) do
    create(:ai_catalog_flow, :private, project: sibling_project)
  end

  let_it_be_with_reload(:restricted_agent_in_group) do
    create(:ai_catalog_agent, :restricted, project: sibling_project)
  end

  let_it_be(:restricted_agent_outside_group) do
    create(:ai_catalog_agent, :restricted, project: other_project)
  end

  let(:available_items) do
    [
      foundational_flow,
      restricted_agent_in_group,
      public_flow_of_sibling_project,
      public_flow_of_other_project,
      public_flow
    ]
  end

  let(:expected_items) { (owned_items + available_items).uniq }
  let(:params) { {} }

  subject(:results) { described_class.new(user, container, params: params).execute }

  context 'when user does not have permission to read AI catalog items in the container' do
    let(:params) { all_items_params }

    subject(:results) { described_class.new(create(:user), container, params: params).execute }

    it { is_expected.to be_empty }
  end

  context 'when user can read every item type' do
    it 'does not filter by item type' do
      expect(results.to_sql).not_to include('"item_type"')
    end
  end

  context 'when returning every item the container can enable' do
    let(:params) { all_items_params }

    before do
      project.namespace.reload
    end

    it 'returns owned items, public and restricted items from the same top-level group, and foundational items' do
      is_expected.to match_array(expected_items)
    end

    it 'orders gitlab_maintained items first, then the remaining items by id desc' do
      is_expected.to eq(expected_default_order)
    end

    context 'when the top-level group restricts the AI Catalog to its hierarchy' do
      before do
        group.ai_settings.update!(ai_catalog_restricted_to_group_hierarchy: true)
      end

      it 'returns items within the hierarchy, and foundational items' do
        is_expected.to match_array(expected_items - [public_flow_of_other_project])
      end
    end

    context 'when filtering by `item_types`' do
      let(:params) { super().merge(item_types: %w[flow third_party_flow]) }

      it 'returns the matching items' do
        is_expected.to match_array(expected_items.select { |item| item.flow? || item.third_party_flow? })
      end

      context 'when user cannot read ai catalog flows' do
        before do
          allow(Ability).to receive(:allowed?).and_call_original
          allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_flow, container).and_return(false)
        end

        it 'returns non-flow items only' do
          is_expected.to match_array(expected_items.select(&:third_party_flow?))
        end
      end

      context 'when user cannot read ai catalog third party flows' do
        before do
          allow(Ability).to receive(:allowed?).and_call_original
          allow(Ability).to receive(:allowed?)
            .with(user, :read_ai_catalog_third_party_flow, container).and_return(false)
        end

        it 'returns non-third party flow items only' do
          is_expected.to match_array(expected_items.select(&:flow?))
        end
      end

      context 'when user cannot read any of the requested item types' do
        let(:params) { super().merge(item_types: %w[flow]) }

        before do
          allow(Ability).to receive(:allowed?).and_call_original
          allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_flow, container).and_return(false)
        end

        it { is_expected.to be_empty }
      end

      context 'when item_types is empty' do
        let(:params) { super().merge(item_types: []) }

        it 'returns all items' do
          is_expected.to match_array(expected_items)
        end
      end
    end

    context 'when user cannot read ai catalog flows' do
      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?).with(user, :read_ai_catalog_flow, container).and_return(false)
      end

      it 'returns non-flow items only' do
        is_expected.to match_array(expected_items.reject(&:flow?))
      end
    end

    context 'when user cannot read ai catalog third party flows' do
      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?)
          .with(user, :read_ai_catalog_third_party_flow, container).and_return(false)
      end

      it 'returns non-third party flow items only' do
        is_expected.to match_array(expected_items.reject(&:third_party_flow?))
      end
    end

    context 'when filtering by `search`' do
      let_it_be(:agent_with_name_match) do
        create(:ai_catalog_agent, :public, name: 'Autotriager', project: sibling_project)
      end

      let_it_be(:flow_with_description_match) do
        create(:ai_catalog_flow, :public, project: sibling_project, description: 'Flow to triage issues')
      end

      let(:params) { super().merge(search: 'triage') }

      it 'returns items that partial match on the name or description' do
        is_expected.to contain_exactly(agent_with_name_match, flow_with_description_match)
      end
    end

    context 'when sorting' do
      # Distinct counts, so ordering by the sorted column alone gives the expected order without id tie-breaks.
      before do
        restricted_agent_in_group.update!(star_count: 25, last_30_day_usage_count: 1)
        private_agent.update!(star_count: 20, last_30_day_usage_count: 50)
        public_flow_of_sibling_project.update!(star_count: 15, last_30_day_usage_count: 5)
        foundational_flow.update!(star_count: 10, last_30_day_usage_count: 40)
        public_flow.update!(star_count: 5, last_30_day_usage_count: 10)
        public_flow_of_other_project.update!(star_count: 3, last_30_day_usage_count: 20)
        private_third_party_flow.update!(star_count: 1, last_30_day_usage_count: 30)
      end

      context 'with sort: :star_count_desc' do
        let(:params) { super().merge(sort: :star_count_desc) }

        it 'returns items sorted by star count descending' do
          is_expected.to eq(expected_items.sort_by { |item| -item.star_count })
        end
      end

      context 'with sort: :star_count_asc' do
        let(:params) { super().merge(sort: :star_count_asc) }

        it 'returns items sorted by star count ascending' do
          is_expected.to eq(expected_items.sort_by(&:star_count))
        end
      end

      context 'with sort: :usage_count_desc' do
        let(:params) { super().merge(sort: :usage_count_desc) }

        it 'returns items sorted by usage count descending' do
          is_expected.to eq(expected_items.sort_by { |item| -item.last_30_day_usage_count })
        end
      end

      context 'with sort: :usage_count_asc' do
        let(:params) { super().merge(sort: :usage_count_asc) }

        it 'returns items sorted by usage count ascending' do
          is_expected.to eq(expected_items.sort_by(&:last_30_day_usage_count))
        end
      end
    end
  end
end
