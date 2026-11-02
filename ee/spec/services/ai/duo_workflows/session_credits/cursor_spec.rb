# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::SessionCredits::Cursor, :click_house, :clean_gitlab_redis_shared_state,
  :freeze_time, feature_category: :duo_agent_platform do
  let(:root_namespace_id) { 42 }
  let(:cursor) { described_class.new(root_namespace_id) }

  describe '#key' do
    it 'is the v2 prefix plus the root namespace id' do
      expect(cursor.key).to eq('duo_workflow_session_credits_v2_42')
    end

    it 'uses an explicit instance key on self-managed' do
      expect(described_class.new(nil).key).to eq('duo_workflow_session_credits_v2_instance')
    end
  end

  describe '#updated_after' do
    it 'seeds just inside the CustomersDot window when nothing is stored' do
      expect(cursor.value_us).to eq(0)
      expect(cursor.updated_after).to eq(described_class.seed_time)
      expect(described_class.seed_time).to be > 90.days.ago
      expect(described_class.seed_time).to be < 89.days.ago
    end

    it 'keeps the same window for the life of the cursor, so every page asks the same updatedAfter' do
      first = cursor.updated_after
      allow(described_class).to receive(:seed_time).and_return(1.hour.ago)

      expect(cursor.updated_after).to eq(first)
    end

    it 'reseeds a stored cursor that fell out of the window instead of failing forever' do
      ClickHouse::SyncCursor.update_cursor_for(cursor.key, (91.days.ago.to_r * 1_000_000).to_i)

      expect(cursor.updated_after).to eq(described_class.seed_time)
    end

    it 'returns the stored microsecond cursor as a time' do
      stored = Time.utc(2026, 10, 1, 12, 0, 0, 123_456)
      ClickHouse::SyncCursor.update_cursor_for(cursor.key, (stored.to_r * 1_000_000).to_i)

      expect(cursor.updated_after).to eq(stored)
    end
  end

  describe '#stale?' do
    it 'is false when unset or inside the window' do
      expect(cursor).not_to be_stale

      ClickHouse::SyncCursor.update_cursor_for(cursor.key, (89.days.ago.to_r * 1_000_000).to_i)
      expect(described_class.new(root_namespace_id)).not_to be_stale
    end

    it 'is true for a stored cursor at or beyond the window' do
      ClickHouse::SyncCursor.update_cursor_for(cursor.key, (90.days.ago.to_r * 1_000_000).to_i)

      expect(cursor).to be_stale
    end
  end

  describe '#advance!' do
    it 'stores the microseconds and is read back by a fresh cursor' do
      cursor.advance!(1_791_022_560_000_001)

      expect(described_class.new(root_namespace_id).value_us).to eq(1_791_022_560_000_001)
    end
  end

  describe 'after token' do
    it 'is nil when nothing is stored' do
      expect(cursor.after_token).to be_nil
    end

    it 'resumes with the window the token was issued for, not a drifted seed' do
      window = cursor.updated_after
      cursor.store_after_token('opaque-cursor')
      allow(described_class).to receive(:seed_time).and_return(1.hour.ago)

      resumed = described_class.new(root_namespace_id)

      expect(resumed.after_token).to eq('opaque-cursor')
      expect(resumed.updated_after).to eq(window)
    end

    it 'drops a token whose window is about to fall out of the CustomersDot limit and reseeds',
      :aggregate_failures do
      expired_window_us = ((described_class.token_window_floor - 1.second).to_r * 1_000_000).to_i
      Gitlab::Redis::SharedState.with do |redis|
        redis.set(cursor.after_token_key, Gitlab::Json.dump({ c: 'opaque-cursor', u: expired_window_us }))
      end

      expect(cursor.after_token).to be_nil
      expect(cursor.updated_after).to eq(described_class.seed_time)
      expect(cursor).to be_reseeded
      expect(Gitlab::Redis::SharedState.with { |redis| redis.exists?(cursor.after_token_key) }).to be(false)
    end

    it 'is not a reseed when the token window is still inside the limit' do
      cursor.store_after_token('opaque-cursor')

      resumed = described_class.new(root_namespace_id)

      expect(resumed.after_token).to eq('opaque-cursor')
      expect(resumed).not_to be_reseeded
    end

    it 'ignores a token it cannot parse, so a corrupt value only costs a window re-read' do
      Gitlab::Redis::SharedState.with { |redis| redis.set(cursor.after_token_key, 'not json') }

      expect(cursor.after_token).to be_nil
      expect(cursor.updated_after).to eq(described_class.seed_time)
    end

    it 'keeps the current window when a stored token carries none' do
      Gitlab::Redis::SharedState.with { |redis| redis.set(cursor.after_token_key, '{"c":"opaque-cursor"}') }

      expect(cursor.after_token).to eq('opaque-cursor')
      expect(cursor.updated_after).to eq(described_class.seed_time)
    end

    it 'round-trips the token for the current window and clears it' do
      cursor.store_after_token('opaque-cursor')

      expect(described_class.new(root_namespace_id).after_token).to eq('opaque-cursor')

      cursor.clear_after_token

      expect(described_class.new(root_namespace_id).after_token).to be_nil
    end

    it 'keeps the token across a partial advance, so a long drain resumes where it stopped' do
      window = cursor.updated_after
      cursor.store_after_token('opaque-cursor')
      cursor.advance!(1_791_022_560_000_001)

      resumed = described_class.new(root_namespace_id)

      expect(resumed.after_token).to eq('opaque-cursor')
      expect(resumed.updated_after).to eq(window)
    end

    it 'keeps the pinned window when the cursor advances mid-drain' do
      window = cursor.updated_after

      cursor.advance!(1_791_022_560_000_001)

      expect(cursor.updated_after).to eq(window)
      expect(cursor.position_time).to eq(Time.zone.at(Rational(1_791_022_560_000_001, 1_000_000)))
    end

    it 'expires the token' do
      cursor.store_after_token('opaque-cursor')

      ttl = Gitlab::Redis::SharedState.with { |redis| redis.ttl(cursor.after_token_key) }
      expect(ttl).to be_within(5).of(described_class::AFTER_TOKEN_TTL.to_i)
    end
  end
end
