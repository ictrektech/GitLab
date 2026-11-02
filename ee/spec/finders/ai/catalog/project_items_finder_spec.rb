# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::ProjectItemsFinder, feature_category: :ai_catalog_curation do
  include Ai::Catalog::TestHelpers

  before do
    enable_ai_catalog
  end

  it_behaves_like Ai::Catalog::BaseContainerItemsFinder do
    let(:container) { project }
    let(:owned_items) { [public_flow, private_agent, private_third_party_flow] }
    let(:all_items_params) { { all_available: true } }

    let(:expected_default_order) do
      [
        foundational_flow,
        restricted_agent_in_group,
        public_flow_of_sibling_project,
        public_flow_of_other_project,
        private_third_party_flow,
        private_agent,
        public_flow
      ]
    end

    it 'returns items that are not deleted and belong to the project' do
      is_expected.to contain_exactly(public_flow, private_agent, private_third_party_flow)
    end

    it 'returns items ordered by id desc' do
      is_expected.to eq([private_third_party_flow, private_agent, public_flow])
    end

    context 'when the project is in a personal namespace and `all_available` param is `true`' do
      let(:container) { other_project }
      let(:params) { { all_available: true } }

      it 'returns owned items, public items and foundational items, but no restricted items from other projects' do
        is_expected.to match_array([
          private_flow_of_other_project,
          public_flow_of_other_project,
          restricted_agent_outside_group,
          foundational_flow,
          public_flow_of_sibling_project,
          public_flow
        ])
      end
    end

    context 'when filtering by `enabled`' do
      let(:params) { { enabled: enabled } }

      before_all do
        create(:ai_catalog_item_consumer, item: private_agent, project: project)
        create(:ai_catalog_item_consumer, item: public_flow, project: other_project)
        create(:ai_catalog_item_consumer, item: public_flow_of_other_project, project: other_project)
      end

      context 'when `enabled` is `true`' do
        let(:enabled) { true }

        it 'returns items owned by the project and enabled for the project' do
          is_expected.to contain_exactly(private_agent)
        end
      end

      context 'when `enabled` is `false`' do
        let(:enabled) { false }

        it 'returns only items that have not been enabled for the project' do
          is_expected.to contain_exactly(public_flow, private_third_party_flow)
        end
      end
    end
  end
end
