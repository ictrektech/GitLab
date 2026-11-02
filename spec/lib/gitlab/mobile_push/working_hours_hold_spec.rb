# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::MobilePush::WorkingHoursHold, :clean_gitlab_redis_shared_state, feature_category: :notifications do
  let(:now) { Time.utc(2026, 10, 7, 7, 0) }

  it 'lists users once their resume time has passed' do
    described_class.record(1, now)
    described_class.record(2, now + 1.hour)

    expect(described_class.due_user_ids(now - 1.second, limit: 10)).to be_empty
    expect(described_class.due_user_ids(now, limit: 10)).to eq([1])
    expect(described_class.due_user_ids(now + 1.hour, limit: 10)).to contain_exactly(1, 2)
  end

  it 'lets the set expire after the latest possible resume time' do
    described_class.record(1, now)

    ttl = Gitlab::Redis::SharedState.with { |redis| redis.ttl(described_class::RESUME_SET) }

    expect(ttl).to be_between(described_class::RESUME_SET_TTL.to_i - 5, described_class::RESUME_SET_TTL.to_i)
  end

  it 'moves the resume time when a user is recorded again' do
    described_class.record(1, now)
    described_class.record(1, now + 2.hours)

    expect(described_class.due_user_ids(now, limit: 10)).to be_empty
    expect(described_class.due_user_ids(now + 2.hours, limit: 10)).to eq([1])
  end

  it 'returns at most the requested number of due users' do
    [1, 2, 3].each { |id| described_class.record(id, now) }

    expect(described_class.due_user_ids(now, limit: 2).size).to eq(2)
  end
end
