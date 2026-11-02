# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::SyncSessionCreditsCronWorker, :click_house, :clean_gitlab_redis_shared_state,
  feature_category: :value_stream_management do
  let_it_be(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }
  let_it_be(:other_root) { create(:group) }
  let_it_be(:third_root) { create(:group) }
  let_it_be(:fourth_root) { create(:group) }

  let(:child_worker) { Ai::DuoWorkflows::SyncNamespaceSessionCreditsWorker }
  let(:worker) { described_class.new }

  subject(:perform) { worker.perform }

  before do
    allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
    allow(Gitlab::ClickHouse).to receive(:siphon_enabled?).with('duo_workflows_workflows').and_return(true)
    allow(Gitlab::Saas).to receive(:feature_available?).and_call_original
    allow(Gitlab::Saas).to receive(:feature_available?).with(:gitlab_com_subscriptions).and_return(true)
    allow(child_worker).to receive(:bulk_perform_async_with_contexts)
    allow(child_worker).to receive(:bulk_perform_in_with_contexts)
    allow(child_worker).to receive(:perform_async)
    allow(worker).to receive(:log_extra_metadata_on_done).and_call_original
  end

  def insert_session(id, traversal_path, watermark: 1.day.ago, updated_at: watermark)
    stamp = watermark.utc.strftime('%Y-%m-%d %H:%M:%S.%6N')
    updated_stamp = updated_at.utc.strftime('%Y-%m-%d %H:%M:%S.%6N')

    ClickHouse::Client.execute(<<~SQL, :main)
      INSERT INTO siphon_duo_workflows_workflows
        (id, user_id, created_at, updated_at, traversal_path, _siphon_replicated_at, _siphon_watermark)
      VALUES (#{id}, 1, '#{updated_stamp}', '#{updated_stamp}', '#{traversal_path}', '#{stamp}', '#{stamp}')
    SQL
  end

  # Captures [delay_seconds, groups] per enqueue call, checking the procs on the way.
  def enqueued_batches
    batches = []
    record = ->(delay, groups, arguments_proc, context_proc) do
      groups.each do |group|
        expect(arguments_proc.call(group)).to eq(group.id)
        expect(context_proc.call(group)).to eq(namespace: group)
      end

      batches << [delay.to_i, groups]
    end

    allow(child_worker).to receive(:bulk_perform_async_with_contexts) do |groups, arguments_proc:, context_proc:|
      record.call(0, groups, arguments_proc, context_proc)
    end
    allow(child_worker).to receive(:bulk_perform_in_with_contexts) do |delay, groups, arguments_proc:, context_proc:|
      record.call(delay, groups, arguments_proc, context_proc)
    end

    batches
  end

  def enqueued_groups
    batches = enqueued_batches

    Class.new do
      define_method(:to_a) { batches.flat_map(&:last) }
      define_method(:empty?) { to_a.empty? }
    end.new
  end

  def expect_logged(key, value)
    expect(worker).to have_received(:log_extra_metadata_on_done).with(key, value)
  end

  it_behaves_like 'an idempotent worker' do
    before do
      insert_session(1, root_group.traversal_path(with_organization: true))
    end
  end

  it 'enqueues one job per root namespace with sessions in the activity window', :aggregate_failures do
    insert_session(1, subgroup.traversal_path(with_organization: true))
    insert_session(2, root_group.traversal_path(with_organization: true))
    insert_session(3, other_root.traversal_path(with_organization: true))
    enqueued = enqueued_groups

    perform

    expect(enqueued).to contain_exactly(root_group, other_root)
    expect_logged(:namespaces_enumerated, 2)
    expect_logged(:namespaces_enqueued, 2)
    expect_logged(:namespaces_flag_off, 0)
    expect_logged(:stop_reason, :completed)
  end

  it 'skips root namespaces whose last session activity is older than the activity window' do
    insert_session(1, root_group.traversal_path(with_organization: true), watermark: 4.days.ago)
    enqueued = enqueued_groups

    perform

    expect(enqueued).to be_empty
    expect_logged(:namespaces_enumerated, 0)
  end

  it 'skips sessions that Siphon rewrote recently without a change in the activity window', :aggregate_failures do
    insert_session(1, root_group.traversal_path(with_organization: true), updated_at: 4.days.ago)
    insert_session(2, other_root.traversal_path(with_organization: true), updated_at: 1.day.ago)
    enqueued = enqueued_groups

    perform

    expect(enqueued).to contain_exactly(other_root)
    expect_logged(:namespaces_enumerated, 1)
  end

  it 'ignores sessions whose traversal path resolves to no root' do
    insert_session(1, '0/')
    enqueued = enqueued_groups

    perform

    expect(enqueued).to be_empty
  end

  it 'skips root namespaces that no longer exist', :aggregate_failures do
    insert_session(1, "#{root_group.organization_id}/#{non_existing_record_id}/")
    insert_session(2, root_group.traversal_path(with_organization: true))
    enqueued = enqueued_groups

    perform

    expect(enqueued).to contain_exactly(root_group)
    expect_logged(:namespaces_enumerated, 2)
    expect_logged(:namespaces_enqueued, 1)
  end

  it 'does not enqueue when nothing was active', :aggregate_failures do
    perform

    expect(child_worker).not_to have_received(:bulk_perform_async_with_contexts)
    expect(child_worker).not_to have_received(:bulk_perform_in_with_contexts)
    expect_logged(:stop_reason, :completed)
  end

  it 'spreads the jobs one minute apart across the tick', :aggregate_failures do
    insert_session(1, root_group.traversal_path(with_organization: true))
    insert_session(2, other_root.traversal_path(with_organization: true))
    insert_session(3, third_root.traversal_path(with_organization: true))
    batches = enqueued_batches

    perform

    expect(batches.map(&:first)).to match_array([0, 60, 120])
    expect(batches.flat_map(&:last)).to contain_exactly(root_group, other_root, third_root)
  end

  it 'fills the spread window evenly when there are more namespaces than minutes', :aggregate_failures do
    stub_const("#{described_class}::SPREAD_MINUTES", 2)
    insert_session(1, root_group.traversal_path(with_organization: true))
    insert_session(2, other_root.traversal_path(with_organization: true))
    insert_session(3, third_root.traversal_path(with_organization: true))
    batches = enqueued_batches

    perform

    expect(batches.map(&:first)).to match_array([0, 60])
    expect(batches.map { |(_, groups)| groups.size }).to match_array([2, 1])
  end

  it 'uses every minute of the spread when namespaces outnumber minutes', :aggregate_failures do
    stub_const("#{described_class}::SPREAD_MINUTES", 3)
    insert_session(1, root_group.traversal_path(with_organization: true))
    insert_session(2, other_root.traversal_path(with_organization: true))
    insert_session(3, third_root.traversal_path(with_organization: true))
    insert_session(4, fourth_root.traversal_path(with_organization: true))
    batches = enqueued_batches

    perform

    expect(batches.map(&:first)).to match_array([0, 60, 120])
    expect(batches.map { |(_, groups)| groups.size }).to match_array([2, 1, 1])
  end

  it 'loads the groups in slices without dropping any', :aggregate_failures do
    stub_const("#{described_class}::GROUP_LOAD_BATCH_SIZE", 1)
    insert_session(1, root_group.traversal_path(with_organization: true))
    insert_session(2, other_root.traversal_path(with_organization: true))
    batches = enqueued_batches

    perform

    expect(batches.flat_map(&:last)).to contain_exactly(root_group, other_root)
    expect(batches.map(&:first)).to match_array([0, 60])
  end

  it 'logs the namespace jobs still buffered when the tick starts' do
    allow(Gitlab::SidekiqMiddleware::ConcurrencyLimit::ConcurrencyLimitService)
      .to receive(:queue_size).with(child_worker.name).and_return(3)

    perform

    expect_logged(:namespace_jobs_buffered, 3)
  end

  it 'preloads routes for the job contexts instead of one query per group' do
    insert_session(1, root_group.traversal_path(with_organization: true))
    insert_session(2, other_root.traversal_path(with_organization: true))
    enqueued_groups

    recorder = ActiveRecord::QueryRecorder.new { perform }

    expect(recorder.log.count { |sql| sql.include?('FROM "routes"') }).to be <= 1
  end

  context 'when Siphon is not replicating duo_workflows_workflows' do
    before do
      allow(Gitlab::ClickHouse).to receive(:siphon_enabled?).with('duo_workflows_workflows').and_return(false)
      insert_session(1, root_group.traversal_path(with_organization: true))
    end

    it 'enqueues nothing and says why', :aggregate_failures do
      enqueued = enqueued_groups

      perform

      expect(enqueued).to be_empty
      expect_logged(:stop_reason, :siphon_disabled)
    end
  end

  describe 'freshness' do
    let(:freshness) { Ai::DuoWorkflows::SessionCredits::SyncFreshness }
    let(:stats) { { oldest_sync_age_s: 3600, oldest_awaiting_sync_s: 0, namespaces_awaiting_sync: 0 } }

    before do
      allow(freshness).to receive(:observe).and_return(stats)
      stub_feature_flags(duo_workflow_session_credits_sync_v2: root_group)
      insert_session(1, root_group.traversal_path(with_organization: true))
      insert_session(2, other_root.traversal_path(with_organization: true))
    end

    it 'observes the namespaces in scope, not the flag-off ones, and logs the figures', :aggregate_failures do
      perform

      expect(freshness).to have_received(:observe).with([root_group.id]).once
      stats.each { |key, value| expect_logged(key, value) }
    end

    context 'when the ClickHouse scan fails' do
      before do
        allow(ClickHouse::Client).to receive(:select).and_raise(ClickHouse::Client::DatabaseError, 'down')
      end

      it 'raises, as the tick cannot enqueue anything' do
        expect { perform }.to raise_error(ClickHouse::Client::DatabaseError)
      end
    end

    context 'when Siphon is not replicating duo_workflows_workflows' do
      before do
        allow(Gitlab::ClickHouse).to receive(:siphon_enabled?).with('duo_workflows_workflows').and_return(false)
      end

      it 'observes nothing, since the scope is unknown' do
        perform

        expect(freshness).not_to have_received(:observe)
      end
    end

    context 'when the freshness store fails' do
      let(:stats) { nil }

      it 'still enqueues the namespaces', :aggregate_failures do
        enqueued = enqueued_groups

        perform

        expect(enqueued).to contain_exactly(root_group)
        expect(worker).not_to have_received(:log_extra_metadata_on_done).with(:oldest_sync_age_s, anything)
      end
    end

    context 'on self-managed' do
      before do
        allow(Gitlab::Saas).to receive(:feature_available?).with(:gitlab_com_subscriptions).and_return(false)
      end

      it 'observes nothing, since only GitLab.com namespaces are tracked' do
        perform

        expect(freshness).not_to have_received(:observe)
      end
    end
  end

  context 'when the flag is enabled for one root namespace only' do
    before do
      stub_feature_flags(duo_workflow_session_credits_sync_v2: root_group)
      insert_session(1, root_group.traversal_path(with_organization: true))
      insert_session(2, other_root.traversal_path(with_organization: true))
    end

    it 'enqueues that namespace and counts the other as flag-off', :aggregate_failures do
      enqueued = enqueued_groups

      perform

      expect(enqueued).to contain_exactly(root_group)
      expect_logged(:namespaces_enumerated, 2)
      expect_logged(:namespaces_enqueued, 1)
      expect_logged(:namespaces_flag_off, 1)
    end
  end

  context 'when ClickHouse analytics is disabled' do
    before do
      allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(false)
      insert_session(1, root_group.traversal_path(with_organization: true))
    end

    it 'does nothing' do
      perform

      expect(child_worker).not_to have_received(:bulk_perform_async_with_contexts)
    end
  end

  context 'when a namespace is paused after a CustomersDot kill switch' do
    before do
      Ai::DuoWorkflows::SessionCredits::SyncPause
        .pause!(source: root_group.id.to_s, reason: :disabled, duration: 2.hours)
      insert_session(1, root_group.traversal_path(with_organization: true))
    end

    it 'still enqueues it, since the namespace job is what honours the pause', :aggregate_failures do
      enqueued = enqueued_groups

      perform

      expect(enqueued).to contain_exactly(root_group)
      expect_logged(:stop_reason, :completed)
    end
  end

  context 'on self-managed' do
    before do
      allow(Gitlab::Saas).to receive(:feature_available?).with(:gitlab_com_subscriptions).and_return(false)
    end

    it 'enqueues one instance-level job without scanning ClickHouse', :aggregate_failures do
      expect(ClickHouse::Client).not_to receive(:select)

      perform

      expect(child_worker).to have_received(:perform_async).with(nil)
      expect_logged(:namespaces_enumerated, 1)
      expect_logged(:namespaces_enqueued, 1)
    end

    context 'when the instance flag is off' do
      before do
        stub_feature_flags(duo_workflow_session_credits_sync_v2: false)
      end

      it 'counts it as flag-off and enqueues nothing', :aggregate_failures do
        perform

        expect(child_worker).not_to have_received(:perform_async)
        expect_logged(:namespaces_flag_off, 1)
        expect_logged(:namespaces_enqueued, 0)
      end
    end
  end

  describe 'worker attributes' do
    it 'registers with ClickHouse migration pause control and disables retries', :aggregate_failures do
      expect(described_class.click_house_worker_attrs).to be_present
      expect(described_class.sidekiq_options['retry']).to be(false)
      expect(described_class.get_data_consistency_per_database.values.uniq).to eq([:sticky])
      expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
    end
  end
end
