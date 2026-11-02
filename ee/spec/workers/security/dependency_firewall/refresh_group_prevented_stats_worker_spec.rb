# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::DependencyFirewall::RefreshGroupPreventedStatsWorker, feature_category: :dependency_firewall do
  include EE::GeoHelpers

  let_it_be(:group) { create(:group) }

  let(:refresh_service) { Security::DependencyFirewall::PreventedStats::GroupRefreshService }

  it 'declares deduplication until executed with one reschedule, and a concurrency limit of 5' do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
    expect(described_class.get_deduplication_options).to include(
      if_deduplicated: :reschedule_once,
      including_scheduled: true
    )
    expect(described_class.get_concurrency_limit).to eq(5)
  end

  it 'defers on database health for the prevented stats tables' do
    expect(described_class.database_health_check_attrs).to include(
      gitlab_schema: :gitlab_main,
      tables: [:dependency_firewall_prevented_packages],
      delay_by: 1.minute
    )
    expect(described_class.defer_on_database_health_signal?).to be(true)
  end

  describe '#perform' do
    subject(:perform) { described_class.new.perform(group.id) }

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [group.id] }
    end

    it 'refreshes the group summary' do
      service = instance_double(refresh_service, execute: nil)
      expect(refresh_service).to receive(:new).with(group).and_return(service)
      expect(service).to receive(:execute)

      perform
    end

    it 'does nothing when the group does not exist' do
      expect(refresh_service).not_to receive(:new)

      described_class.new.perform(non_existing_record_id)
    end

    it 'does nothing on a Geo secondary site' do
      stub_secondary_site

      expect(refresh_service).not_to receive(:new)

      perform
    end

    it 'does nothing when the flag is disabled for the root group' do
      stub_feature_flags(dependency_firewall_group_prevented_stats: false)

      expect(refresh_service).not_to receive(:new)

      perform
    end

    context 'with a subgroup whose root has the flag' do
      let_it_be(:subgroup) { create(:group, parent: group) }

      before do
        stub_feature_flags(dependency_firewall_group_prevented_stats: group)
        allow(refresh_service).to receive(:new).and_return(instance_double(refresh_service, execute: nil))
      end

      it 'refreshes the subgroup and loads only the subgroup to check the flag', :aggregate_failures do
        # Geo::SkipSecondary#perform calls Gitlab::Geo.secondary?, which queries geo_nodes unless its
        # process-level cache is warm. Stub it so the count reflects only the worker's own queries.
        allow(::Gitlab::Geo).to receive(:secondary?).and_return(false)

        recorder = ActiveRecord::QueryRecorder.new { described_class.new.perform(subgroup.id) }

        expect(refresh_service).to have_received(:new).with(subgroup)
        expect(recorder.count).to eq(1)
      end
    end

    it 'lets a refresh error propagate so Sidekiq retries' do
      allow(refresh_service).to receive(:new).and_raise(StandardError, 'boom')

      expect { perform }.to raise_error(StandardError, 'boom')
    end
  end

  describe '.schedule' do
    it 'enqueues nothing for no group ids' do
      expect(described_class).not_to receive(:bulk_perform_async)

      described_class.schedule([])
    end

    it 'enqueues one job per unique group id' do
      other_group = create(:group)

      expect { described_class.schedule([group.id, other_group.id, group.id]) }
        .to change { described_class.jobs.size }.by(2)

      expect(described_class.jobs.pluck('args')).to contain_exactly([group.id], [other_group.id])
    end
  end
end
