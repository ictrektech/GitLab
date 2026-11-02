# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::UpdateRepositoryStorageWorker, feature_category: :gitaly do
  subject { described_class.new }

  it_behaves_like 'an update storage move worker' do
    let_it_be_with_refind(:container) { create(:group, :wiki_repo) }
    let_it_be(:repository_storage_move) { create(:group_repository_storage_move) }

    let(:service_klass) { Groups::UpdateRepositoryStorageService }
    let(:repository_storage_move_klass) { Groups::RepositoryStorageMove }
  end

  describe '#perform' do
    context 'when the repository storage move does not exist' do
      it 'does not raise an error and does not call the update repository storage service' do
        expect(Groups::UpdateRepositoryStorageService).not_to receive(:new)

        expect { described_class.new.perform(non_existing_record_id) }.not_to raise_error
      end
    end
  end
end
