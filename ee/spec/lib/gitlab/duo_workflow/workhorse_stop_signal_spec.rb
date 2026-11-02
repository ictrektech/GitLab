# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::DuoWorkflow::WorkhorseStopSignal, :clean_gitlab_redis_shared_state,
  feature_category: :duo_agent_platform do
  let(:workflow_id) { 42 }
  let(:key) { 'workhorse:duoworkflow:stop:42' }

  def stored(&block)
    Gitlab::Redis::Workhorse.with(&block)
  end

  shared_examples 'best effort' do |workhorse_method|
    where(:error) do
      [
        [::Redis::CannotConnectError.new('redis down')],
        [::RedisClient::CannotConnectError.new('redis down')]
      ]
    end

    with_them do
      before do
        allow(Gitlab::Workhorse).to receive(workhorse_method).and_raise(error)
      end

      it 'reports the error instead of raising it' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error, workflow_id: workflow_id)

        expect(call).to be_nil
      end
    end
  end

  describe '.set' do
    subject(:call) { described_class.set(workflow_id) }

    it 'sets the key Workhorse checks, expiring after the longest server-side run' do
      call

      expect(stored { |redis| redis.exists?(key) }).to be(true)
      expect(stored { |redis| redis.ttl(key) }).to be_within(5).of(1.hour.to_i)
    end

    it_behaves_like 'best effort', :set_key_and_notify
  end

  describe '.clear' do
    subject(:call) { described_class.clear(workflow_id) }

    it 'removes the key' do
      described_class.set(workflow_id)

      expect { call }.to change { stored { |redis| redis.exists?(key) } }.from(true).to(false)
    end

    it_behaves_like 'best effort', :cleanup_key
  end
end
