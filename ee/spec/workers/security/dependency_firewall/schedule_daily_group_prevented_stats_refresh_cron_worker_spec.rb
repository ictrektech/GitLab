# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::DependencyFirewall::ScheduleDailyGroupPreventedStatsRefreshCronWorker,
  feature_category: :dependency_firewall do
  let_it_be(:group) { create(:group) }
  let_it_be(:other_group) { create(:group) }
  let_it_be(:group_without_stats) { create(:group) }

  let(:refresh_worker) { Security::DependencyFirewall::RefreshGroupPreventedStatsWorker }

  subject(:worker) { described_class.new }

  def create_stat_rows(namespace)
    create(:dependency_firewall_namespace_prevented_stat, namespace: namespace, window_days: 7)
    create(:dependency_firewall_namespace_prevented_stat, namespace: namespace, window_days: 30,
      window_start: Date.current - 29)
  end

  it_behaves_like 'an idempotent worker' do
    before do
      create_stat_rows(group)
    end

    it 'refreshes the summary rows of the group' do
      Security::DependencyFirewallNamespacePreventedStat.where(namespace_id: group.id)
        .update_all(window_start: Date.current - 60)
      today = Time.current.utc.to_date

      perform_idempotent_work

      expect(Security::DependencyFirewallNamespacePreventedStat.where(namespace_id: group.id)
        .pluck(:window_days, :window_start)).to contain_exactly([7, today - 6], [30, today - 29])
    end
  end

  it 'schedules every namespace with summary rows once', :aggregate_failures do
    create_stat_rows(group)
    create_stat_rows(other_group)

    expect(worker).to receive(:log_extra_metadata_on_done).with(:scheduled_namespaces, 2)
    expect(refresh_worker).to receive(:schedule).with(contain_exactly(group.id, other_group.id)).once

    worker.perform
  end

  it 'schedules up to BATCH_SIZE namespaces per batch, each once', :aggregate_failures do
    stub_const("#{described_class}::BATCH_SIZE", 2)
    third_group = create(:group)
    [group, other_group, third_group].each { |namespace| create_stat_rows(namespace) }

    expect(worker).to receive(:log_extra_metadata_on_done).with(:scheduled_namespaces, 3)
    expect(refresh_worker).to receive(:schedule).with([group.id, other_group.id]).once
    expect(refresh_worker).to receive(:schedule).with([third_group.id]).once

    worker.perform
  end

  it 'schedules nothing when there are no summary rows', :aggregate_failures do
    expect(worker).to receive(:log_extra_metadata_on_done).with(:scheduled_namespaces, 0)
    expect(refresh_worker).not_to receive(:schedule)

    worker.perform
  end

  context 'when refresh jobs are still waiting for the concurrency limit' do
    before do
      create_stat_rows(group)
      allow(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
        .to receive(:queue_size).with(refresh_worker.name).and_return(3)
    end

    it 'still schedules every group with summary rows', :aggregate_failures do
      expect(worker).to receive(:log_extra_metadata_on_done).with(:scheduled_namespaces, 1)
      expect(refresh_worker).to receive(:schedule).with([group.id]).once

      worker.perform
    end
  end
end
