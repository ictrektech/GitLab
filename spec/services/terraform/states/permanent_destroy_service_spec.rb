# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Terraform::States::PermanentDestroyService, feature_category: :infrastructure_as_code do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, maintainer_of: project) }

  describe '#execute', :aggregate_failures do
    let(:state) { create(:terraform_state, project: project, deleted_at: Time.current) }

    subject(:execute) { described_class.new(state, current_user: user).execute }

    context 'when the state is marked for deletion' do
      it 'enqueues the destroy worker with permanent and user_id params and returns success' do
        expect(Terraform::States::DestroyWorker).to receive(:perform_async)
          .with(state.id, { 'permanent' => true, 'user_id' => user.id }).once

        expect(execute).to be_success
      end

      it 'does not modify the state' do
        expect { execute }.not_to change { state.reload.attributes }
      end
    end

    context 'when a protection rule applies to the state' do
      before do
        create(:terraform_state_protection_rule,
          project: project,
          state_name: state.name,
          minimum_access_level_for_write: :owner)
      end

      it 'returns an error without enqueuing the worker' do
        expect(Terraform::States::DestroyWorker).not_to receive(:perform_async)

        expect(execute).to be_error
        expect(execute.message).to eq('Write access to this Terraform state is restricted by a protection rule')
      end

      context 'when the protected_terraform_states feature flag is disabled' do
        before do
          stub_feature_flags(protected_terraform_states: false)
        end

        it 'enqueues the destroy worker and returns success' do
          expect(Terraform::States::DestroyWorker).to receive(:perform_async)
            .with(state.id, { 'permanent' => true, 'user_id' => user.id }).once

          expect(execute).to be_success
        end
      end

      context 'when the user meets the minimum access level' do
        let_it_be(:user) { project.owner }

        it 'enqueues the destroy worker and returns success' do
          expect(Terraform::States::DestroyWorker).to receive(:perform_async)
            .with(state.id, { 'permanent' => true, 'user_id' => user.id }).once

          expect(execute).to be_success
        end
      end
    end

    context 'when the state is not marked for deletion' do
      let(:state) { create(:terraform_state, project: project) }

      it 'returns an error without enqueuing the worker' do
        expect(Terraform::States::DestroyWorker).not_to receive(:perform_async)

        expect(execute).to be_error
        expect(execute.message).to eq('State must be marked for deletion before it can be permanently deleted')
      end
    end

    context 'when the user does not have permission' do
      let_it_be(:user) { create(:user, developer_of: project) }

      it 'returns an error without enqueuing the worker' do
        expect(Terraform::States::DestroyWorker).not_to receive(:perform_async)

        expect(execute).to be_error
        expect(execute.message).to eq('You have insufficient permissions to permanently delete this state')
      end
    end
  end
end
