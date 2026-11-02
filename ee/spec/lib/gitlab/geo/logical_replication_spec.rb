# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Geo::LogicalReplication, feature_category: :geo_replication do
  let(:subscription_query) { described_class::SUBSCRIPTION_NAMES_SQL }

  describe '.active?' do
    using RSpec::Parameterized::TableSyntax

    subject(:active?) { described_class.active? }

    where(:configured?, :subscribed?, :expected) do
      true  | true  | true
      true  | false | false
      false | true  | false
      false | false | false
    end

    with_them do
      before do
        allow(described_class).to receive_messages(configured?: configured?, database_subscribed?: subscribed?)
      end

      it { is_expected.to be(expected) }
    end
  end

  describe '.in_use?' do
    using RSpec::Parameterized::TableSyntax

    subject(:in_use?) { described_class.in_use? }

    where(:configured?, :recovery?, :expected) do
      true  | false | true
      true  | true  | false
      false | false | false
      false | true  | false
    end

    with_them do
      before do
        allow(described_class).to receive(:configured?).and_return(configured?)
        allow(ApplicationRecord.database).to receive(:recovery?).and_return(recovery?)
      end

      it { is_expected.to be(expected) }
    end
  end

  describe '.subscriber?' do
    include ::EE::GeoHelpers

    subject(:subscriber?) { described_class.subscriber?(connection) }

    let(:connection) { ApplicationRecord.connection }

    let_it_be(:primary) { create(:geo_node, :primary) }
    let_it_be(:secondary) { create(:geo_node) }

    context 'on a Geo secondary' do
      before do
        stub_current_geo_node(secondary)
      end

      it { is_expected.to be(true) }

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(geo_postgresql_replication_agnostic: false)
        end

        it { is_expected.to be(true) }
      end

      context 'when the database is a streaming standby' do
        before do
          allow(connection).to receive(:select_value).and_call_original
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

    context 'when the site cannot identify itself' do
      before do
        stub_current_geo_node(nil)
        allow(described_class).to receive(:subscription_names).with(connection).and_return(subscriptions)
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
  end

  describe '.database_subscribed?' do
    subject(:database_subscribed?) { described_class.database_subscribed? }

    before do
      described_class.clear_memoization(:database_subscribed)
    end

    context 'when there are active subscriptions' do
      it 'returns true' do
        expect(ApplicationRecord.connection)
          .to receive(:select_values).with(subscription_query).and_return(%w[gitlab_subscription])
        expect(database_subscribed?).to be(true)
      end
    end

    context 'when there are no subscriptions' do
      it 'returns false' do
        expect(ApplicationRecord.connection)
          .to receive(:select_values).with(subscription_query).and_return([])
        expect(database_subscribed?).to be(false)
      end
    end

    context 'when the database connection is unavailable' do
      before do
        allow(ApplicationRecord.connection).to receive(:select_values).and_raise(
          ActiveRecord::ConnectionNotEstablished)
      end

      it { is_expected.to be(false) }

      it 'logs an error' do
        expect(Gitlab::Geo::Logger).to receive(:error)

        database_subscribed?
      end
    end

    context 'when the database connection failed' do
      before do
        allow(ApplicationRecord.connection).to receive(:select_values).and_raise(ActiveRecord::ConnectionFailed)
      end

      it { is_expected.to be(false) }

      it 'logs an error' do
        expect(Gitlab::Geo::Logger).to receive(:error)

        database_subscribed?
      end
    end

    context 'when the query fails' do
      before do
        allow(ApplicationRecord.connection).to receive(:select_values).and_raise(ActiveRecord::StatementInvalid)
      end

      it { is_expected.to be(false) }

      it 'logs an error' do
        expect(Gitlab::Geo::Logger).to receive(:error)

        database_subscribed?
      end
    end

    context 'when an unexpected error is raised' do
      before do
        allow(ApplicationRecord.connection).to receive(:select_values).and_raise(RuntimeError, 'unexpected')
      end

      it 'is not rescued' do
        expect { database_subscribed? }.to raise_error(RuntimeError, 'unexpected')
      end
    end
  end

  describe '.subscription_names' do
    it 'queries the connection it is given' do
      connection = instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)

      expect(connection).to receive(:select_values).with(subscription_query).and_return(%w[ci_subscription])

      expect(described_class.subscription_names(connection)).to eq(%w[ci_subscription])
    end

    it 'defaults to the main connection' do
      expect(ApplicationRecord.connection).to receive(:select_values).with(subscription_query).and_return([])

      expect(described_class.subscription_names).to eq([])
    end

    it 'does not rescue query failures' do
      connection = instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)

      allow(connection).to receive(:select_values).and_raise(ActiveRecord::ConnectionFailed)

      expect { described_class.subscription_names(connection) }.to raise_error(ActiveRecord::ConnectionFailed)
    end
  end

  describe '.active_subscriptions' do
    let(:main_connection) { instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) }
    let(:ci_connection) { instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) }

    before do
      allow(Gitlab::Database::EachDatabase).to receive(:each_connection)
        .with(include_shared: false)
        .and_yield(main_connection, 'main')
        .and_yield(ci_connection, 'ci')
    end

    it 'returns the subscriptions found per database, skipping databases without any' do
      allow(main_connection).to receive(:select_values).and_return(%w[main_subscription])
      allow(ci_connection).to receive(:select_values).and_return([])

      expect(described_class.active_subscriptions).to eq('main' => %w[main_subscription])
    end

    it 'returns an empty hash when no database has a subscription' do
      allow(main_connection).to receive(:select_values).and_return([])
      allow(ci_connection).to receive(:select_values).and_return([])

      expect(described_class.active_subscriptions).to eq({})
    end

    it 'reads the databases again on every call' do
      allow(main_connection).to receive(:select_values).and_return([], %w[main_subscription])
      allow(ci_connection).to receive(:select_values).and_return([])

      expect(described_class.active_subscriptions).to eq({})
      expect(described_class.active_subscriptions).to eq('main' => %w[main_subscription])
    end
  end

  describe '.ensure_no_active_subscription!' do
    context 'when no database has a subscription' do
      before do
        allow(described_class).to receive(:active_subscriptions).and_return({})
      end

      it 'does not raise' do
        expect { described_class.ensure_no_active_subscription! }.not_to raise_error
      end
    end

    context 'when a subscription is present' do
      before do
        allow(described_class).to receive(:active_subscriptions)
          .and_return('main' => %w[gitlab_subscription], 'ci' => %w[gitlab_ci_subscription])
      end

      it 'raises an ActiveSubscriptionError naming every database and subscription' do
        expect { described_class.ensure_no_active_subscription! }.to raise_error(
          described_class::ActiveSubscriptionError,
          /main: gitlab_subscription; ci: gitlab_ci_subscription/
        )
      end
    end
  end

  describe '.configured?' do
    using RSpec::Parameterized::TableSyntax

    subject(:configured?) { described_class.configured? }

    where(:secondary?, :flag_enabled?, :expected) do
      true  | true  | true
      true  | false | false
      false | true  | false
      false | false | false
    end

    with_them do
      before do
        allow(Gitlab::Geo).to receive_messages(secondary?: secondary?,
          postgresql_replication_agnostic_enabled?: flag_enabled?)
      end

      it { is_expected.to be(expected) }
    end
  end
end
