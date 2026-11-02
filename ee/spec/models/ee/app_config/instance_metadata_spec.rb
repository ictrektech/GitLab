# frozen_string_literal: true

require 'spec_helper'

RSpec.describe AppConfig::InstanceMetadata, feature_category: :api do
  subject(:plan) { described_class.new.plan }

  let(:license) { nil }

  before do
    allow(::License).to receive(:current).and_return(license)
  end

  context 'when the instance runs under a license' do
    let(:license) { build(:license, plan: ::License::ULTIMATE_PLAN) }

    it { is_expected.to eq(::License::ULTIMATE_PLAN) }
  end

  context 'when the license names no plan' do
    let(:license) { build(:license) }

    it { is_expected.to eq(::License::STARTER_PLAN) }
  end

  context 'when the license is an active trial' do
    let(:license) { build(:license, :ultimate_trial) }

    it { is_expected.to eq(::License::ULTIMATE_PLAN) }
  end

  context 'when the license is an expired trial' do
    let(:license) { build(:license, :ultimate_trial, expired: true) }

    it { is_expected.to eq('free') }
  end

  context 'when a paid license has expired' do
    let(:license) { build(:license, :expired_paid) }

    it { is_expected.to eq(::License::PREMIUM_PLAN) }
  end

  context 'when the instance has no license' do
    it { is_expected.to eq('free') }
  end

  context 'when subscriptions are held per namespace', :saas_gitlab_com_subscriptions do
    let(:license) { build(:license, plan: ::License::ULTIMATE_PLAN) }

    it { is_expected.to be_nil }
  end
end
