# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::UnassignCrossOrganizationPolicyConfigurationsWorker, feature_category: :security_policy_management do
  subject(:worker) { described_class.new }

  describe '#perform' do
    let_it_be(:old_organization) { create(:organization) }
    let_it_be(:new_organization) { create(:organization) }
    let_it_be(:old_admin_bot) { create(:user, :admin_bot, organization: old_organization) }
    let_it_be(:new_admin_bot) { create(:user, :admin_bot, organization: new_organization) }

    let_it_be(:group) { create(:group, organization: new_organization) }
    let_it_be(:subgroup) { create(:group, parent: group, organization: new_organization) }
    let_it_be(:inside_policy_project) { create(:project, group: group, organization: new_organization) }
    let_it_be(:old_organization_project) { create(:project, organization: old_organization) }
    let_it_be(:new_organization_project) { create(:project, organization: new_organization) }

    let_it_be(:inside_to_old_organization) do
      create(:security_orchestration_policy_configuration, :namespace,
        namespace: subgroup, security_policy_management_project: old_organization_project)
    end

    let_it_be(:old_organization_to_inside) do
      create(:security_orchestration_policy_configuration,
        project: create(:project, organization: old_organization),
        security_policy_management_project: inside_policy_project)
    end

    let_it_be(:new_organization_to_inside) do
      create(:security_orchestration_policy_configuration,
        project: new_organization_project, security_policy_management_project: inside_policy_project)
    end

    let(:job_args) { [group.id] }

    it_behaves_like 'an idempotent worker'

    it 'unassigns policy projects linked across organizations' do
      expect(Security::Orchestration::UnassignService).to receive(:new)
        .with(container: subgroup, current_user: new_admin_bot).and_call_original
      expect(Security::Orchestration::UnassignService).to receive(:new)
        .with(container: old_organization_to_inside.project, current_user: old_admin_bot).and_call_original
      expect(Security::Orchestration::UnassignService).not_to receive(:new)
        .with(hash_including(container: new_organization_project))

      worker.perform(group.id)
    end

    it 'logs the number of unassigned configurations' do
      expect(worker).to receive(:log_extra_metadata_on_done).with(:unassigned_configurations_count, 2)

      worker.perform(group.id)
    end

    it 'does not count configurations when unassigning returns an error' do
      allow_next_instance_of(Security::Orchestration::UnassignService) do |service|
        allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'failed'))
      end

      expect(worker).to receive(:log_extra_metadata_on_done).with(:unassigned_configurations_count, 0)

      worker.perform(group.id)
    end

    it 'raises when unassigning fails so the job is retried' do
      allow(Security::Orchestration::UnassignService).to receive(:new).and_raise(ActiveRecord::StatementInvalid)

      expect { worker.perform(group.id) }.to raise_error(ActiveRecord::StatementInvalid)
    end

    context 'when the group does not exist' do
      it 'does nothing' do
        expect(Security::Orchestration::UnassignService).not_to receive(:new)

        worker.perform(non_existing_record_id)
      end
    end
  end
end
