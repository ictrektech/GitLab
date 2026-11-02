# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::AddInheritedServiceAccountMembersToHierarchyWorker, feature_category: :ai_catalog_curation do
  let_it_be(:triggering_user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:nested_subgroup) { create(:group, parent: subgroup) }

  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:subgroup_project) { create(:project, group: subgroup) }
  let_it_be(:nested_project) { create(:project, group: nested_subgroup) }
  let_it_be(:other_project) { create(:project, :in_group) }

  let_it_be_with_refind(:item_consumer) { create(:ai_catalog_item_consumer, :inheritance, group: group) }

  let(:service_account) { item_consumer.service_account }
  let(:triggering_user_id) { triggering_user.id }
  let(:item_consumer_id) { item_consumer.id }

  subject(:perform) { described_class.new.perform(triggering_user_id, item_consumer_id) }

  before do
    stub_const("#{described_class}::BATCH_SLEEP", 0)
  end

  def service_account_project_ids
    ProjectMember.for_users(service_account).pluck(:source_id)
  end

  shared_examples 'does not add any members' do
    it 'does not add any members' do
      expect { perform }.not_to change { ProjectMember.count }
    end
  end

  describe 'worker attributes' do
    it 'has the expected attributes', :aggregate_failures do
      expect(described_class.get_feature_category).to eq(:ai_catalog_curation)
      expect(described_class.get_urgency).to eq(:low)
      expect(described_class.get_concurrency_limit).to eq(10)
    end

    it_behaves_like 'worker with data consistency', described_class, data_consistency: :delayed
  end

  describe '#perform' do
    it 'adds the service account as a developer of every project in the hierarchy' do
      perform

      expect(service_account_project_ids).to contain_exactly(project.id, subgroup_project.id, nested_project.id)
      expect(ProjectMember.for_users(service_account).pluck(:access_level).uniq).to eq([Gitlab::Access::DEVELOPER])
    end

    it 'pauses after each batch so a waiting trigger can take the lock' do
      stub_const("#{described_class}::BATCH_SIZE", 1)

      expect_next_instance_of(described_class) do |worker|
        expect(worker).to receive(:sleep).with(described_class::BATCH_SLEEP).exactly(3).times
      end

      perform
    end

    it 'records the triggering user as the creator' do
      perform

      expect(ProjectMember.for_users(service_account).pluck(:created_by_id).uniq).to eq([triggering_user.id])
    end

    it 'does not queue a cleanup' do
      expect(Ai::Catalog::DeleteServiceAccountMembersFromHierarchyWorker).not_to receive(:perform_async)

      perform
    end

    context 'when the service account is already a member of some projects' do
      before do
        create(:project_member, :reporter, source: project, user: service_account)
        create(:project_member, :maintainer, source: subgroup_project, user: service_account)
      end

      it 'keeps their existing roles and does not duplicate members', :aggregate_failures do
        perform

        expect(service_account_project_ids).to contain_exactly(project.id, subgroup_project.id, nested_project.id)
        expect(project.member(service_account).access_level).to eq(Gitlab::Access::REPORTER)
        expect(subgroup_project.member(service_account).access_level).to eq(Gitlab::Access::MAINTAINER)
      end
    end

    context 'when the triggering user no longer exists' do
      let(:triggering_user_id) { non_existing_record_id }

      it_behaves_like 'does not add any members'
    end

    context 'when the item consumer no longer exists' do
      let(:item_consumer_id) { non_existing_record_id }

      it_behaves_like 'does not add any members'
    end

    context 'when the item consumer is not an inheritance consumer' do
      let_it_be(:other_group) { create(:group) }
      let_it_be(:direct_consumer) { create(:ai_catalog_item_consumer, :for_flow, group: other_group) }
      let_it_be(:other_group_project) { create(:project, group: other_group) }

      let(:item_consumer_id) { direct_consumer.id }

      it_behaves_like 'does not add any members'
    end

    context 'when the inheritance consumer has no service account' do
      let_it_be(:agent_consumer) do
        create(:ai_catalog_item_consumer, :inheritance,
          group: group, item: create(:ai_catalog_agent, :public), service_account: nil)
      end

      let(:item_consumer_id) { agent_consumer.id }

      it_behaves_like 'does not add any members'
    end

    context 'when the ai_catalog_group_inherited_consumers feature flag is disabled' do
      before do
        stub_feature_flags(ai_catalog_group_inherited_consumers: false)
      end

      it 'still adds the service account to every project in the hierarchy' do
        perform

        expect(service_account_project_ids).to contain_exactly(project.id, subgroup_project.id, nested_project.id)
      end
    end

    context 'when the item consumer is removed part way through' do
      before do
        stub_const("#{described_class}::BATCH_SIZE", 1)

        allow(Ai::ServiceAccountProjectMemberBulkAddService)
          .to receive(:new).and_wrap_original do |method, *args, **kwargs|
          service = method.call(*args, **kwargs)
          item_consumer.destroy!
          service
        end
      end

      it 'stops after the current batch and queues a cleanup', :aggregate_failures do
        expect(Ai::Catalog::DeleteServiceAccountMembersFromHierarchyWorker).to receive(:perform_async)
          .with(triggering_user.id, service_account.id, group.id, { 'skip_authorization' => true })

        perform

        expect(service_account_project_ids.size).to eq(1)
      end
    end

    context 'when the item consumer is removed during the last batch' do
      before do
        allow(Ai::ServiceAccountProjectMemberBulkAddService)
          .to receive(:new).and_wrap_original do |method, *args, **kwargs|
          service = method.call(*args, **kwargs)
          item_consumer.destroy!
          service
        end
      end

      it 'finishes the batch and queues a cleanup', :aggregate_failures do
        expect(Ai::Catalog::DeleteServiceAccountMembersFromHierarchyWorker).to receive(:perform_async)
          .with(triggering_user.id, service_account.id, group.id, { 'skip_authorization' => true })

        perform

        expect(service_account_project_ids).to contain_exactly(project.id, subgroup_project.id, nested_project.id)
      end
    end

    context 'when the item consumer service account changes part way through' do
      let_it_be(:other_service_account) { create(:service_account) }

      before do
        stub_const("#{described_class}::BATCH_SIZE", 1)

        allow(Ai::ServiceAccountProjectMemberBulkAddService)
          .to receive(:new).and_wrap_original do |method, *args, **kwargs|
          service = method.call(*args, **kwargs)
          item_consumer.update_column(:service_account_id, other_service_account.id)
          service
        end
      end

      it 'stops after the current batch and queues a cleanup for the original service account',
        :aggregate_failures do
        expect(Ai::Catalog::DeleteServiceAccountMembersFromHierarchyWorker).to receive(:perform_async)
          .with(triggering_user.id, service_account.id, group.id, { 'skip_authorization' => true })

        perform

        expect(service_account_project_ids.size).to eq(1)
      end
    end

    context 'when a project in the hierarchy is archived' do
      let_it_be(:archived_project) { create(:project, :archived, group: subgroup) }

      it 'adds the service account to the archived project too' do
        perform

        expect(service_account_project_ids).to include(archived_project.id)
      end
    end
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [triggering_user.id, item_consumer.id] }
  end
end
