# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::Groups::TransferWorker, feature_category: :organization do
  let_it_be(:old_organization) { create(:organization) }
  let_it_be(:group) { create(:group, organization: old_organization) }
  let_it_be(:organization) { create(:organization) }
  let_it_be(:user) { create(:user) }

  let(:worker) { described_class.new }
  let(:args) do
    {
      'group_id' => group.id,
      'organization_id' => organization.id,
      'current_user_id' => user.id
    }
  end

  describe '#perform', :clean_gitlab_redis_shared_state do
    subject(:perform) { worker.perform(args) }

    let(:lease_key) { described_class.lease_key(group.id) }

    context 'when all records exist' do
      it 'calls the transfer service' do
        expect_next_instance_of(
          Organizations::Transfer::GroupsService,
          group: group,
          new_organization: organization,
          current_user: user,
          force: false
        ) do |service|
          expect(service).to receive(:execute)
        end

        perform
      end

      it 'releases the lease after the transfer' do
        allow_next_instance_of(Organizations::Transfer::GroupsService) do |service|
          allow(service).to receive(:execute)
        end

        perform

        expect(Gitlab::ExclusiveLease.get_uuid(lease_key)).to be(false)
      end

      context 'when the transfer service raises' do
        it 'releases the lease and re-raises' do
          allow_next_instance_of(Organizations::Transfer::GroupsService) do |service|
            allow(service).to receive(:execute).and_raise(StandardError, 'transfer failed')
          end

          expect { perform }.to raise_error(StandardError, 'transfer failed')
          expect(Gitlab::ExclusiveLease.get_uuid(lease_key)).to be(false)
        end
      end

      context 'when force is passed' do
        let(:args) { super().merge('force' => true) }

        it 'forwards force to the transfer service' do
          expect_next_instance_of(
            Organizations::Transfer::GroupsService,
            group: group,
            new_organization: organization,
            current_user: user,
            force: true
          ) do |service|
            expect(service).to receive(:execute)
          end

          perform
        end
      end

      context 'when another job holds the lease for the group' do
        let(:other_jid) { 'other-worker-jid' }

        before do
          Gitlab::ExclusiveLease.new(lease_key, uuid: other_jid, timeout: 1.minute).try_obtain
        end

        it 'does not call the transfer service, logs the conflict and leaves the lease intact', :aggregate_failures do
          expect(Organizations::Transfer::GroupsService).not_to receive(:new)
          expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(
            group_id: group.id,
            Labkit::Fields::GL_ORGANIZATION_ID => organization.id
          ))

          expect { perform }.not_to raise_error
          expect(Gitlab::ExclusiveLease.get_uuid(lease_key)).to eq(other_jid)
        end
      end

      context 'when the lease is held by the same jid after a Sidekiq interrupt' do
        let(:jid) { 'interrupted-worker-jid' }

        before do
          allow(worker).to receive(:jid).and_return(jid)
          Gitlab::ExclusiveLease.new(lease_key, uuid: jid, timeout: 1.minute).try_obtain
        end

        it 'reclaims the lease, runs the transfer and releases the lease', :aggregate_failures do
          expect_next_instance_of(Organizations::Transfer::GroupsService) do |service|
            expect(service).to receive(:execute)
          end

          perform

          expect(Gitlab::ExclusiveLease.get_uuid(lease_key)).to be(false)
        end
      end
    end

    context 'when group does not exist' do
      let(:args) do
        {
          'group_id' => non_existing_record_id,
          'organization_id' => organization.id,
          'current_user_id' => user.id
        }
      end

      it 'does not call the transfer service' do
        expect(Organizations::Transfer::GroupsService).not_to receive(:new)

        perform
      end

      it 'does not raise an error' do
        expect { perform }.not_to raise_error
      end
    end

    context 'when organization does not exist' do
      let(:args) do
        {
          'group_id' => group.id,
          'organization_id' => non_existing_record_id,
          'current_user_id' => user.id
        }
      end

      it 'does not call the transfer service' do
        expect(Organizations::Transfer::GroupsService).not_to receive(:new)

        perform
      end

      it 'does not raise an error' do
        expect { perform }.not_to raise_error
      end
    end

    context 'when user does not exist' do
      let(:args) do
        {
          'group_id' => group.id,
          'organization_id' => organization.id,
          'current_user_id' => non_existing_record_id
        }
      end

      it 'does not call the transfer service' do
        expect(Organizations::Transfer::GroupsService).not_to receive(:new)

        perform
      end

      it 'does not raise an error' do
        expect { perform }.not_to raise_error
      end
    end
  end

  describe 'worker attributes' do
    it 'is idempotent' do
      expect(described_class).to be_idempotent
    end

    it 'deduplicates until the running job finishes' do
      expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
    end

    it 'has the correct feature category' do
      expect(described_class.get_feature_category).to eq(:organization)
    end

    it 'has low urgency' do
      expect(described_class.get_urgency).to eq(:low)
    end
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [args] }
  end
end
