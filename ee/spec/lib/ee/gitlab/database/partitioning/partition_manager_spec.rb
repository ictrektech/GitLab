# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Database::Partitioning::PartitionManager, feature_category: :geo_replication do
  include ::EE::GeoHelpers

  describe '#logical_replication_subscriber?' do
    subject(:logical_replication_subscriber) { described_class.new(model).send(:logical_replication_subscriber?) }

    let(:connection) { ApplicationRecord.connection }
    let(:model) { class_double(ApplicationRecord, table_name: 'foo', connection: connection) }

    let_it_be(:primary) { create(:geo_node, :primary) }
    let_it_be(:secondary) { create(:geo_node) }

    context 'on a Geo secondary' do
      before do
        stub_current_geo_node(secondary)
      end

      it { is_expected.to be(true) }

      it 'reads the current node from the database, not the memoized one' do
        allow(::Gitlab::Geo).to receive(:current_node).and_return(primary)

        expect(logical_replication_subscriber).to be(true)
      end

      it 'does not depend on the connection having run a query yet' do
        # Gitlab::Geo.connected? reports a connection Rails has not opened yet as inactive
        allow(::Gitlab::Geo).to receive(:connected?).and_return(false)

        expect(logical_replication_subscriber).to be(true)
      end

      context 'when the database it syncs is a streaming standby and main is not' do
        let(:connection) do
          instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter, pool: ApplicationRecord.connection_pool)
        end

        before do
          allow(connection).to receive(:select_value).with('SELECT pg_is_in_recovery()').and_return(true)
        end

        it { is_expected.to be(false) }
      end
    end

    context 'on a Geo primary' do
      before do
        stub_current_geo_node(primary)
      end

      it { is_expected.to be(false) }
    end

    context 'on an organization migration target cell' do
      before do
        stub_org_migration_target_cell(secondary)
      end

      it { is_expected.to be(false) }
    end

    context 'when the site cannot identify itself' do
      before do
        stub_current_geo_node(nil)
        allow(::Gitlab::Geo::LogicalReplication).to receive(:subscription_names)
          .with(connection).and_return(subscriptions)
      end

      context 'when its database has a subscription' do
        let(:subscriptions) { ['geo_subscription'] }

        it { is_expected.to be(true) }
      end

      context 'when its database has no subscription' do
        let(:subscriptions) { [] }

        it { is_expected.to be(false) }
      end
    end

    context 'when the Geo tables cannot be read' do
      before do
        stub_current_geo_node(secondary)
      end

      it 'is false without looking up the current node when geo_nodes does not exist' do
        allow(GeoNode).to receive(:table_exists?).and_return(false)

        expect(GeoNode).not_to receive(:current_node)
        expect(logical_replication_subscriber).to be(false)
      end

      it 'is false when the database cannot be reached' do
        allow(GeoNode).to receive(:table_exists?).and_raise(ActiveRecord::ConnectionNotEstablished)

        expect(logical_replication_subscriber).to be(false)
      end
    end
  end
end
