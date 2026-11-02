# frozen_string_literal: true

require 'spec_helper'

RSpec.shared_examples "refreshes user's project authorizations" do
  describe '#perform' do
    let_it_be(:user, freeze: false) { create(:user) }

    let(:service) { instance_double(Users::RefreshAuthorizedProjectsService) }

    subject(:job) { described_class.new }

    it 'calls refresh authorized projects service' do
      expect(service).to receive(:execute)

      expect(Users::RefreshAuthorizedProjectsService)
        .to receive(:new)
        .with(user, source: described_class.name)
        .and_return(service)

      job.perform(user.id)
    end

    context 'when the user is not found' do
      it 'does not call the refresh authorized projects service' do
        expect(Users::RefreshAuthorizedProjectsService).not_to receive(:new)

        job.perform(nil)
      end
    end

    it_behaves_like 'refreshes authorizations under the per-user lock' do
      let_it_be(:project) { create(:project) }
      let(:job_args) { [user.id] }
    end

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { user.id }

      it 'does not change authorizations when run twice' do
        group = create(:group)
        create(:project, namespace: group)
        group.add_developer(user)

        # Delete the authorization created by the after save hook of the member
        # created above.
        user.project_authorizations.delete_all

        expect { job.perform(user.id) }.to change { user.project_authorizations.reload.size }.by(1)
        expect { job.perform(user.id) }.not_to change { user.project_authorizations.reload.size }
      end
    end
  end
end

RSpec.shared_examples 'schedules a safety-net refresh when the job is given up' do
  let(:user) { build_stubbed(:user) }
  let(:job) do
    { 'class' => described_class.name, 'args' => [user.id], 'correlation_id' => 'correlation-id-of-the-dead-job' }
  end

  shared_examples 'scheduling the safety-net refresh' do
    it 'schedules a replica check for the user an hour later, tagged as a safety-net refresh' do
      freeze_time do
        give_up_job

        expect(AuthorizedProjectUpdate::UserRefreshFromReplicaWorker.jobs).to contain_exactly(
          a_hash_including(
            'args' => [user.id],
            'at' => 1.hour.from_now.to_f,
            'correlation_id' => job['correlation_id'],
            Labkit::Context.log_key(:authorized_projects_refresh_purpose) =>
              UserProjectAccessChangedService::SAFETY_NET_REFRESH_PURPOSE,
            Labkit::Context.log_key(:related_class) => described_class.name
          )
        )
      end
    end
  end

  describe '.sidekiq_retries_exhausted' do
    subject(:give_up_job) do
      described_class.sidekiq_retries_exhausted_block.call(job, ActiveRecord::QueryCanceled.new)
    end

    it_behaves_like 'scheduling the safety-net refresh'
  end

  describe '.sidekiq_interruptions_exhausted' do
    subject(:give_up_job) { described_class.interruptions_exhausted_block.call(job) }

    it_behaves_like 'scheduling the safety-net refresh'
  end
end
