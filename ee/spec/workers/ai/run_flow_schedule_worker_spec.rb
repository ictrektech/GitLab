# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::RunFlowScheduleWorker, feature_category: :dap_triggers do
  let_it_be_with_reload(:project) { create(:project, :in_group) }
  let_it_be_with_reload(:flow_trigger) { create(:ai_flow_trigger, :for_catalog_consumer, project: project) }
  let_it_be_with_reload(:schedule) do
    create(:ai_flow_schedule, flow_trigger: flow_trigger, project: project, description: 'Nightly run')
  end

  let(:options) { {} }
  let(:schedule_id) { schedule.id }

  subject(:perform) { described_class.new.perform(schedule_id, options) }

  shared_examples 'skips execution with a logged error' do |error_message|
    it 'logs an error and does not execute a flow' do
      expect(Gitlab::AppLogger).to receive(:error).with(
        message: 'Failed to execute AI flow schedule',
        schedule_id: schedule_id,
        error_message: error_message
      )
      expect(Ai::FlowTriggers::RunService).not_to receive(:new)

      perform
    end
  end

  describe '#perform' do
    context 'when the schedule does not exist' do
      let(:schedule_id) { non_existing_record_id }

      it_behaves_like 'skips execution with a logged error', 'Schedule not found'
    end

    context 'when the schedule was deactivated after being enqueued' do
      before do
        schedule.update!(active: false)
      end

      it_behaves_like 'skips execution with a logged error',
        'Schedule is not active, skipping scheduled run'

      it 'does not record a failure or notify owners' do
        expect(NotificationService).not_to receive(:new)

        expect { perform }.not_to change { schedule.reload.consecutive_failure_count }
      end

      context 'when scheduling' do
        let(:options) { { 'scheduling' => true } }

        # Reactivating recalculates next_run_at, so there is nothing to advance here.
        it 'does not advance next_run_at' do
          travel_to(schedule.next_run_at + 1.minute) do
            expect { perform }.not_to change { schedule.reload.next_run_at }
          end
        end
      end
    end

    context 'when the schedule has no flow trigger' do
      before do
        allow_next_found_instance_of(Ai::FlowSchedule) do |instance|
          allow(instance).to receive(:flow_trigger).and_return(nil)
        end
      end

      it_behaves_like 'skips execution with a logged error', 'Flow trigger not found for schedule'
    end

    context 'when the ai_flow_schedules feature flag is disabled for the project' do
      before do
        stub_feature_flags(ai_flow_schedules: false)
      end

      it_behaves_like 'skips execution with a logged error',
        'Flow schedules are not enabled for this project, skipping scheduled run'
    end

    context 'when the ai_flow_schedules feature flag is enabled for a different project only' do
      let_it_be(:other_project) { create(:project) }

      before do
        stub_feature_flags(ai_flow_schedules: other_project)
      end

      it_behaves_like 'skips execution with a logged error',
        'Flow schedules are not enabled for this project, skipping scheduled run'
    end

    context 'when the project is archived' do
      before do
        project.update!(archived: true)
      end

      it_behaves_like 'skips execution with a logged error', 'Project or ancestors are archived'
    end

    context 'when the project is scheduled for deletion' do
      before do
        allow_next_found_instance_of(Project) do |instance|
          allow(instance).to receive(:deletion_in_progress_or_scheduled_in_hierarchy_chain?).and_return(true)
        end
      end

      it_behaves_like 'skips execution with a logged error',
        'Project, namespace or ancestors are scheduled for deletion'
    end

    context 'when scheduling and next_run_at is in the future' do
      let(:options) { { 'scheduling' => true } }

      before do
        schedule.update_column(:next_run_at, 1.hour.from_now)
      end

      it_behaves_like 'skips execution with a logged error', 'Schedule next run time is in future'
    end

    context 'when the flow trigger is not active' do
      before do
        flow_trigger.update!(active: false)
      end

      it_behaves_like 'skips execution with a logged error',
        'Flow trigger is not active, skipping scheduled run'

      it 'does not record a failure or notify owners' do
        expect(NotificationService).not_to receive(:new)

        expect { perform }.not_to change { schedule.reload.consecutive_failure_count }
      end

      context 'when scheduling' do
        let(:options) { { 'scheduling' => true } }

        it 'still advances next_run_at so the schedule resumes normally once reactivated' do
          travel_to(schedule.next_run_at + 1.minute) do
            expect { perform }.to change { schedule.reload.next_run_at }
          end
        end
      end
    end

    context 'when scheduled triggers are turned off for the project' do
      before do
        project.project_setting.update!(duo_scheduled_triggers_enabled: false)
      end

      it_behaves_like 'skips execution with a logged error',
        'Scheduled triggers are turned off, skipping scheduled run'

      it 'does not record a failure, change the run status, or notify owners' do
        expect(NotificationService).not_to receive(:new)

        expect { perform }.to not_change { schedule.reload.consecutive_failure_count }
          .and not_change { schedule.reload.last_run_status }
          .and not_change { schedule.reload.active }
      end

      context 'when scheduling' do
        let(:options) { { 'scheduling' => true } }

        it 'still advances next_run_at so the schedule resumes normally once re-enabled' do
          travel_to(schedule.next_run_at + 1.minute) do
            expect { perform }.to change { schedule.reload.next_run_at }
          end
        end
      end
    end

    context 'when the flow does not support being scheduled' do
      shared_examples 'fails the run without dispatching' do
        it 'records the failure and notifies the owner' do
          expect(Ai::FlowTriggers::RunService).not_to receive(:new)
          expect_next_instance_of(NotificationService) do |notifications|
            expect(notifications).to receive(:ai_flow_schedule_failed).with(stale_schedule)
          end

          described_class.new.perform(stale_schedule.id, options)

          expect(stale_schedule.reload.last_run_error)
            .to eq('Scheduled triggers are not supported for external agents or configuration file flows')
          expect(stale_schedule.consecutive_failure_count).to eq(1)
        end
      end

      context 'with an external agent' do
        let_it_be(:external_agent_trigger) do
          create(:ai_flow_trigger, :for_catalog_consumer, project: project,
            ai_catalog_item_consumer: create(:ai_catalog_item_consumer, :child_item_consumer,
              project: project, item: create(:ai_catalog_third_party_flow)))
        end

        let_it_be_with_reload(:stale_schedule) do
          create(:ai_flow_schedule, flow_trigger: external_agent_trigger, project: project)
        end

        it_behaves_like 'fails the run without dispatching'
      end

      context 'with a configuration file flow' do
        let_it_be(:config_path_trigger) { create(:ai_flow_trigger, project: project) }

        let_it_be_with_reload(:stale_schedule) do
          create(:ai_flow_schedule, flow_trigger: config_path_trigger, project: project)
        end

        it_behaves_like 'fails the run without dispatching'
      end
    end

    context 'when the schedule is valid and due' do
      let(:run_service) { instance_double(Ai::FlowTriggers::RunService) }
      let(:response) { ServiceResponse.success }

      before do
        allow(Ai::FlowTriggers::RunService).to receive(:new).and_return(run_service)
        allow(run_service).to receive(:execute).and_return(response)
      end

      it 'runs the flow with scheduled trigger metadata and records success when scheduled triggers are enabled',
        :aggregate_failures do
        expect(project.duo_scheduled_triggers_enabled).to be(true)
        expect(Ai::FlowTriggers::RunService).to receive(:new).with(
          project: project,
          flow_trigger: flow_trigger,
          trigger_source: :scheduled,
          flow_schedule: schedule
        ).and_return(run_service)
        expect(run_service).to receive(:execute).with({ event: :scheduled })

        expect { perform }.to change { schedule.reload.last_run_status }.to('success')
      end

      # A project-scoped rollout is the normal way this feature is enabled, so the
      # flag must be read against the project and not the instance.
      context 'when the ai_flow_schedules feature flag is enabled for the project only' do
        before do
          stub_feature_flags(ai_flow_schedules: project)
        end

        it 'runs the flow' do
          expect(run_service).to receive(:execute)

          perform
        end
      end

      context 'when scheduling' do
        let(:options) { { 'scheduling' => true } }

        it 'advances next_run_at before executing' do
          travel_to(schedule.next_run_at + 1.minute) do
            expect { perform }.to change { schedule.reload.next_run_at }
          end
        end
      end

      context 'when not scheduling (for example a manual retry)' do
        it 'does not advance next_run_at' do
          expect { perform }.not_to change { schedule.reload.next_run_at }
        end
      end

      context 'when the response is wrapped in an array (response, workflow)' do
        let(:workflow) { instance_double(Ai::DuoWorkflows::Workflow) }
        let(:response) { [ServiceResponse.success, workflow] }

        it 'unwraps the response and records success' do
          perform

          expect(schedule.reload.last_run_status).to eq('success')
        end
      end

      context 'when execution succeeds' do
        it 'records success' do
          schedule.update!(consecutive_failure_count: 1, last_run_status: :execution_error)

          perform

          expect(schedule.reload).to have_attributes(
            consecutive_failure_count: 0,
            last_run_status: 'success',
            last_run_error: nil
          )
        end
      end

      context 'when execution returns an error response' do
        let(:response) { ServiceResponse.error(message: 'flow definition invalid') }

        it 'records the failure with the response message' do
          perform

          expect(schedule.reload).to have_attributes(
            last_run_status: 'execution_error',
            last_run_error: 'flow definition invalid',
            consecutive_failure_count: 1
          )
        end

        it 'logs the error' do
          expect(Gitlab::AppLogger).to receive(:error).with(
            message: 'Failed to execute AI flow schedule',
            schedule_id: schedule.id,
            error_message: 'flow definition invalid'
          )

          perform
        end

        it 'notifies owners and maintainers of the failure' do
          expect_next_instance_of(NotificationService) do |service|
            expect(service).to receive(:ai_flow_schedule_failed).with(instance_of(Ai::FlowSchedule))
          end

          perform
        end

        context 'when the response has no message' do
          let(:response) { ServiceResponse.error(message: nil) }

          it 'falls back to a generic error message' do
            perform

            expect(schedule.reload.last_run_error).to eq('Unknown execution error')
          end
        end

        context 'when this failure crosses the consecutive-failure threshold' do
          before do
            schedule.update!(consecutive_failure_count: Ai::FlowSchedule::MAX_CONSECUTIVE_FAILURES - 1)
          end

          it 'deactivates the schedule and notifies owners and maintainers' do
            expect_next_instance_of(NotificationService) do |service|
              expect(service).to receive(:ai_flow_schedule_deactivated).with(instance_of(Ai::FlowSchedule))
            end

            perform

            expect(schedule.reload.active).to be(false)
          end
        end
      end

      context 'when the response carries a reason the schedule cannot act on' do
        shared_examples 'skips the run without counting a failure' do |logged_message|
          it 'logs the skip and leaves the failure count untouched' do
            expect(Gitlab::AppLogger).to receive(:error).with(
              message: 'Failed to execute AI flow schedule',
              schedule_id: schedule.id,
              error_message: "#{logged_message}, skipping scheduled run"
            )
            expect(NotificationService).not_to receive(:new)

            expect { perform }.not_to change { schedule.reload.consecutive_failure_count }
          end

          it 'does not deactivate a schedule that is one failure from the threshold' do
            schedule.update!(consecutive_failure_count: Ai::FlowSchedule::MAX_CONSECUTIVE_FAILURES - 1)

            perform

            expect(schedule.reload).to have_attributes(active: true, last_run_status: nil)
          end
        end

        context 'when the flow is blocked by a feature flag' do
          let(:response) do
            ServiceResponse.error(
              message: 'flow is disabled by a feature flag',
              reason: :flow_disabled_by_feature_flag
            )
          end

          it_behaves_like 'skips the run without counting a failure', 'flow is disabled by a feature flag'
        end

        context 'when autonomous service account execution is disabled' do
          let(:response) do
            ServiceResponse.error(
              message: 'cannot be triggered by non-human users',
              reason: :non_human_trigger_not_permitted
            )
          end

          it_behaves_like 'skips the run without counting a failure', 'cannot be triggered by non-human users'
        end

        context 'when the namespace has exhausted its AI credits' do
          let(:response) do
            ServiceResponse.error(message: ['Usage quota exceeded'], reason: :usage_quota_exceeded)
          end

          it_behaves_like 'skips the run without counting a failure', 'Usage quota exceeded'
        end
      end

      context 'when execution raises an error' do
        let(:error) { StandardError.new('boom') }

        before do
          allow(run_service).to receive(:execute).and_raise(error)
        end

        it 'records a generic failure message' do
          perform

          expect(schedule.reload.last_run_error).to eq(described_class::UNEXPECTED_ERROR_MESSAGE)
        end

        it 'tracks the exception' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(
            error, schedule_id: schedule.id, flow_trigger_id: flow_trigger.id
          )

          perform
        end
      end
    end

    describe 'reconciling the dedicated service account role before the run' do
      let_it_be_with_reload(:autonomous_trigger) { create(:ai_flow_trigger, :autonomous) }
      let_it_be(:autonomous_project) { autonomous_trigger.project }
      let_it_be(:dedicated_account) { autonomous_trigger.autonomous_service_account }
      let_it_be(:flow_account) { autonomous_trigger.ai_catalog_item_consumer.active_service_account }

      let_it_be_with_reload(:autonomous_schedule) do
        create(:ai_flow_schedule, flow_trigger: autonomous_trigger, project: autonomous_project)
      end

      let(:schedule_id) { autonomous_schedule.id }
      let(:run_service) { instance_double(Ai::FlowTriggers::RunService) }

      def dedicated_level
        autonomous_project.project_members.reset
        autonomous_project.member(dedicated_account)&.access_level
      end

      before_all do
        autonomous_project.add_developer(flow_account)
        autonomous_project.add_developer(dedicated_account)
      end

      before do
        allow(Ai::FlowTriggers::RunService).to receive(:new).and_return(run_service)
        allow(run_service).to receive(:execute).and_return(ServiceResponse.success)
      end

      it 'follows the flow account down before running' do
        autonomous_project.member(flow_account).update!(access_level: Gitlab::Access::REPORTER)

        expect { perform }.to change { dedicated_level }
          .from(Gitlab::Access::DEVELOPER).to(Gitlab::Access::REPORTER)
      end

      it 'runs the flow once the role is in step' do
        expect(run_service).to receive(:execute)

        perform
      end

      context 'when the role cannot be reconciled' do
        before do
          allow_next_instance_of(::Ai::FlowTriggers::SyncAutonomousServiceAccountRoleService) do |service|
            allow(service).to receive(:execute).and_return(
              ServiceResponse.error(message: 'membership refused', reason: :validation_error, payload: payload)
            )
          end
        end

        context 'and the account would keep more access than the flow' do
          let(:payload) do
            { changed: false,
              access_level: Gitlab::Access::REPORTER,
              current_access_level: Gitlab::Access::MAINTAINER,
              effective_access_level: Gitlab::Access::MAINTAINER }
          end

          it 'refuses the run instead of acting over-privileged' do
            expect(run_service).not_to receive(:execute)

            perform

            expect(autonomous_schedule.reload.last_run_error).to eq(described_class::EXCESS_ACCESS_MESSAGE)
          end
        end

        context 'and the account would simply be short of access' do
          let(:payload) do
            { changed: false,
              access_level: Gitlab::Access::MAINTAINER,
              current_access_level: Gitlab::Access::DEVELOPER,
              effective_access_level: Gitlab::Access::DEVELOPER }
          end

          # Under-privilege is not a safety problem: the run either works or
          # fails on its own merits, and failing the run here would hide that.
          it 'still runs' do
            expect(run_service).to receive(:execute)

            perform
          end
        end
      end

      context 'when the account inherits a higher role from an ancestor group' do
        before do
          autonomous_project.group.add_member(dedicated_account, Gitlab::Access::MAINTAINER)
        end

        it 'refuses the run even though the project row matches the flow' do
          expect(dedicated_level).to eq(Gitlab::Access::DEVELOPER)
          expect(run_service).not_to receive(:execute)

          perform

          expect(autonomous_schedule.reload.last_run_error).to eq(described_class::EXCESS_ACCESS_MESSAGE)
        end

        it 'refuses the run when the account holds no project row at all' do
          autonomous_project.member(dedicated_account).destroy!

          expect(run_service).not_to receive(:execute)

          perform

          expect(autonomous_schedule.reload.last_run_error).to eq(described_class::EXCESS_ACCESS_MESSAGE)
        end

        it 'still runs when the inherited role does not exceed the flow' do
          autonomous_project.member(flow_account).update!(access_level: Gitlab::Access::MAINTAINER)

          expect(run_service).to receive(:execute)

          perform
        end
      end

      context 'when a shared group grants the account higher access' do
        let_it_be(:shared_group) { create(:group) }

        before do
          shared_group.add_member(dedicated_account, Gitlab::Access::MAINTAINER)
          create(:project_group_link, project: autonomous_project, group: shared_group,
            group_access: Gitlab::Access::MAINTAINER)
        end

        it 'refuses the run' do
          expect(run_service).not_to receive(:execute)

          perform

          expect(autonomous_schedule.reload.last_run_error).to eq(described_class::EXCESS_ACCESS_MESSAGE)
        end
      end

      it 'runs after a successful demotion' do
        autonomous_project.member(flow_account).update!(access_level: Gitlab::Access::REPORTER)

        expect(run_service).to receive(:execute)

        perform

        expect(dedicated_level).to eq(Gitlab::Access::REPORTER)
      end

      context 'when keeping up with the flow would mean granting access' do
        it 'does not promote the account, and still runs' do
          autonomous_project.member(flow_account).update!(access_level: Gitlab::Access::MAINTAINER)

          expect(run_service).to receive(:execute)

          expect { perform }.not_to change { dedicated_level }
        end

        it 'does not re-add a lost membership, and the eligibility check refuses the run' do
          autonomous_project.member(dedicated_account).destroy!

          expect(run_service).to receive(:execute).and_return(
            ServiceResponse.error(message: 'Service account must be a member of the target project')
          )

          perform

          expect(dedicated_level).to be_nil
          expect(autonomous_schedule.reload.last_run_error)
            .not_to eq(described_class::EXCESS_ACCESS_MESSAGE)
        end
      end

      context 'when the flow account has left the project entirely' do
        before do
          autonomous_project.member(flow_account).destroy!
        end

        it 'refuses the run rather than acting on access the flow no longer has' do
          expect(run_service).not_to receive(:execute)

          perform

          expect(autonomous_schedule.reload.last_run_error).to eq(described_class::EXCESS_ACCESS_MESSAGE)
        end

        it 'leaves the membership alone rather than guessing at a role' do
          expect { perform }.not_to change { dedicated_level }
        end

        context 'and the dedicated account is not a member either' do
          before do
            autonomous_project.member(dedicated_account).destroy!
          end

          # Nothing to be over-privileged with, so this is left to the
          # eligibility check, which refuses a non-member with its own message.
          it 'does not refuse on excess access' do
            perform

            expect(autonomous_schedule.reload.last_run_error).not_to eq(described_class::EXCESS_ACCESS_MESSAGE)
          end
        end
      end

      context 'when the feature flag is disabled for the project' do
        before do
          stub_feature_flags(autonomous_service_account_execution: false)
        end

        it 'leaves the membership alone' do
          autonomous_project.member(flow_account).update!(access_level: Gitlab::Access::REPORTER)

          expect { perform }.not_to change { dedicated_level }
        end
      end
    end

    describe 'idempotency' do
      let(:run_service) { instance_double(Ai::FlowTriggers::RunService) }

      before do
        schedule.update!(next_run_at: 1.minute.ago)

        allow(Ai::FlowTriggers::RunService).to receive(:new).and_return(run_service)
        allow(run_service).to receive(:execute).and_return(ServiceResponse.success)
      end

      context 'with a scheduled run' do
        it_behaves_like 'an idempotent worker' do
          let(:job_args) { [schedule.id, { 'scheduling' => true }] }

          it 'executes the flow once because next_run_at is advanced before execution' do
            expect(run_service).to receive(:execute).once

            perform_idempotent_work
          end
        end
      end

      context 'with a manual run' do
        it_behaves_like 'an idempotent worker' do
          let(:job_args) { [schedule.id, {}] }

          # Without the 'scheduling' flag there is no next_run_at guard, so
          # re-execution is prevented by deduplicate :until_executed, not here.
          it 'executes the flow once per invocation' do
            expect(run_service).to receive(:execute).exactly(worker_exec_times).times

            perform_idempotent_work
          end
        end
      end
    end
  end
end
