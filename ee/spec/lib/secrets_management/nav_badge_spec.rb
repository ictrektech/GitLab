# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SecretsManagement::NavBadge, feature_category: :secrets_management do
  describe '.visible?' do
    let(:user) { instance_double(User, dismissed_callout?: false) }

    subject(:visible) { described_class.visible?(user: user) }

    context 'on a date before the badge expires' do
      around do |example|
        travel_to(described_class::BADGE_EXPIRES_ON - 1.day) { example.run }
      end

      context 'when all conditions are met' do
        it { is_expected.to be(true) }
      end

      context 'when there is no user' do
        let(:user) { nil }

        it { is_expected.to be(false) }
      end

      context 'when the user has dismissed the callout' do
        let(:user) { instance_double(User, dismissed_callout?: true) }

        it { is_expected.to be(false) }
      end
    end

    context 'on the badge expiry date' do
      around do |example|
        travel_to(described_class::BADGE_EXPIRES_ON) { example.run }
      end

      it { is_expected.to be(true) }
    end

    context 'on a date after the badge expires' do
      around do |example|
        travel_to(described_class::BADGE_EXPIRES_ON + 1.day) { example.run }
      end

      it { is_expected.to be(false) }
    end
  end
end
