# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Graphql::Loaders::Ai::FlowTriggerRunStatsLoader, feature_category: :dap_triggers do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:now) { 1.day.ago.utc.noon }

  let_it_be(:stats_trigger) { create(:ai_flow_trigger, project: project) }
  let_it_be(:never_run_trigger) { create(:ai_flow_trigger, project: project) }

  before_all do
    create_session(stats_trigger, :finished, created_at: now - 3.days, updated_at: now - 3.days + 60.seconds)
    create_session(stats_trigger, :failed, created_at: now - 2.days, updated_at: now - 2.days + 120.seconds)
    create_session(stats_trigger, :stopped, created_at: now - 2.days, updated_at: now - 2.days + 300.seconds)
    create_session(stats_trigger, :running, created_at: now - 1.day, updated_at: now)
    create_session(stats_trigger, :finished, created_at: 30.days.ago - 1.hour)
  end

  subject(:stats) do
    loaders = [stats_trigger, never_run_trigger].to_h do |trigger|
      [trigger.id, described_class.new(trigger, user).find]
    end

    loaders.transform_values(&:sync)
  end

  def create_session(flow_trigger, status, **attributes)
    create(:duo_workflows_workflow, status, project: flow_trigger.project, environment: :web,
      trigger_flow_trigger: flow_trigger, service_account: flow_trigger.service_account, **attributes)
  end

  before do
    allow(user).to receive(:can?).and_call_original
    allow(user).to receive(:can?).with(:duo_workflow, project).and_return(true)
  end

  it 'summarizes the runs created in the last 30 days', :aggregate_failures do
    expect(stats[stats_trigger.id]).to eq(
      total_runs: 4, finished_runs: 1, failed_runs: 1, stopped_runs: 1, median_duration_seconds: 120.0,
      daily_volume: [
        { date: (now - 3.days).to_date, runs: 1 },
        { date: (now - 2.days).to_date, runs: 2 },
        { date: (now - 1.day).to_date, runs: 1 }
      ]
    )
    expect(stats[never_run_trigger.id]).to eq(
      total_runs: 0, finished_runs: 0, failed_runs: 0, stopped_runs: 0, median_duration_seconds: nil,
      daily_volume: []
    )
  end
end
