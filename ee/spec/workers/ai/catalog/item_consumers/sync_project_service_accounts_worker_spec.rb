# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::ItemConsumers::SyncProjectServiceAccountsWorker, feature_category: :ai_catalog_curation do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:item_consumer) { create(:ai_catalog_item_consumer, :inheritance, group: group) }

  let(:user_id) { user.id }
  let(:project_ids) { [project.id] }

  subject(:perform) { described_class.new.perform(user_id, project_ids) }

  describe 'worker attributes' do
    it 'has the expected attributes', :aggregate_failures do
      expect(described_class.get_feature_category).to eq(:ai_catalog_curation)
      expect(described_class.get_urgency).to eq(:low)
      expect(described_class.get_concurrency_limit).to eq(10)
    end

    it_behaves_like 'worker with data consistency', described_class, data_consistency: :delayed
  end

  describe '#perform' do
    it 'adds the inherited service account to the projects' do
      perform

      expect(project.member(item_consumer.service_account).access_level).to eq(Gitlab::Access::DEVELOPER)
    end

    context 'when the user no longer exists' do
      let(:user_id) { non_existing_record_id }

      it 'does not add any members' do
        expect { perform }.not_to change { ProjectMember.count }
      end
    end

    context 'with an old top-level group' do
      let_it_be(:old_group) { create(:group) }
      let_it_be(:project_still_in_old_group) { create(:project, group: old_group) }

      let(:project_ids) { [project.id, project_still_in_old_group.id] }

      subject(:perform) do
        described_class.new.perform(user_id, project_ids, { 'old_root_namespace_id' => old_group.id })
      end

      it 'removes the old group service accounts from the transferred projects only, then adds the new ones' do
        expect(Ai::Catalog::ItemConsumers::RemoveTransferredServiceAccountsService)
          .to receive(:new).with(project: project, old_root_namespace_id: old_group.id, current_user: user)
          .and_call_original

        perform

        expect(project.member(item_consumer.service_account).access_level).to eq(Gitlab::Access::DEVELOPER)
      end
    end

    context 'when the projects no longer exist' do
      let(:project_ids) { [non_existing_record_id] }

      it 'does not add any members' do
        expect { perform }.not_to change { ProjectMember.count }
      end
    end
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [user.id, [project.id]] }
  end
end
