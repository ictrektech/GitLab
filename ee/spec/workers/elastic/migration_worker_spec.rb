# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Elastic::MigrationWorker, :clean_gitlab_redis_shared_state, feature_category: :global_search do
  include ExclusiveLeaseHelpers

  subject(:worker) { described_class.new }

  let(:logger) { ::Gitlab::Elasticsearch::Logger.build }
  let(:helper) { ::Search::Elastic::Helper.default }

  before do
    allow(Search::ClusterHealthCheck::Elastic).to receive(:healthy?).and_return(true)
    allow(::Search::Elastic::Helper).to receive(:default).and_return(helper)
    allow(helper).to receive_messages(unsupported_version?: false, alias_exists?: true, migrations_index_exists?: true)
  end

  describe '#perform' do
    let(:migration) { Elastic::DataMigrationService.migrations(exclude_skipped: true).last }

    before do
      stub_ee_application_setting(elasticsearch_indexing: true)
    end

    context 'when application setting `elastic_migration_worker_enabled` is false' do
      before do
        stub_ee_application_setting(elastic_migration_worker_enabled: false)
      end

      it 'returns with no execution' do
        expect(worker).not_to receive(:execute_migration)
        expect(worker.perform).to be_falsey
      end
    end

    context 'when indexing is disabled' do
      before do
        stub_ee_application_setting(elasticsearch_indexing: false)
      end

      it 'returns without execution' do
        expect(worker).not_to receive(:execute_migration)
        expect(worker.perform).to be_falsey
      end
    end

    context 'when on an unsupported elasticsearch version' do
      before do
        allow(helper).to receive(:unsupported_version?).and_return(true)
      end

      it 'pauses indexing and does not execute migration' do
        expect(Gitlab::CurrentSettings).to receive(:update!).with(elasticsearch_advanced_search_pause_indexing: true)
        expect(worker).not_to receive(:execute_migration)
        expect(worker.perform).to be_falsey
      end
    end

    context 'when cluster is unhealthy' do
      before do
        allow(Search::ClusterHealthCheck::Elastic).to receive(:healthy?).and_return(false)
        allow(::Gitlab::Elasticsearch::Logger).to receive(:build).and_return(logger)
      end

      it 'raises an error and does not execute migration' do
        expect(worker).not_to receive(:execute_migration)
        expect(logger).to receive(:error)
        expect(worker.perform).to be_falsey
      end
    end

    context 'when reindexing task is in progress' do
      it 'returns without execution' do
        create(:elastic_reindexing_task)

        expect(worker).not_to receive(:execute_migration)
        expect(worker.perform).to be_falsey
      end
    end

    context 'when indexing is enabled' do
      context 'when an unexecuted migration present', :elastic_clean do
        before do
          allow(Elastic::MigrationRecord).to receive(:current_migration).and_return(migration)
        end

        context 'when migrations index does not exist' do
          it 'skips execution' do
            allow(helper).to receive(:migrations_index_exists?).and_return(false)
            expect(helper).not_to receive(:create_migrations_index)

            expect(worker.perform).to be_falsey
          end
        end

        context 'when migration is halted' do
          using RSpec::Parameterized::TableSyntax

          where(:pause_indexing, :halted_indexing_unpaused, :unpause) do
            false | false | false
            false | true  | false
            true  | false | true
            true  | true  | false
          end

          with_them do
            before do
              allow(Gitlab::CurrentSettings).to receive(:advanced_search_indexing_paused?).and_return(true)
              allow(migration).to receive(:pause_indexing?).and_return(true)
              migration.save_state!(halted: true, pause_indexing: pause_indexing,
                halted_indexing_unpaused: halted_indexing_unpaused)
            end

            it 'unpauses indexing' do
              if unpause
                expect(Gitlab::CurrentSettings).to receive(:update!).with(
                  elasticsearch_advanced_search_pause_indexing: false
                )
              else
                expect(Gitlab::CurrentSettings).not_to receive(:update!)
              end

              expect(migration).not_to receive(:migrate)

              worker.perform
            end
          end
        end

        context 'when executing migration with retry_on_failure set' do
          before do
            allow(migration).to receive_messages(started?: true, retry_on_failure?: true, max_attempts: 2)
            allow(migration).to receive(:migrate).and_raise(StandardError)
            allow(::Gitlab::Elasticsearch::Logger).to receive(:build).and_return(logger)
          end

          it 'increases previous_attempts on failure' do
            worker.perform

            expect(migration.migration_state).to match(a_hash_including(previous_attempts: 1))
          end

          it 'fails the migration if max_attempts is exceeded' do
            migration.set_migration_state(previous_attempts: 2)

            expect(logger).to receive(:error).twice.and_call_original
            worker.perform

            expect(migration.halted?).to be_truthy
            expect(migration.failed?).to be_truthy
          end
        end

        context 'for migration process' do
          before do
            # retry_on_failure is tested in the context above
            allow(migration).to receive_messages(started?: started, completed?: completed, batched?: batched,
              retry_on_failure?: false)
          end

          using RSpec::Parameterized::TableSyntax

          # completed is evaluated after migrate method is executed
          where(:started, :completed, :execute_migration, :batched) do
            false | false | true  | false
            false | true  | true  | false
            false | false | true  | true
            false | true  | true  | true
            true  | false | false | false
            true  | true  | false | false
            true  | false | true  | true
            true  | true  | true | true
          end

          with_them do
            it 'calls migration only when needed', :aggregate_failures do
              if execute_migration
                expect(migration).to receive(:migrate).once
              else
                expect(migration).not_to receive(:migrate)
              end

              expect(migration).to receive(:save!).with(completed: completed)
              expect(Elastic::DataMigrationService).to receive(:drop_migration_has_finished_cache!).with(migration)

              worker.perform
            end

            it 'handles batched migrations' do
              if batched && !completed
                expect(Elastic::MigrationWorker).to receive(:perform_in)
                  .with(migration.throttle_delay)
              else
                expect(Elastic::MigrationWorker).not_to receive(:perform_in)
              end

              worker.perform
            end
          end

          context 'when indexing paused' do
            before do
              allow(migration).to receive(:pause_indexing?).and_return(true)
            end

            let(:batched) { true }

            where(:started, :completed, :expected) do
              false | false | false
              true  | false | false
              true  | true  | true
            end

            with_them do
              it 'pauses and unpauses indexing' do
                expect(Gitlab::CurrentSettings).to receive(:update!).with(
                  elasticsearch_advanced_search_pause_indexing: true
                )

                if expected
                  expect(Gitlab::CurrentSettings).to receive(:update!).with(
                    elasticsearch_advanced_search_pause_indexing: false
                  )
                end

                worker.perform
              end
            end
          end

          context 'when space_requirements migration option is set' do
            let(:started) { false }
            let(:completed) { false }
            let(:batched) { false }

            before do
              allow(migration).to receive_messages(space_requirements?: true, space_required_bytes: 10)
            end

            it 'halts the migration if there is not enough space' do
              allow(helper).to receive(:cluster_free_size_bytes).and_return(5)
              expect(migration).to receive(:halt)
              expect(migration).not_to receive(:migrate)

              worker.perform
            end

            it 'runs the migration if there is enough space' do
              allow(helper).to receive(:cluster_free_size_bytes).and_return(20)
              expect(migration).not_to receive(:fail)
              expect(migration).to receive(:migrate).once

              worker.perform
            end

            context 'when migration is already started' do
              let(:started) { true }

              it 'does not check space requirements' do
                expect(helper).not_to receive(:cluster_free_size_bytes)
                expect(migration).not_to receive(:space_required_bytes)

                worker.perform
              end
            end
          end
        end

        context 'for batch cadence' do
          let(:throttle_key) { "elastic/migration_worker:throttle:#{migration.name_for_key}" }

          before do
            allow(migration).to receive_messages(started?: true, completed?: false, batched?: true,
              retry_on_failure?: false, pause_indexing?: false, throttle_delay: 1.minute)
            allow(migration).to receive(:save!)
            allow(described_class).to receive(:perform_in)
          end

          it 'runs one batch per throttle_delay however many invocations arrive in the window' do
            expect(migration).to receive(:migrate).once

            3.times { described_class.new.perform }
          end

          it 'runs the next batch once the window has elapsed' do
            expect(migration).to receive(:migrate).twice

            described_class.new.perform
            # Standing in for the TTL expiring, which is wall-clock in Redis and cannot be travelled past.
            Gitlab::ExclusiveLease.cancel(throttle_key, Gitlab::ExclusiveLease.get_uuid(throttle_key))
            described_class.new.perform
          end

          it 'leaves the window short of throttle_delay so a self-enqueued successor is not throttled' do
            expect_to_obtain_exclusive_lease(throttle_key, timeout: 59)

            described_class.new.perform
          end

          it 'keeps the throttle lease shorter than MINIMUM_THROTTLE_DELAY' do
            allow(migration).to receive(:throttle_delay).and_return(Elastic::MigrationOptions::MINIMUM_THROTTLE_DELAY)

            expect_to_obtain_exclusive_lease(throttle_key, timeout: 1)

            described_class.new.perform
          end

          it 'throttles when the lease is already held elsewhere' do
            Gitlab::ExclusiveLease.new(throttle_key, timeout: 60).try_obtain

            expect(migration).not_to receive(:migrate)
            expect(described_class).not_to receive(:perform_in)

            described_class.new.perform
          end

          it 'takes the lease only after the batch finishes' do
            expect(migration).to receive(:migrate) do
              expect(Gitlab::ExclusiveLease.get_uuid(throttle_key)).to be_falsey
            end

            described_class.new.perform

            expect(Gitlab::ExclusiveLease.get_uuid(throttle_key)).to be_present
          end

          it 'does not throttle an unbatched migration' do
            allow(migration).to receive_messages(batched?: false, started?: false)
            Gitlab::ExclusiveLease.new(throttle_key, timeout: 60).try_obtain

            expect(migration).to receive(:migrate).twice

            2.times { described_class.new.perform }
          end
        end
      end

      context 'when there are no unexecuted migrations' do
        before do
          allow(Elastic::MigrationRecord).to receive(:current_migration).and_return(nil)
        end

        it 'skips execution' do
          expect(worker).not_to receive(:execute_migration)

          expect(worker.perform).to be_falsey
        end
      end

      context 'when there are no executed migrations' do
        before do
          allow(Elastic::MigrationRecord).to receive(:load_versions).and_return([])
          allow(Elastic::DataMigrationService).to receive(:migrations).and_return([migration])
          allow(migration).to receive_messages(space_requirements?: false, started?: false, batched?: false)
        end

        it 'executes the first migration' do
          expect(worker).to receive(:execute_migration).with(migration)

          worker.perform
        end
      end
    end
  end
end
