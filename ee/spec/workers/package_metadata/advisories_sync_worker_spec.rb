# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PackageMetadata::AdvisoriesSyncWorker, feature_category: :software_composition_analysis do
  using RSpec::Parameterized::TableSyntax

  let(:instance) { described_class.new }
  let(:lease) { instance_double(Gitlab::ExclusiveLease) }
  let(:advisories_path) { PackageMetadata::SyncConfiguration::Location::ADVISORIES_PATH }

  # The examples below are the delayed run, so the jitter re-enqueue does not stand
  # between them and the sync. The tick itself is covered in its own describe.
  subject(:perform!) { instance.perform(true) }

  before do
    allow(instance).to receive(:try_obtain_lease).and_yield
    allow(Gitlab::ExclusiveLease).to receive(:new).and_return(lease)
  end

  # One place to describe the instance: which purl types it syncs, whether a vendor
  # directory is present and whether that directory holds a v3 layout. The flag is
  # always explicit, since specs enable every flag by default while this one ships
  # wip and off.
  #
  # The vendored paths are pinned rather than left to fall through: a developer with
  # a real vendor/package_metadata/advisories on disk would otherwise get different
  # routing locally than CI does.
  def stub_instance(flag:, vendored: false, v3_vendored: false, purl_types: [1])
    stub_feature_flags(sync_v3_advisories: flag)
    stub_application_setting(package_metadata_purl_types: purl_types)
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(advisories_path).and_return(vendored)
    allow(File).to receive(:exist?).with(File.join(advisories_path, 'v3')).and_return(v3_vendored)
  end

  describe '#perform' do
    describe 'eligibility' do
      before do
        stub_instance(flag: false)
      end

      shared_examples_for 'it syncs' do
        it 'calls sync service with the advisories data_type' do
          expect(PackageMetadata::SyncService).to receive(:execute)
            .with(data_type: 'advisories', lease: lease)

          perform!
        end
      end

      shared_examples_for 'it does not sync' do
        it 'does not call sync service' do
          expect(PackageMetadata::SyncService).not_to receive(:execute)

          perform!
        end
      end

      context 'when neither dependency_scanning nor the dependency firewall is available' do
        before do
          stub_licensed_features(dependency_scanning: false)
          allow(::Security::DependencyFirewall::Availability).to receive(:instance_configurable?).and_return(false)
        end

        it_behaves_like 'it does not sync'
      end

      context 'when dependency_scanning is unavailable but the dependency firewall is (Premium)' do
        before do
          stub_licensed_features(dependency_scanning: false)
          allow(::Security::DependencyFirewall::Availability).to receive(:instance_configurable?).and_return(true)
          allow(Rails.env).to receive(:development?).and_return(false)
        end

        it_behaves_like 'it syncs'
      end

      context 'when the dependency_scanning feature is enabled' do
        before do
          stub_licensed_features(dependency_scanning: true)
        end

        context 'and rails is not development' do
          before do
            allow(Rails.env).to receive(:development?).and_return(false)
          end

          it_behaves_like 'it syncs'
        end

        context 'and rails is development' do
          before do
            allow(Rails.env).to receive(:development?).and_return(true)
          end

          context 'and sync in dev env variable is true' do
            before do
              stub_env('PM_SYNC_IN_DEV', true)
            end

            it_behaves_like 'it syncs'
          end

          context 'and sync in dev env variable is false' do
            before do
              stub_env('PM_SYNC_IN_DEV', false)
            end

            it_behaves_like 'it does not sync'
          end
        end
      end
    end

    describe 'routing' do
      # Every row of the table. An offline root follows the flag only once it holds a
      # v3 directory; without one the vendored v2 layout keeps syncing.
      where(:case_name, :vendored, :v3_vendored, :flag, :expected_service, :extra_args) do
        'vendored v3, flag on'  | true  | true  | true  | PackageMetadata::AdvisoryV3SyncService | {}
        'vendored v3, flag off' | true  | true  | false | PackageMetadata::SyncService           | { data_type: 'advisories' }
        'vendored v2, flag on'  | true  | false | true  | PackageMetadata::SyncService           | { data_type: 'advisories' }
        'vendored v2, flag off' | true  | false | false | PackageMetadata::SyncService           | { data_type: 'advisories' }
        'online, flag on'       | false | false | true  | PackageMetadata::AdvisoryV3SyncService | {}
        'online, flag off'      | false | false | false | PackageMetadata::SyncService           | { data_type: 'advisories' }
      end

      with_them do
        let(:other_service) do
          ([PackageMetadata::SyncService, PackageMetadata::AdvisoryV3SyncService] - [expected_service]).first
        end

        before do
          stub_licensed_features(dependency_scanning: true)
          stub_instance(flag: flag, vendored: vendored, v3_vendored: v3_vendored)
        end

        it 'routes to the sync service the config selects', :aggregate_failures do
          expect(other_service).not_to receive(:execute)
          expect(expected_service).to receive(:execute).with(**extra_args, lease: lease)

          perform!
        end
      end

      # No purl types means no configs, which must not read as v3: an air-gapped
      # install would then reach a service whose offline connector raises.
      context 'when no purl types are enabled' do
        before do
          stub_licensed_features(dependency_scanning: true)
          stub_instance(flag: true, purl_types: [])
        end

        it 'calls the v2 sync service', :aggregate_failures do
          expect(PackageMetadata::AdvisoryV3SyncService).not_to receive(:execute)
          expect(PackageMetadata::SyncService).to receive(:execute)
            .with(data_type: 'advisories', lease: lease)

          perform!
        end
      end
    end

    # A v2 run rewrites every column of an advisory it touches, so a field only v3
    # populates returns to NULL, and resuming v3 from its old bookmark would never
    # revisit those rows.
    describe 'the v3 bookmarks on a fallback to v2' do
      # Two purl types, neither of them the enabled one: the delete keys on data_type
      # and version_format only, so it must take every registry's bookmark whatever
      # the instance syncs.
      let_it_be(:v3_npm) { create(:pm_checkpoint, data_type: 'advisories', version_format: 'v3', purl_type: 'npm') }
      let_it_be(:v3_pypi) { create(:pm_checkpoint, data_type: 'advisories', version_format: 'v3', purl_type: 'pypi') }
      let_it_be(:v2_npm) { create(:pm_checkpoint, data_type: 'advisories', version_format: 'v2', purl_type: 'npm') }
      let_it_be(:v3_malware) do
        create(:pm_checkpoint, data_type: 'malware_advisories', version_format: 'v3', purl_type: 'npm')
      end

      before do
        stub_licensed_features(dependency_scanning: true)
        allow(PackageMetadata::SyncService).to receive(:execute)
        allow(PackageMetadata::AdvisoryV3SyncService).to receive(:execute)
      end

      shared_examples_for 'it drops them' do
        it 'deletes every v3 advisory bookmark and nothing else', :aggregate_failures do
          expect { perform! }.to change { PackageMetadata::Checkpoint.count }.by(-2)

          expect(PackageMetadata::Checkpoint.all).to contain_exactly(v2_npm, v3_malware)
        end

        it 'records how many it deleted' do
          expect(instance).to receive(:log_extra_metadata_on_done).with(:v3_advisory_checkpoints_deleted, 2)

          perform!
        end
      end

      context 'when the flag is off' do
        before do
          stub_instance(flag: false)
        end

        it_behaves_like 'it drops them'
      end

      context 'when a vendored v2 directory pins v2 while the flag is on' do
        before do
          stub_instance(flag: true, vendored: true, v3_vendored: false)
        end

        it_behaves_like 'it drops them'
      end

      context 'when the run stays on v3' do
        before do
          stub_instance(flag: true)
        end

        it 'keeps them' do
          expect { perform! }.not_to change { PackageMetadata::Checkpoint.count }
        end
      end

      # No purl types means nothing syncs, so there is nothing to compensate for.
      context 'when no purl types are enabled' do
        before do
          stub_instance(flag: false, purl_types: [])
        end

        it 'keeps them' do
          expect { perform! }.not_to change { PackageMetadata::Checkpoint.count }
        end
      end
    end

    context 'when there are no v3 advisory bookmarks' do
      before do
        stub_licensed_features(dependency_scanning: true)
        stub_instance(flag: false)
        allow(PackageMetadata::SyncService).to receive(:execute)
      end

      it 'logs no deleted count' do
        expect(instance).not_to receive(:log_extra_metadata_on_done)

        perform!
      end
    end
  end

  describe '#lease_timeout' do
    where(:flag, :expected) do
      true  | PackageMetadata::AdvisoryV3SyncService::MAX_LEASE_LENGTH
      false | PackageMetadata::SyncService::MAX_LEASE_LENGTH
    end

    with_them do
      before do
        stub_instance(flag: flag)
      end

      it 'matches the lease of the service it routes to' do
        expect(instance.send(:lease_timeout)).to eq(expected)
      end
    end

    # A run reads the config twice, to size the lease and to pick the route. A second
    # read is a chance for the two to disagree.
    it 'reads the config once per run' do
      stub_instance(flag: false)

      expect(PackageMetadata::SyncConfiguration).to receive(:configs_for).with('advisories').once.and_call_original

      instance.send(:lease_timeout)
      instance.send(:advisories_config)
    end
  end

  describe 'the cron tick' do
    subject(:perform!) { instance.perform }

    before do
      stub_licensed_features(dependency_scanning: true)
      stub_instance(flag: false)
      allow(Rails.env).to receive(:development?).and_return(false)
    end

    context 'on a self-managed instance' do
      before do
        allow(Gitlab).to receive(:com?).and_return(false)
      end

      # Without this every instance in the fleet calls PDS on the same tick.
      it 're-enqueues itself after the per-instance offset instead of syncing', :aggregate_failures do
        expect(described_class).to receive(:perform_in).with(instance.send(:jitter_offset), true)
        expect(PackageMetadata::SyncService).not_to receive(:execute)
        expect(PackageMetadata::AdvisoryV3SyncService).not_to receive(:execute)

        perform!
      end
    end

    context 'on GitLab.com' do
      before do
        allow(Gitlab).to receive(:com?).and_return(true)
      end

      it 'syncs on the tick, without jitter', :aggregate_failures do
        expect(described_class).not_to receive(:perform_in)
        expect(PackageMetadata::SyncService).to receive(:execute).with(data_type: 'advisories', lease: lease)

        perform!
      end
    end

    context 'when the license is unavailable' do
      before do
        stub_licensed_features(dependency_scanning: false)
        allow(::Security::DependencyFirewall::Availability).to receive(:instance_configurable?).and_return(false)
        allow(Gitlab).to receive(:com?).and_return(false)
      end

      it 'does not re-enqueue' do
        expect(described_class).not_to receive(:perform_in)

        perform!
      end
    end
  end
end
