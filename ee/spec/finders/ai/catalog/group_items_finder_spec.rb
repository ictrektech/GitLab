# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::GroupItemsFinder, feature_category: :ai_catalog_curation do
  include Ai::Catalog::TestHelpers

  before do
    enable_ai_catalog
  end

  it_behaves_like Ai::Catalog::BaseContainerItemsFinder do
    let(:container) { group }
    let(:owned_items) { [] }
    let(:all_items_params) { {} }

    let(:expected_default_order) do
      [
        foundational_flow,
        restricted_agent_in_group,
        public_flow_of_sibling_project,
        public_flow_of_other_project,
        public_flow
      ]
    end

    before_all do
      group.add_developer(user)
    end

    it 'does not return private items' do
      is_expected.not_to include(
        private_agent,
        private_third_party_flow,
        private_flow_of_sibling_project,
        private_flow_of_other_project
      )
    end

    context 'with items owned by a project in a subgroup' do
      let_it_be(:subgroup) { create(:group, parent: group) }
      let_it_be(:subgroup_project) { create(:project, group: subgroup) }
      let_it_be(:public_flow_of_subgroup_project) { create(:ai_catalog_flow, :public, project: subgroup_project) }
      let_it_be(:restricted_agent_of_subgroup_project) do
        create(:ai_catalog_agent, :restricted, project: subgroup_project)
      end

      let_it_be(:private_agent_of_subgroup_project) do
        create(:ai_catalog_agent, :private, project: subgroup_project)
      end

      it 'returns the public and restricted items of the subgroup project' do
        is_expected.to include(public_flow_of_subgroup_project, restricted_agent_of_subgroup_project)
        is_expected.not_to include(private_agent_of_subgroup_project)
      end
    end

    context 'when user is a reporter of the group' do
      let_it_be(:reporter) { create(:user, reporter_of: group) }

      subject(:results) { described_class.new(reporter, group, params: params).execute }

      it { is_expected.to be_empty }
    end

    context 'when user is a guest of the group' do
      let_it_be(:guest) { create(:user, guest_of: group) }

      subject(:results) { described_class.new(guest, group, params: params).execute }

      it { is_expected.to be_empty }
    end

    context 'when filtering by `enabled_by`' do
      let_it_be(:subgroup) { create(:group, parent: group) }
      let_it_be(:subgroup_project) { create(:project, group: subgroup) }

      let(:inherited_items) { [public_flow_of_sibling_project] }
      let(:project_direct_items) { [public_flow, restricted_agent_in_group] }

      before_all do
        create(:ai_catalog_item_consumer, :inheritance, group: group, item: public_flow_of_sibling_project)
        create(:ai_catalog_item_consumer, project: sibling_project, item: public_flow)
        create(:ai_catalog_item_consumer, project: subgroup_project, item: restricted_agent_in_group)
        create(:ai_catalog_item_consumer, project: other_project, item: public_flow_of_other_project)
        create(:ai_catalog_item_consumer, group: group, item: foundational_flow)
        create(
          :ai_catalog_item_consumer, :inheritance, group: group, item: public_flow_of_other_project, enabled: false
        )
        create(:ai_catalog_item_consumer, project: project, item: public_flow_of_other_project, enabled: false)
      end

      context 'when `enabled_by` is empty' do
        let(:params) { { enabled_by: [] } }

        it 'does not filter the items' do
          is_expected.to match_array(expected_items)
        end
      end

      context 'when `enabled_by` is `inheritance`' do
        let(:params) { { enabled_by: [:inheritance] } }

        it 'returns items enabled through group inheritance' do
          is_expected.to match_array(inherited_items)
        end

        context 'when the finder is for a subgroup' do
          subject(:results) { described_class.new(user, subgroup, params: params).execute }

          before_all do
            build(:ai_catalog_item_consumer, :inheritance, group: subgroup, item: public_flow)
              .save!(validate: false)
          end

          it { is_expected.to be_empty }
        end

        context 'when the ai_catalog_group_inherited_consumers feature flag is disabled' do
          before do
            stub_feature_flags(ai_catalog_group_inherited_consumers: false)
          end

          it { is_expected.to be_empty }
        end
      end

      context 'when `enabled_by` is `project_direct`' do
        let(:params) { { enabled_by: [:project_direct] } }

        it 'returns items enabled directly in projects in the group, including in subgroups' do
          is_expected.to match_array(project_direct_items)
        end

        context 'when the finder is for a subgroup' do
          subject(:results) { described_class.new(user, subgroup, params: params).execute }

          it 'returns items enabled directly in projects in the subgroup' do
            is_expected.to contain_exactly(restricted_agent_in_group)
          end
        end
      end

      context 'when `enabled_by` is `inheritance` and `project_direct`' do
        let(:params) { { enabled_by: %w[inheritance project_direct] } }

        it 'returns items enabled by either kind' do
          is_expected.to match_array(inherited_items + project_direct_items)
        end

        context 'when the ai_catalog_group_inherited_consumers feature flag is disabled' do
          before do
            stub_feature_flags(ai_catalog_group_inherited_consumers: false)
          end

          it 'returns items enabled directly in projects' do
            is_expected.to match_array(project_direct_items)
          end
        end
      end

      context 'when `enabled_by` contains an unsupported kind' do
        let(:params) { { enabled_by: [:direct, :inheritance] } }

        it 'ignores the unsupported kind' do
          is_expected.to match_array(inherited_items)
        end

        context 'when it only contains unsupported kinds' do
          let(:params) { { enabled_by: [:direct] } }

          it { is_expected.to be_empty }
        end
      end
    end
  end
end
