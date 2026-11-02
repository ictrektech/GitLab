# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::ItemConsumers::SyncTransferredProjectsService, feature_category: :ai_catalog_curation do
  let_it_be(:user) { create(:user) }
  let_it_be(:old_root) { create(:group) }
  let_it_be(:new_root) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: new_root) }
  let_it_be(:project) { create(:project, group: new_root) }
  let_it_be(:nested_project) { create(:project, group: subgroup) }

  let(:worker) { Ai::Catalog::ItemConsumers::SyncProjectServiceAccountsWorker }
  let(:projects) { Project.id_in(project.id) }
  let(:old_root_namespace_id) { old_root.id }
  let(:params) { { 'old_root_namespace_id' => old_root.id } }
  let(:queued_args) { worker.jobs.pluck('args') }

  subject(:execute) do
    described_class.new(
      projects,
      old_root_namespace_id: old_root_namespace_id,
      new_root_namespace_id: new_root.id,
      current_user: user
    ).execute
  end

  describe '#execute', :clean_gitlab_redis_queues do
    context 'when the new top-level group has an inheritance consumer' do
      before_all do
        create(:ai_catalog_item_consumer, :inheritance, group: new_root)
      end

      it 'queues syncing the project service accounts with the old top-level group', :aggregate_failures do
        expect(execute).to be_success

        expect(queued_args).to contain_exactly([user.id, [project.id], params])
      end

      it 'runs the jobs in the context of the new top-level group' do
        execute

        expect(worker.jobs.pluck('meta.root_namespace')).to contain_exactly(new_root.full_path)
      end

      context 'with all projects of a group' do
        let(:projects) { new_root.all_projects }

        it 'includes the projects of nested subgroups' do
          execute

          expect(queued_args).to contain_exactly([user.id, contain_exactly(project.id, nested_project.id), params])
        end

        it 'queues one job per batch' do
          stub_const("#{described_class}::BATCH_SIZE", 1)

          execute

          expect(queued_args).to contain_exactly(
            [user.id, [project.id], params],
            [user.id, [nested_project.id], params]
          )
        end
      end

      context 'when the projects stay in the same top-level group' do
        let(:old_root_namespace_id) { new_root.id }

        it 'does not queue syncing the project service accounts', :aggregate_failures do
          expect(execute).to be_success

          expect(queued_args).to be_empty
        end
      end

      context 'when the ai_catalog_group_inherited_consumers feature flag is disabled for the new top-level group' do
        before do
          stub_feature_flags(ai_catalog_group_inherited_consumers: old_root)
        end

        it 'does not queue syncing the project service accounts', :aggregate_failures do
          expect(execute).to be_success

          expect(queued_args).to be_empty
        end
      end
    end

    context 'when the old top-level group has a flow group configuration' do
      before_all do
        create(:ai_catalog_item_consumer, :for_flow, group: old_root)
      end

      it 'queues syncing the project service accounts with the old top-level group' do
        execute

        expect(queued_args).to contain_exactly([user.id, [project.id], params])
      end

      context 'when the ai_catalog_group_inherited_consumers feature flag is disabled' do
        before do
          stub_feature_flags(ai_catalog_group_inherited_consumers: false)
        end

        it 'still queues syncing the project service accounts' do
          execute

          expect(queued_args).to contain_exactly([user.id, [project.id], params])
        end
      end
    end

    context 'when neither top-level group has a flow configuration' do
      it 'does not queue syncing the project service accounts', :aggregate_failures do
        expect(execute).to be_success

        expect(queued_args).to be_empty
      end
    end
  end
end
