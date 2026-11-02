# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::Billing::GroupAccount, feature_category: :knowledge_graph do
  let_it_be_with_reload(:group) { create(:group) }

  let(:account) { described_class.new(group) }

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
    stub_licensed_features(orbit: false)
    stub_feature_flags(orbit_promo_access_gate: false, orbit_trial: false)
  end

  it 'keeps the facts private' do
    expect(account).not_to respond_to(:licensed?, :promo_gate?, :promo_add_on?, :trial_flow?, :trial_status)
  end

  describe '#eligible? and #entitled?' do
    it 'follows the plan of the group without the promo gate' do
      expect(account).to have_attributes(eligible?: false, entitled?: false)

      stub_licensed_features(orbit: true)

      expect(described_class.new(group)).to have_attributes(eligible?: true, entitled?: true)
    end

    context 'with the promo gate' do
      before do
        stub_feature_flags(orbit_promo_access_gate: group)
      end

      it 'does not give access through the plan alone' do
        stub_licensed_features(orbit: true)

        expect(account).to have_attributes(eligible?: true, entitled?: false)
      end

      it 'gives access through the orbit_promo add-on' do
        create(:gitlab_subscription_add_on_purchase, :orbit_promo, namespace: group)

        expect(account).to have_attributes(eligible?: true, entitled?: true)
      end

      it 'gives access through a trial that has not ended while Orbit is on' do
        create(:knowledge_graph_enabled_namespace, namespace: group)
        create(:orbit_namespace_enrollment, namespace: group)

        expect(account.entitled?).to be(true)
      end
    end
  end

  describe '#entitled? for a project' do
    let_it_be(:project) { create(:project, group: group) }

    it 'reads the license of the project, which can hold its own license' do
      allow(project).to receive(:licensed_feature_available?).with(:orbit).and_return(true)

      expect(account.entitled?(project)).to be(true)
      expect(account.entitled?).to be(false)
    end
  end

  describe '#access_by_plan?' do
    it 'is true during the beta and false under the promo gate' do
      expect(account.access_by_plan?).to be(true)

      stub_feature_flags(orbit_promo_access_gate: group)

      expect(described_class.new(group).access_by_plan?).to be(false)
    end
  end

  describe '#setting_changeable?' do
    before do
      stub_feature_flags(orbit_promo_access_gate: group)
    end

    it 'lets an Owner turn Orbit off after the access lapsed' do
      expect(account.setting_changeable?(group)).to be(false)

      create(:knowledge_graph_enabled_namespace, namespace: group)

      expect(described_class.new(group.reload).setting_changeable?(group)).to be(true)
    end
  end

  describe '#trial_offered_to? and #trial_startable_by?' do
    before do
      stub_licensed_features(orbit: true)
      stub_feature_flags(orbit_trial: group)
    end

    it 'offers the trial to the group of the account' do
      other_group = create(:group)

      expect(account.trial_offered_to?(group)).to be(true)
      expect(account.trial_offered_to?(other_group)).to be(false)
      expect(account.trial_startable_by?(group)).to be(true)
      expect(account.trial_startable_by?(other_group)).to be(false)
    end

    it 'does not offer the trial with the orbit_promo add-on' do
      stub_feature_flags(orbit_promo_access_gate: group)
      create(:gitlab_subscription_add_on_purchase, :orbit_promo, namespace: group)

      expect(account.trial_offered_to?(group)).to be(false)
    end

    it 'does not let a beta group start a trial during the beta' do
      create(:orbit_namespace_enrollment, :beta, namespace: group)

      expect(account.trial_offered_to?(group)).to be(true)
      expect(account.trial_startable_by?(group)).to be(false)
    end
  end

  describe '#trial' do
    it 'does not read CustomersDot outside the trial flow' do
      expect(Analytics::Orbit::Trial).not_to receive(:request_status_for)

      expect(account.trial).to be_nil
    end

    it 'returns the trial status in the trial flow' do
      stub_feature_flags(orbit_trial: group)
      trial = instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse)
      allow(Analytics::Orbit::Trial).to receive(:request_status_for).with(group).and_return(trial)

      expect(account.trial).to eq(trial)
    end
  end

  describe '#turn_on' do
    it 'allows turning on without CustomersDot outside the trial flow' do
      expect(Analytics::Orbit::Trial).not_to receive(:status_for)

      expect(account.turn_on(group)).to be_allowed
    end

    it 'asks CustomersDot once in the trial flow' do
      stub_feature_flags(orbit_trial: group)
      trial = instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: false,
        trial_ended?: true)
      expect(Analytics::Orbit::Trial).to receive(:status_for).with(group).once.and_return(trial)

      expect(account.turn_on(group).denial_reason).to eq(:trial_ended)
    end
  end
end
