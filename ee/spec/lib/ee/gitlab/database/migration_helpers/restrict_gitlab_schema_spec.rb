# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Database::MigrationHelpers::RestrictGitlabSchema, :use_clean_rails_redis_caching,
  query_analyzers: false, feature_category: :geo_replication do
  include EE::GeoHelpers

  let(:migration_class) do
    Class.new(Gitlab::Database::Migration[2.0]) do
      def up; end
      def down; end
    end
  end

  let(:subscription_names) { ['geo_subscription'] }

  around do |example|
    verbose_was = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false

    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose_was
  end

  before do
    allow(Gitlab::Geo::LogicalReplication).to receive(:subscription_names).and_return(subscription_names)
    stub_current_geo_node(create(:geo_node))
  end

  shared_examples 'a migration that runs' do
    it 'runs the migration' do
      expect_next_instance_of(migration_class) do |migration|
        expect(migration).to receive(:up)
      end

      migration_class.migrate(:up)
    end
  end

  context 'with a data migration' do
    before do
      migration_class.restrict_gitlab_migration gitlab_schema: :gitlab_main
    end

    context 'on a Geo secondary whose database is a logical replication subscriber' do
      it 'skips the migration in both directions' do
        expect_next_instance_of(migration_class) do |migration|
          expect(migration).to receive(:say).with(/receives data changes from the primary through logical replication/)
          expect(migration).not_to receive(:up)
        end

        migration_class.migrate(:up)

        expect_next_instance_of(migration_class) do |migration|
          expect(migration).not_to receive(:down)
        end

        migration_class.migrate(:down)
      end

      it 'checks the subscription on the connection being migrated' do
        expect_next_instance_of(migration_class) do |migration|
          expect(migration).to receive(:exec_migration).and_wrap_original do |original, conn, direction|
            expect(Gitlab::Geo::LogicalReplication).to receive(:subscription_names).with(conn)
              .and_return(subscription_names)

            original.call(conn, direction)
          end
          expect(migration).not_to receive(:up)
        end

        migration_class.migrate(:up)
      end

      context 'when the subscription cannot be read' do
        before do
          allow(Gitlab::Geo::LogicalReplication).to receive(:subscription_names)
            .and_raise(ActiveRecord::StatementInvalid, 'boom')
        end

        it 'aborts the migration' do
          expect { migration_class.migrate(:up) }.to raise_error(ActiveRecord::StatementInvalid, /boom/)
        end
      end

      context 'when the Geo site cannot be read' do
        before do
          allow(GeoNode).to receive(:current_node).and_raise(ActiveRecord::StatementInvalid, 'boom')
        end

        it 'aborts the migration' do
          expect { migration_class.migrate(:up) }.to raise_error(ActiveRecord::StatementInvalid, /boom/)
        end
      end

      context 'when this site does not match a Geo site' do
        before do
          stub_current_geo_node(nil)
        end

        it 'aborts the migration' do
          expect { migration_class.migrate(:up) }
            .to raise_error(described_class::UnknownGeoSiteError, /does not match a Geo site/)
        end
      end
    end

    context 'when the database has no subscription' do
      let(:subscription_names) { [] }

      it 'does not look up the Geo site' do
        expect(GeoNode).not_to receive(:current_node)

        migration_class.migrate(:up)
      end

      it_behaves_like 'a migration that runs'
    end

    context 'on a Geo primary' do
      before do
        stub_current_geo_node(create(:geo_node, :primary))
      end

      it_behaves_like 'a migration that runs'
    end

    context 'on an org migration target cell' do
      before do
        stub_org_migration_target_cell
      end

      it_behaves_like 'a migration that runs'
    end

    context 'when the migration targets a schema this database does not own' do
      it 'leaves the skip to the decomposition check' do
        expect(Gitlab::Geo::LogicalReplication).not_to receive(:subscription_names)

        expect_next_instance_of(migration_class) do |migration|
          allow(migration).to receive(:unmatched_schemas).and_return([:gitlab_main])
          expect(migration).to receive(:migration_skipped)
          expect(migration).not_to receive(:up)
        end

        migration_class.migrate(:up)
      end
    end
  end

  context 'with a schema migration' do
    it 'does not check for a subscription' do
      expect(Gitlab::Geo::LogicalReplication).not_to receive(:subscription_names)

      migration_class.migrate(:up)
    end

    it_behaves_like 'a migration that runs'
  end
end
