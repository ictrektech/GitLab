# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Packages::Downloadable, feature_category: :package_registry do
  let(:throttle_period) { described_class::THROTTLE_PERIOD }

  context 'with a package', :aggregate_failures do
    let_it_be_with_reload(:package) { create(:generic_package) }

    shared_examples 'updating the last_downloaded_at column' do
      specify do
        expect(::Gitlab::Database::LoadBalancing::SessionMap.current(package.load_balancer))
          .to receive(:without_sticky_writes).and_call_original
        expect { execute }
          .to change { package.reload.last_downloaded_at }.from(nil).to(instance_of(ActiveSupport::TimeWithZone))
      end
    end

    shared_examples 'throttling the last_downloaded_at update' do
      it 'does not update again within the throttle period' do
        execute

        travel_to(throttle_period.from_now - 1.second) do
          expect { execute }.not_to change { package.reload.last_downloaded_at }
        end
      end

      it 'updates again once the throttle period has passed' do
        execute

        travel_to(throttle_period.from_now + 1.second) do
          expect { execute }.to change { package.reload.last_downloaded_at }
        end
      end
    end

    describe '#touch_last_downloaded_at' do
      # Not a memoized `subject`: the throttling examples call it more than once.
      def execute
        package.reload.touch_last_downloaded_at
      end

      it_behaves_like 'updating the last_downloaded_at column'
      it_behaves_like 'throttling the last_downloaded_at update'

      context 'when the timestamp is already fresh' do
        before do
          package.update_column(:last_downloaded_at, Time.current)
        end

        it 'short-circuits without issuing a database write' do
          expect(::Packages::Generic::Package).not_to receive(:touch_last_downloaded_at)

          expect { package.reload.touch_last_downloaded_at }
            .not_to change { package.reload.last_downloaded_at }
        end
      end
    end

    describe '.touch_last_downloaded_at' do
      # Not a memoized `subject`: the throttling examples call it more than once.
      def execute
        ::Packages::Generic::Package.touch_last_downloaded_at(package.id)
      end

      it_behaves_like 'updating the last_downloaded_at column'
      it_behaves_like 'throttling the last_downloaded_at update'

      it 'locks the row with FOR NO KEY UPDATE SKIP LOCKED in the id subquery' do
        recorder = ActiveRecord::QueryRecorder.new(skip_cached: true) { execute }

        expect(recorder.log).to include(
          a_string_matching(/UPDATE .* IN \(SELECT .*last_downloaded_at.* FOR NO KEY UPDATE SKIP LOCKED\)/)
        )
      end
    end
  end

  # Transactional tests hide the row from other connections, so this context commits its
  # data (:delete) and holds a real lock on the row from a second connection.
  context 'when another connection holds the row lock', :delete do
    let(:package) { create(:generic_package, last_downloaded_at: nil) }

    # Without a short timeout, a regression that blocks would hang the suite instead of failing.
    before do
      ::ApplicationRecord.connection.execute("SET statement_timeout = '5s'")
    end

    after do
      ::ApplicationRecord.connection.execute('RESET statement_timeout')
    end

    it 'skips the locked row and updates it once the lock is released', :aggregate_failures do
      blocker = ::ApplicationRecord.connection_pool.checkout

      begin
        blocker.begin_db_transaction
        blocker.execute("SELECT id FROM packages_packages WHERE id = #{blocker.quote(package.id)} FOR UPDATE")

        expect { expect(::Packages::Generic::Package.touch_last_downloaded_at(package.id)).to eq(0) }
          .not_to change { package.reload.last_downloaded_at }
      ensure
        blocker.rollback_db_transaction
        ::ApplicationRecord.connection_pool.checkin(blocker)
      end

      expect { expect(::Packages::Generic::Package.touch_last_downloaded_at(package.id)).to eq(1) }
        .to change { package.reload.last_downloaded_at }
    end

    it 'updates the row while another connection holds FOR KEY SHARE', :aggregate_failures do
      blocker = ::ApplicationRecord.connection_pool.checkout

      begin
        blocker.begin_db_transaction
        blocker.execute("SELECT id FROM packages_packages WHERE id = #{blocker.quote(package.id)} FOR KEY SHARE")

        expect { expect(::Packages::Generic::Package.touch_last_downloaded_at(package.id)).to eq(1) }
          .to change { package.reload.last_downloaded_at }
      ensure
        blocker.rollback_db_transaction
        ::ApplicationRecord.connection_pool.checkin(blocker)
      end
    end
  end
end
