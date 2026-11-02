# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Admin::UsageTrendsController, :enable_admin_mode, feature_category: :devops_reports do
  let(:admin) { create(:user, :admin) }
  let(:target_id) { 'i_analytics_instance_statistics' }

  before do
    sign_in(admin)
  end

  describe 'GET #index' do
    it 'tracks unique visit if the format is HTML' do
      expect(Gitlab::Redis::HLL).to receive(:add).with(hash_including(key: a_string_including(target_id)))
      # allow other method calls in addition to the expected one
      allow(Gitlab::Redis::HLL).to receive(:add)

      get admin_usage_trends_path
    end

    it 'tracks unique visit if DNT is not enabled' do
      expect(Gitlab::Redis::HLL)
        .to receive(:add).with(hash_including(key: a_string_including(target_id), value: anything))
      allow(Gitlab::Redis::HLL).to receive(:add)

      get admin_usage_trends_path, headers: { 'DNT' => '0' }
    end

    it 'does not track unique visit if DNT is enabled' do
      expect(Gitlab::Redis::HLL).not_to receive(:add)

      get admin_usage_trends_path, headers: { 'DNT' => '1' }
    end

    it 'does not track unique visit if the format is JSON' do
      expect(Gitlab::Redis::HLL).not_to receive(:add)

      get admin_usage_trends_path(format: :json)
    end

    it_behaves_like 'Snowplow event tracking with RedisHLL context' do
      subject { get admin_usage_trends_path }

      let(:category) { described_class.name }
      let(:action) { 'perform_analytics_usage_action' }
      let(:label) { 'redis_hll_counters.analytics.analytics_total_unique_counts_monthly' }
      let(:property) { 'i_analytics_instance_statistics' }
      let(:namespace) { nil }
      let(:project) { nil }
      let(:user) { admin }
    end
  end
end
