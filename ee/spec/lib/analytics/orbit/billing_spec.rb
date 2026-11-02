# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::Billing, feature_category: :knowledge_graph do
  let_it_be(:root) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root) }

  describe '.account_for' do
    it 'returns the account of the top-level group on GitLab.com' do
      stub_saas_features(gitlab_com_subscriptions: true)

      expect(described_class::GroupAccount).to receive(:new).with(root).and_call_original

      expect(described_class.account_for(subgroup)).to be_a(described_class::GroupAccount)
    end

    it 'returns the instance account on GitLab Self-Managed and GitLab Dedicated', :request_store do
      stub_saas_features(gitlab_com_subscriptions: false)

      expect(described_class.account_for(subgroup)).to equal(described_class.instance_account)
    end
  end

  describe '.account_for on GitLab.com', :request_store do
    it 'returns one account per top-level group in a request' do
      stub_saas_features(gitlab_com_subscriptions: true)

      expect(described_class.account_for(subgroup)).to equal(described_class.account_for(root))
      expect(described_class.account_for(create(:group))).not_to equal(described_class.account_for(root))
    end
  end

  describe '.instance_account', :request_store do
    it 'returns one account per request' do
      expect(described_class.instance_account).to equal(described_class.instance_account)
    end
  end

  describe '.reject_gated_root_ids_without_access' do
    let_it_be(:add_on_root) { create(:group) }
    let_it_be(:trial_root) { create(:group) }
    let_it_be(:plan_tier_root) { create(:group) }
    let(:root_ids) { [add_on_root.id, trial_root.id, plan_tier_root.id] }

    subject { described_class.reject_gated_root_ids_without_access(root_ids) }

    before_all do
      create(:gitlab_subscription_add_on_purchase, :orbit_promo, namespace: add_on_root)
      create(:orbit_namespace_enrollment, namespace: trial_root)
      create(:knowledge_graph_enabled_namespace, namespace: trial_root)
    end

    before do
      stub_saas_features(gitlab_com_subscriptions: true)
    end

    it { is_expected.to eq([add_on_root.id, trial_root.id]) }

    context 'when the orbit_promo_access_gate flag is enabled only for another root' do
      before do
        stub_feature_flags(orbit_promo_access_gate: add_on_root)
      end

      it { is_expected.to eq(root_ids) }
    end

    context 'when the orbit_promo_access_gate flag is disabled' do
      before do
        stub_feature_flags(orbit_promo_access_gate: false)
      end

      it { is_expected.to eq(root_ids) }
    end

    context 'on self-managed' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it { is_expected.to eq(root_ids) }
    end
  end
end
