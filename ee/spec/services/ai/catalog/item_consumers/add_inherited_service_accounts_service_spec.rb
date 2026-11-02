# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::ItemConsumers::AddInheritedServiceAccountsService, feature_category: :ai_catalog_curation do
  let_it_be(:current_user) { create(:user) }

  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:subgroup_project) { create(:project, group: subgroup) }

  let_it_be(:other_group) { create(:group) }
  let_it_be(:other_group_project) { create(:project, group: other_group) }

  let_it_be(:group_without_grants) { create(:group) }
  let_it_be(:project_without_grants) { create(:project, group: group_without_grants) }

  let_it_be(:inheritance_consumer) { create(:ai_catalog_item_consumer, :inheritance, group: group) }
  let_it_be(:second_inheritance_consumer) { create(:ai_catalog_item_consumer, :inheritance, group: group) }
  let_it_be(:other_group_inheritance_consumer) do
    create(:ai_catalog_item_consumer, :inheritance, group: other_group)
  end

  let(:projects) { [subgroup_project] }

  subject(:execute) { described_class.new(projects: projects, current_user: current_user).execute }

  def member_pairs
    ProjectMember.in_projects(projects.map(&:id)).for_users(User.service_account).pluck(:source_id, :user_id)
  end

  describe '#execute' do
    it 'adds every inherited service account of the top-level group as a developer' do
      expect(execute).to be_success

      expect(member_pairs).to contain_exactly(
        [subgroup_project.id, inheritance_consumer.service_account_id],
        [subgroup_project.id, second_inheritance_consumer.service_account_id]
      )
      expect(ProjectMember.in_projects(subgroup_project.id).for_users(User.service_account).pluck(:access_level).uniq)
        .to eq([Gitlab::Access::DEVELOPER])
    end

    it 'records the current user as the creator' do
      execute

      expect(ProjectMember.in_projects(subgroup_project.id).for_users(User.service_account).pluck(:created_by_id).uniq)
        .to eq([current_user.id])
    end

    context 'with projects under different top-level groups' do
      let(:projects) { [project, other_group_project] }

      it 'adds the service accounts of each project top-level group only' do
        execute

        expect(member_pairs).to contain_exactly(
          [project.id, inheritance_consumer.service_account_id],
          [project.id, second_inheritance_consumer.service_account_id],
          [other_group_project.id, other_group_inheritance_consumer.service_account_id]
        )
      end
    end

    context 'when the ai_catalog_group_inherited_consumers feature flag is disabled for the top-level group' do
      let(:projects) { [project, other_group_project] }

      before do
        stub_feature_flags(ai_catalog_group_inherited_consumers: other_group)
      end

      it 'only adds the service accounts of top-level groups with the flag enabled' do
        execute

        expect(member_pairs).to contain_exactly(
          [other_group_project.id, other_group_inheritance_consumer.service_account_id]
        )
      end
    end

    context 'when the top-level group has no inheritance grants' do
      let(:projects) { [project_without_grants] }

      it 'does not add any members' do
        expect { execute }.not_to change { ProjectMember.count }
        expect(execute.payload[:added]).to be_empty
      end
    end

    context 'when the project is a personal project' do
      let_it_be(:personal_project) { create(:project, namespace: create(:user, :with_namespace).namespace) }

      let(:projects) { [personal_project] }

      it 'does not add any members' do
        expect { execute }.not_to change { ProjectMember.count }
      end
    end
  end
end
