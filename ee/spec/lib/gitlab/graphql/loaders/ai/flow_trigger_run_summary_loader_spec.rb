# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Graphql::Loaders::Ai::FlowTriggerRunSummaryLoader, feature_category: :dap_triggers do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:now) { Time.current.change(usec: 0) }

  let_it_be(:never_run_trigger) { create(:ai_flow_trigger, project: project) }
  let_it_be(:active_trigger) { create(:ai_flow_trigger, project: project) }
  let_it_be(:failed_schedule_trigger) { create(:ai_flow_trigger, project: project) }
  let_it_be(:stale_schedule_trigger) { create(:ai_flow_trigger, project: project) }

  let_it_be(:active_sessions) do
    [
      create_session(active_trigger, :finished, created_at: now - 3.hours),
      create_session(active_trigger, :running, created_at: now - 2.hours),
      create_session(active_trigger, :created, created_at: now - 1.hour)
    ]
  end

  let_it_be(:finished_session) do
    create_session(stale_schedule_trigger, :finished, created_at: now - 2.hours, updated_at: now - 1.hour)
  end

  let_it_be(:schedules) do
    [
      create(:ai_flow_schedule, flow_trigger: failed_schedule_trigger, last_run_status: :sa_invalid,
        last_run_at: now - 1.hour, last_run_error: 'Service account is invalid'),
      create(:ai_flow_schedule, flow_trigger: stale_schedule_trigger, last_run_status: :execution_error,
        last_run_at: now - 3.hours, last_run_error: 'Old error')
    ]
  end

  let(:flow_triggers) { [never_run_trigger, active_trigger, failed_schedule_trigger, stale_schedule_trigger] }

  before_all do
    create_session(failed_schedule_trigger, :finished, created_at: now - 2.hours)
    create_session(never_run_trigger, :running, service_account: active_trigger.user)
  end

  subject(:summaries) do
    loaders = flow_triggers.to_h { |trigger| [trigger.id, described_class.new(trigger, user).find] }
    loaders.transform_values(&:sync)
  end

  def create_session(flow_trigger, status, **attributes)
    create(:duo_workflows_workflow, status, project: flow_trigger.project, environment: :web,
      trigger_flow_trigger: flow_trigger, service_account: flow_trigger.user, **attributes)
  end

  context 'when the user can use flows in the project' do
    before do
      allow(user).to receive(:can?).and_call_original
      allow(user).to receive(:can?).with(:duo_workflow, project).and_return(true)
    end

    it 'summarizes the runs of each flow trigger', :aggregate_failures do
      expect(summaries[never_run_trigger.id]).to have_attributes(last_run: nil, running_count: 0)

      expect(summaries[active_trigger.id]).to have_attributes(running_count: 2)
      expect(summaries[active_trigger.id].last_run).to have_attributes(
        status: :pending, started_at: active_sessions.last.created_at, finished_at: nil, error: nil
      )

      expect(summaries[failed_schedule_trigger.id].last_run).to have_attributes(
        status: :failed, started_at: schedules.first.last_run_at, finished_at: schedules.first.last_run_at,
        error: 'Service account is invalid'
      )

      expect(summaries[stale_schedule_trigger.id].last_run).to have_attributes(
        status: :succeeded, started_at: finished_session.created_at, finished_at: finished_session.updated_at,
        error: nil
      )
    end
  end

  context 'when the user cannot use flows in the project' do
    it 'shows only the schedule failures', :aggregate_failures do
      expect(summaries[active_trigger.id]).to have_attributes(last_run: nil, running_count: 0)
      expect(summaries[failed_schedule_trigger.id].last_run).to have_attributes(status: :failed)
    end
  end

  it 'returns no run data for a group trigger or a trigger without a service account' do
    group_trigger = build_stubbed(:ai_flow_trigger, project: nil, group: build_stubbed(:group),
      user: active_trigger.user)
    trigger_without_account = build_stubbed(:ai_flow_trigger, project: project, user: nil)

    summaries = [group_trigger, trigger_without_account].map { |trigger| described_class.new(trigger, user).find }

    expect(summaries.map(&:sync)).to all(have_attributes(last_run: nil, running_count: 0))
  end
end
