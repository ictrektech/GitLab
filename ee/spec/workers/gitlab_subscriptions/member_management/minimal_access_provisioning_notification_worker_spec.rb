# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::MemberManagement::MinimalAccessProvisioningNotificationWorker, feature_category: :seat_cost_management do
  it_behaves_like 'an idempotent worker'

  describe '#perform' do
    it 'calls MinimalAccessProvisioningNotificationService' do
      expect(GitlabSubscriptions::MemberManagement::MinimalAccessProvisioningNotificationService)
        .to receive(:execute)

      described_class.new.perform
    end
  end
end
