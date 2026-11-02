# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::SessionCredits::SyncPause, :clean_gitlab_redis_shared_state,
  feature_category: :duo_agent_platform do
  def ttl_of(source)
    Gitlab::Redis::SharedState.with { |redis| redis.ttl(described_class.key(source)) }
  end

  it 'is not paused until asked' do
    expect(described_class.reason(source: '42')).to be_nil
  end

  it 'pauses one source for the given duration and leaves the others alone', :aggregate_failures do
    described_class.pause!(source: '42', reason: :disabled, duration: 2.hours)

    expect(described_class.reason(source: '42')).to eq(:disabled)
    expect(ttl_of('42')).to be_between(2.hours.to_i - 5, 2.hours.to_i)
    expect(described_class.reason(source: '43')).to be_nil
    expect(described_class.reason(source: 'instance')).to be_nil
  end

  it 'is lifted by clear!' do
    described_class.pause!(source: '42', reason: :disabled, duration: 2.hours)
    described_class.clear!(source: '42')

    expect(described_class.reason(source: '42')).to be_nil
  end

  it 'treats a Redis failure as not paused instead of raising', :aggregate_failures do
    allow(Gitlab::Redis::SharedState).to receive(:with).and_raise(::Redis::CannotConnectError)

    expect(Gitlab::ErrorTracking).to receive(:track_exception).twice

    expect { described_class.pause!(source: '42', reason: :disabled, duration: 2.hours) }.not_to raise_error
    expect(described_class.reason(source: '42')).to be_nil
  end

  it 'keys by source under one hash tag', :aggregate_failures do
    expect(described_class.key('42')).to eq('duo_workflow_session_credits_v2:{pause}:42')
    expect(described_class.key('instance')).to eq('duo_workflow_session_credits_v2:{pause}:instance')
  end
end
