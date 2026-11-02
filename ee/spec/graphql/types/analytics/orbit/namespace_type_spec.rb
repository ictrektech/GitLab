# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Analytics::Orbit::NamespaceType, feature_category: :knowledge_graph do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }

  before do
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_promo_access_gate: false)
    stub_config(knowledge_graph: { 'enabled' => true })
  end

  specify { expect(described_class.graphql_name).to eq('OrbitNamespace') }

  it 'exposes the Orbit fields' do
    expect(described_class).to have_graphql_fields(
      :access, :enabled, :enabled_at, :indexing, :indexing_status, :item_counts, :trial
    )
  end

  describe '#enabled' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }

    it 'returns whether Orbit is on for a group' do
      expect(batch_sync { resolve_field(:enabled, group, current_user: user) }).to be(false)

      create(:knowledge_graph_enabled_namespace, namespace: group)

      expect(batch_sync { resolve_field(:enabled, group, current_user: user) }).to be(true)
    end

    it 'returns whether Orbit is on for the top-level group of a subgroup' do
      subgroup = create(:group, parent: group)

      expect(batch_sync { resolve_field(:enabled, subgroup, current_user: user) }).to be(false)

      create(:knowledge_graph_enabled_namespace, namespace: group)

      expect(batch_sync { resolve_field(:enabled, subgroup, current_user: user) }).to be(true)
    end

    it 'returns nil for a project' do
      expect(resolve_field(:enabled, project, current_user: user)).to be_nil
    end
  end

  describe '#enabled_at' do
    context 'when Orbit indexing is enabled' do
      let_it_be(:group) { create(:group) }
      let_it_be(:enabled_namespace) { create(:knowledge_graph_enabled_namespace, namespace: group) }

      it 'returns when indexing was enabled' do
        expect(batch_sync { resolve_field(:enabled_at, group, current_user: user) })
          .to be_like_time(enabled_namespace.created_at)
      end

      it 'returns nil when Orbit is not available to the user' do
        stub_licensed_features(orbit: false)

        expect(resolve_field(:enabled_at, group, current_user: user)).to be_nil
      end
    end

    context 'when Orbit is not enabled' do
      let_it_be(:group) { create(:group) }

      it 'returns nil' do
        expect(batch_sync { resolve_field(:enabled_at, group, current_user: user) }).to be_nil
      end
    end

    context 'for a subgroup and a project of a group with Orbit on' do
      let_it_be(:group) { create(:group) }
      let_it_be(:subgroup) { create(:group, parent: group) }
      let_it_be(:project) { create(:project, group: group) }

      let_it_be(:enabled_namespace) { create(:knowledge_graph_enabled_namespace, namespace: group) }

      it 'returns when Orbit was turned on for the top-level group of the subgroup' do
        expect(batch_sync { resolve_field(:enabled_at, subgroup, current_user: user) })
          .to be_like_time(enabled_namespace.created_at)
      end

      it 'returns nil for a project' do
        expect(resolve_field(:enabled_at, project, current_user: user)).to be_nil
      end
    end
  end
end
