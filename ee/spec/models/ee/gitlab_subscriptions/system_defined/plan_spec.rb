# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::SystemDefined::Plan, feature_category: :plan_provisioning do
  describe 'plan constants' do
    it 'mirrors every public plan constant on the legacy EE::Plan while both models exist', :aggregate_failures do
      legacy = EE::Plan.constants(false).select do |name|
        value = EE::Plan.const_get(name, false)
        value.is_a?(String) || value.is_a?(Array)
      end

      expect(legacy).not_to be_empty

      legacy.each do |name|
        ported = EE::GitlabSubscriptions::SystemDefined::Plan.const_get(name, false)

        expect(ported).to eq(EE::Plan.const_get(name, false)), name.to_s
      end
    end
  end

  describe '.all_plans' do
    it 'matches the legacy Plan.all_plans while both models exist' do
      expect(described_class.all_plans).to eq(::Plan.all_plans)
    end
  end

  describe '.default_plans' do
    it 'matches the legacy Plan.default_plans while both models exist' do
      expect(described_class.default_plans).to eq(::Plan.default_plans)
    end
  end

  describe '.instance_plans' do
    context 'when gitlab_com_subscriptions is available' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'returns every plan' do
        expect(described_class.instance_plans).to eq(described_class.all)
      end
    end

    context 'when gitlab_com_subscriptions is not available' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'returns only the default plan' do
        expect(described_class.instance_plans).to eq([described_class.default])
      end
    end
  end

  describe '.tier_for' do
    it 'matches the legacy Plan.tier_for for every plan name while both models exist', :aggregate_failures do
      described_class.all.map(&:name).each do |name|
        expect(described_class.tier_for(name)).to eq(::Plan.tier_for(name)), name
      end
    end
  end

  describe '.free' do
    context 'when gitlab_com_subscriptions is available' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'returns the free plan item' do
        expect(described_class.free).to have_attributes(id: 2, name: 'free')
      end
    end

    context 'when gitlab_com_subscriptions is not available' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'returns nil like the legacy Plan.free' do
        expect(described_class.free).to be_nil
      end
    end
  end

  describe '#paid?' do
    it 'is true exactly for the paid hosted plans' do
      paid_names = described_class.all.select(&:paid?).map(&:name)

      expect(paid_names).to match_array(EE::Plan::PAID_HOSTED_PLANS)
    end
  end

  describe '#paid_excluding_trials?' do
    it 'is true for paid hosted plans that are not trials' do
      names = described_class.all.select(&:paid_excluding_trials?).map(&:name)

      expect(names).to match_array(EE::Plan::PAID_HOSTED_PLANS - EE::Plan::FREE_TRIAL_PLANS)
    end

    it 'also excludes opensource with exclude_oss: true' do
      names = described_class.all.select { |plan| plan.paid_excluding_trials?(exclude_oss: true) }.map(&:name)

      expect(names).to match_array(
        EE::Plan::PAID_HOSTED_PLANS - EE::Plan::FREE_TRIAL_PLANS - [EE::Plan::OPEN_SOURCE]
      )
    end
  end

  describe '#open_source?' do
    it 'is true only for the opensource plan' do
      names = described_class.all.select(&:open_source?).map(&:name)

      expect(names).to contain_exactly('opensource')
    end
  end

  describe '#ultimate_or_ultimate_trial_plans?' do
    it 'is true exactly for the ultimate plan family' do
      names = described_class.all.select(&:ultimate_or_ultimate_trial_plans?).map(&:name)

      expect(names).to match_array(EE::Plan::ALL_ULTIMATE_PLANS)
    end
  end

  describe '#default?' do
    it 'is true for the default and free plans' do
      names = described_class.all.select(&:default?).map(&:name)

      expect(names).to match_array(%w[default free])
    end
  end
end
