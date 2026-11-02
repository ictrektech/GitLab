# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RepositoryUpdateRemoteMirrorWorker, :clean_gitlab_redis_shared_state, feature_category: :source_code_management do
  let_it_be_with_reload(:remote_mirror) { create(:remote_mirror) }

  let(:scheduled_time) { Time.current - 5.minutes }

  describe '#perform' do
    subject(:worker) { described_class.new }

    context 'when continuous GitHub sync is on' do
      before do
        project = remote_mirror.project
        project.update!(import_type: 'github')
        create(:import_sync_repository, project: project,
          authority_state: :provider_canonical)
        project.association(:import_sync_repository).reset
      end

      it 'does not update the mirror' do
        expect(Projects::UpdateRemoteMirrorService).not_to receive(:new)

        worker.perform(remote_mirror.id, scheduled_time)
      end
    end
  end
end
