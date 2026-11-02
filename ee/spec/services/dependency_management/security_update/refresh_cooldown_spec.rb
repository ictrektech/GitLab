# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DependencyManagement::SecurityUpdate::RefreshCooldown, :clean_gitlab_redis_shared_state,
  feature_category: :dependency_management do
  let_it_be(:merge_request) { create(:merge_request) }
  let_it_be(:other_merge_request) { create(:merge_request) }

  def ttl_for(record)
    Gitlab::Redis::SharedState.with do |redis|
      redis.ttl("#{described_class::KEY_PREFIX}:#{record.id}")
    end
  end

  def conflict_ttl(record)
    Gitlab::Redis::SharedState.with do |redis|
      redis.ttl("#{described_class::CONFLICT_KEY_PREFIX}:#{record.id}:#{record.source_branch_sha}")
    end
  end

  def conflict_head(record, sha)
    instance_double(MergeRequest, id: record.id, source_branch_sha: sha)
  end

  describe '.elapsed?' do
    it 'is true when no window is open' do
      expect(described_class.elapsed?(merge_request)).to be(true)
    end

    it 'is false for the rest of the window it just consumed' do
      described_class.elapsed?(merge_request)

      expect(described_class.elapsed?(merge_request)).to be(false)
    end

    it 'tracks each merge request separately' do
      described_class.elapsed?(merge_request)

      expect(described_class.elapsed?(other_merge_request)).to be(true)
    end

    it 'opens a window lasting the full period' do
      described_class.elapsed?(merge_request)

      expect(ttl_for(merge_request)).to be_within(5).of(described_class::PERIOD.to_i)
    end

    it 'does not push out a window that is already open' do
      described_class.elapsed?(merge_request)

      Gitlab::Redis::SharedState.with do |redis|
        redis.expire("#{described_class::KEY_PREFIX}:#{merge_request.id}", 60)
      end

      described_class.elapsed?(merge_request)

      expect(ttl_for(merge_request)).to be_within(5).of(60)
    end

    it 'is true again once the window has expired' do
      described_class.elapsed?(merge_request)

      Gitlab::Redis::SharedState.with do |redis|
        redis.del("#{described_class::KEY_PREFIX}:#{merge_request.id}")
      end

      expect(described_class.elapsed?(merge_request)).to be(true)
    end
  end

  describe '.conflict_refresh_due?' do
    let(:head_a) { conflict_head(merge_request, 'head-a') }

    it 'is true when the branch head has had no conflict refresh' do
      expect(described_class.conflict_refresh_due?(head_a)).to be(true)
    end

    it 'is false for the rest of the period once the head is claimed' do
      described_class.conflict_refresh_due?(head_a)

      expect(described_class.conflict_refresh_due?(head_a)).to be(false)
    end

    it 'is true again once a commit moves the branch head' do
      described_class.conflict_refresh_due?(head_a)

      expect(described_class.conflict_refresh_due?(conflict_head(merge_request, 'head-b'))).to be(true)
    end

    it 'tracks each merge request separately' do
      described_class.conflict_refresh_due?(head_a)

      expect(described_class.conflict_refresh_due?(conflict_head(other_merge_request, 'head-a'))).to be(true)
    end

    it 'claims the head for the full period' do
      described_class.conflict_refresh_due?(head_a)

      expect(conflict_ttl(head_a)).to be_within(5).of(described_class::PERIOD.to_i)
    end

    it 'does not push out a claim that is already held' do
      described_class.conflict_refresh_due?(head_a)

      Gitlab::Redis::SharedState.with do |redis|
        redis.expire("#{described_class::CONFLICT_KEY_PREFIX}:#{merge_request.id}:head-a", 60)
      end

      described_class.conflict_refresh_due?(head_a)

      expect(conflict_ttl(head_a)).to be_within(5).of(60)
    end

    it 'is false once a cooldown refresh holds the head' do
      described_class.hold_head(head_a)

      expect(described_class.conflict_refresh_due?(head_a)).to be(false)
    end

    it 'is false when the merge request has no branch head' do
      expect(described_class.conflict_refresh_due?(conflict_head(merge_request, nil))).to be(false)
    end

    it 'leaves the refresh cooldown to its caller' do
      described_class.conflict_refresh_due?(head_a)

      expect(described_class.elapsed?(merge_request)).to be(true)
    end
  end

  describe '.hold_head' do
    let(:head_a) { conflict_head(merge_request, 'head-a') }

    it 'holds the head for the full period, even over an existing claim' do
      described_class.conflict_refresh_due?(head_a)

      Gitlab::Redis::SharedState.with do |redis|
        redis.expire("#{described_class::CONFLICT_KEY_PREFIX}:#{merge_request.id}:head-a", 60)
      end

      described_class.hold_head(head_a)

      expect(conflict_ttl(head_a)).to be_within(5).of(described_class::PERIOD.to_i)
    end

    it 'writes nothing when the merge request has no branch head' do
      described_class.hold_head(conflict_head(merge_request, nil))

      written = Gitlab::Redis::SharedState.with do |redis|
        redis.exists?("#{described_class::CONFLICT_KEY_PREFIX}:#{merge_request.id}:")
      end

      expect(written).to be(false)
    end
  end

  describe '.release_head' do
    let(:head_a) { conflict_head(merge_request, 'head-a') }

    it 'frees a held head for a conflict refresh' do
      described_class.hold_head(head_a)

      described_class.release_head(head_a)

      expect(described_class.conflict_refresh_due?(head_a)).to be(true)
    end

    it 'leaves other heads held' do
      described_class.hold_head(head_a)

      described_class.release_head(conflict_head(merge_request, 'head-b'))

      expect(described_class.conflict_refresh_due?(head_a)).to be(false)
    end

    it 'does nothing when the merge request has no branch head' do
      expect(Gitlab::Redis::SharedState).not_to receive(:with)

      described_class.release_head(conflict_head(merge_request, nil))
    end
  end

  context 'when Redis is unreachable' do
    before do
      allow(Gitlab::Redis::SharedState).to receive(:with).and_raise(Redis::BaseError)
    end

    it 'reports the window as not elapsed rather than raising' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)

      expect(described_class.elapsed?(merge_request)).to be(false)
    end

    it 'does not raise when starting a window' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)

      expect { described_class.start(merge_request) }.not_to raise_error
    end

    it 'reports the conflict refresh as not due rather than raising' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)

      expect(described_class.conflict_refresh_due?(conflict_head(merge_request, 'head-a'))).to be(false)
    end

    it 'does not raise when a cooldown refresh holds the head' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)

      expect { described_class.hold_head(conflict_head(merge_request, 'head-a')) }.not_to raise_error
    end

    it 'does not raise when a skipped refresh releases the head' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)

      expect { described_class.release_head(conflict_head(merge_request, 'head-a')) }.not_to raise_error
    end
  end

  describe '.start' do
    it 'closes the window so the merge request is not immediately re-resolved' do
      described_class.start(merge_request)

      expect(described_class.elapsed?(merge_request)).to be(false)
    end

    it 'restarts a window that is already open' do
      described_class.elapsed?(merge_request)

      Gitlab::Redis::SharedState.with do |redis|
        redis.expire("#{described_class::KEY_PREFIX}:#{merge_request.id}", 60)
      end

      described_class.start(merge_request)

      expect(ttl_for(merge_request)).to be_within(5).of(described_class::PERIOD.to_i)
    end
  end
end
