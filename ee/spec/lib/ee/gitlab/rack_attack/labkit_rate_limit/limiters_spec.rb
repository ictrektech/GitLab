# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::RackAttack::LabkitRateLimit::Limiters, feature_category: :rate_limiting do
  before do
    described_class.reset!
  end

  after do
    described_class.reset!
  end

  describe 'classification selection', :clean_gitlab_redis_rate_limiting do
    include_context 'with labkit rate limit classification facts'

    let(:limiter) { described_class.all.fetch('rack_request_incident_management') }
    let(:alerts_notify) { { path: '/my-group/my-project/alerts/notify', method: 'POST' } }

    it 'claims an alerts/notify request while the setting is on' do
      expect(selected_in(limiter, **alerts_notify, setting_incident_management_notification: true))
        .to eq('incident_management_notification_web')
    end

    # The setting gates the only rule in this limiter, so nothing here counts the
    # request. The general web throttles still match it in their own limiter.
    it 'leaves the limiter unmatched once the setting is off' do
      expect(selected_in(limiter, **alerts_notify, setting_incident_management_notification: false)).to be_nil
    end
  end
end
