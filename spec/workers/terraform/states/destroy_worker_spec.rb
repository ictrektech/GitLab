# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Terraform::States::DestroyWorker, feature_category: :infrastructure_as_code do
  let(:state) { create(:terraform_state) }

  describe '#perform' do
    let(:state_id) { state.id }
    let(:deletion_service) { instance_double(Terraform::States::DestroyService, execute: true) }

    subject { described_class.new.perform(state_id) }

    it 'calls the deletion service without permanent flag or user' do
      expect(deletion_service).to receive(:execute).once
      expect(Terraform::States::DestroyService).to receive(:new)
        .with(state, permanent: nil, current_user: nil).and_return(deletion_service)

      subject
    end

    context 'with permanent and user_id params' do
      let_it_be(:user) { create(:user) }

      subject { described_class.new.perform(state_id, { 'permanent' => true, 'user_id' => user.id }) }

      it 'calls the deletion service with the permanent flag and user' do
        expect(deletion_service).to receive(:execute).once
        expect(Terraform::States::DestroyService).to receive(:new)
          .with(state, permanent: true, current_user: user).and_return(deletion_service)

        subject
      end

      context 'when the user no longer exists' do
        subject { described_class.new.perform(state_id, { 'permanent' => true, 'user_id' => non_existing_record_id }) }

        it 'calls the deletion service without a user' do
          expect(deletion_service).to receive(:execute).once
          expect(Terraform::States::DestroyService).to receive(:new)
            .with(state, permanent: true, current_user: nil).and_return(deletion_service)

          subject
        end
      end
    end

    context 'when enqueued through Sidekiq', :sidekiq_inline do
      let(:state) { create(:terraform_state, :with_version, deleted_at: Time.current) }

      it 'passes the params through JSON serialization and skips the grace period' do
        expect { described_class.perform_async(state.id, { 'permanent' => true }) }
          .to change { Terraform::State.exists?(state.id) }.from(true).to(false)
      end
    end

    context 'when state no longer exists' do
      let(:state_id) { -1 }

      it 'completes without error' do
        expect { subject }.not_to raise_error
      end
    end
  end
end
