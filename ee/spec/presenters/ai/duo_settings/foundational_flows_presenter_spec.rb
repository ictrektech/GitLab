# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoSettings::FoundationalFlowsPresenter, :aggregate_failures, feature_category: :duo_agent_platform do
  subject(:presenter) { described_class.new(group) }

  let(:listed_references) { presenter.listed_flows.map(&:foundational_flow_reference) }

  # rubocop:disable RSpec/FactoryBot/AvoidCreate -- the presenter reads persisted flow selections
  let_it_be(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }
  let_it_be(:flow) { create(:ai_catalog_item, :with_foundational_flow_reference, :public) }

  before_all do
    create(:ai_catalog_enabled_foundational_flow, :for_namespace, namespace: root_group, catalog_item: flow)
  end
  # rubocop:enable RSpec/FactoryBot/AvoidCreate

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
  end

  context 'for a top-level group' do
    let(:group) { root_group }

    it 'lists every available flow and its own selection' do
      expect(presenter.readiness_card_enabled?).to be(true)
      expect(listed_references).to include('code_review/v1', flow.foundational_flow_reference)
      expect(presenter.selected_flow_references).to eq([flow.foundational_flow_reference])
    end

    context 'when the readiness card is off' do
      before do
        stub_feature_flags(duo_group_agent_readiness_settings: false)
      end

      it 'still lists and selects its own flows' do
        expect(presenter.readiness_card_enabled?).to be(false)
        expect(listed_references).to include('code_review/v1')
        expect(presenter.selected_flow_references).to eq([flow.foundational_flow_reference])
      end
    end
  end

  context 'for a subgroup' do
    let(:group) { subgroup }

    before do
      stub_feature_flags(duo_group_agent_readiness_settings: root_group)
    end

    it 'lists only the flows the top-level group picked, with no selection of its own' do
      expect(presenter.readiness_card_enabled?).to be(true)
      expect(listed_references).to eq([flow.foundational_flow_reference])
      expect(presenter.selected_flow_references).to eq([])
    end

    context 'when the readiness card is on only for the subgroup' do
      before do
        stub_feature_flags(duo_group_agent_readiness_settings: subgroup)
      end

      it 'lists no flows, as without the card' do
        expect(presenter.readiness_card_enabled?).to be(false)
        expect(presenter.listed_flows).to eq([])
        expect(presenter.selected_flow_references).to eq([])
      end
    end

    context 'when only the top-level group turned on experiment features' do
      let(:group) { beta_subgroup }

      # rubocop:disable RSpec/FactoryBot/AvoidCreate -- the beta flows read the persisted setting
      let_it_be(:beta_root_group) do
        create(:group, namespace_settings: build(:namespace_settings, experiment_features_enabled: true))
      end

      let_it_be(:beta_subgroup) { create(:group, parent: beta_root_group) }
      let_it_be(:beta_flow) do
        create(:ai_catalog_item, :with_foundational_flow_reference, :public,
          foundational_flow_reference: 'recommend_reviewers/v1')
      end

      before_all do
        create(:ai_catalog_enabled_foundational_flow, :for_namespace, namespace: beta_root_group,
          catalog_item: beta_flow)
      end
      # rubocop:enable RSpec/FactoryBot/AvoidCreate

      before do
        stub_feature_flags(duo_group_agent_readiness_settings: beta_root_group)
      end

      it 'lists the beta flows the top-level group picked' do
        expect(listed_references).to eq(['recommend_reviewers/v1'])
      end
    end
  end
end
