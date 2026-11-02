# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Onboarding::FeatureLibrary::UpgradeCta, feature_category: :onboarding do
  include AdminModeHelper

  let(:plan) { :premium }
  let(:base_plan) { :free }
  let(:cta) { described_class.new(user: user, resource: resource, plan: plan, base_plan: base_plan).build }
  let(:portal_url) { Gitlab::Routing.url_helpers.subscription_portal_url }
  let(:sales_url) { Gitlab::Routing.url_helpers.promo_url(path: '/sales/') }

  context 'on GitLab.com', :saas_gitlab_com_subscriptions do
    let_it_be(:owner) { create(:user) }
    let_it_be(:developer) { create(:user) }
    let_it_be(:group) { create(:group, owners: owner, developers: developer) }

    let(:user) { owner }
    # A fresh record per example, so subscriptions created in an example aren't hidden by a cached association.
    let(:resource) { Group.find(group.id) }

    def unified_url(tier, namespace_id: group.id)
      params = { deployment_type: 'gitlab_com', plan_type: 'base_product', tier: tier, gl_namespace_id: namespace_id }
      "#{portal_url}/subscriptions/purchases/gitlab?#{params.compact.to_query}"
    end

    shared_context 'with CustomersDot plans' do
      let(:plans_data) do
        [
          Hashie::Mash.new(id: 'premium-id', code: ::Plan::PREMIUM),
          Hashie::Mash.new(id: 'ultimate-id', code: ::Plan::ULTIMATE)
        ]
      end

      before do
        allow_next_instance_of(GitlabSubscriptions::FetchSubscriptionPlansService) do |service|
          allow(service).to receive(:execute).and_return(plans_data)
        end
      end
    end

    it 'links an owner of a Free namespace to the Premium purchase without looking up plans' do
      expect(GitlabSubscriptions::FetchSubscriptionPlansService).not_to receive(:new)

      expect(cta).to eq(type: 'upgrade', text: 'Upgrade to Premium', url: unified_url('premium'))
    end

    context 'when the page is Ultimate' do
      let(:plan) { :ultimate }

      it 'links to the Ultimate purchase' do
        expect(cta).to eq(type: 'upgrade', text: 'Upgrade to Ultimate', url: unified_url('ultimate'))
      end
    end

    context 'when the namespace is on a trial' do
      before do
        create(:gitlab_subscription, :active_trial, :ultimate_trial, namespace: group, trial_ends_on: Date.tomorrow)
      end

      it 'links to the Premium purchase' do
        expect(cta).to eq(type: 'upgrade', text: 'Upgrade to Premium', url: unified_url('premium'))
      end
    end

    context 'when upgrading from Premium to Ultimate' do
      let(:plan) { :ultimate }
      let(:base_plan) { :premium }

      include_context 'with CustomersDot plans'

      before do
        create(:gitlab_subscription, :premium, namespace: group)
      end

      it 'links to the in-place upgrade' do
        expect(cta).to eq(
          type: 'upgrade',
          text: 'Upgrade to Ultimate',
          url: "#{portal_url}/gitlab/namespaces/#{group.id}/upgrade/ultimate-id"
        )
      end
    end

    context 'when a Premium customer is trialing Ultimate' do
      let(:plan) { :ultimate }
      let(:base_plan) { :premium }

      include_context 'with CustomersDot plans'

      before do
        create(:gitlab_subscription, :active_trial, :ultimate_trial_paid_customer, namespace: group,
          trial_ends_on: Date.tomorrow)
      end

      it 'links to the in-place upgrade of the existing subscription' do
        expect(cta).to eq(
          type: 'upgrade',
          text: 'Upgrade to Ultimate',
          url: "#{portal_url}/gitlab/namespaces/#{group.id}/upgrade/ultimate-id"
        )
      end
    end

    context 'when the Premium to Ultimate plans cannot be fetched' do
      let(:plan) { :ultimate }
      let(:base_plan) { :premium }

      before do
        create(:gitlab_subscription, :premium, namespace: group)
        allow_next_instance_of(GitlabSubscriptions::FetchSubscriptionPlansService) do |service|
          allow(service).to receive(:execute).and_return(nil)
        end
      end

      it 'falls back to the group Billing page' do
        expect(cta).to eq(
          type: 'upgrade',
          text: 'Upgrade to Ultimate',
          url: Gitlab::Routing.url_helpers.group_billings_url(group)
        )
      end
    end

    context 'when a Premium subscription has expired but is not downgraded yet' do
      let(:plan) { :ultimate }
      let(:base_plan) { :premium }

      include_context 'with CustomersDot plans'

      before do
        create(:gitlab_subscription, :premium, :expired, namespace: group)
      end

      it 'links to the in-place upgrade, not a renewal' do
        expect(cta).to eq(
          type: 'upgrade',
          text: 'Upgrade to Ultimate',
          url: "#{portal_url}/gitlab/namespaces/#{group.id}/upgrade/ultimate-id"
        )
      end
    end

    context 'when a Premium base plan has no subscription record' do
      let(:plan) { :ultimate }
      let(:base_plan) { :premium }

      include_context 'with CustomersDot plans'

      it 'links to the in-place upgrade' do
        expect(cta).to include(type: 'upgrade', url: "#{portal_url}/gitlab/namespaces/#{group.id}/upgrade/ultimate-id")
      end
    end

    context 'with a personal namespace on Premium' do
      let_it_be(:personal_namespace) { create(:user_namespace) }

      let(:plan) { :ultimate }
      let(:base_plan) { :premium }
      let(:user) { personal_namespace.owner }
      let(:resource) { personal_namespace }

      context 'when the subscription has expired' do
        include_context 'with CustomersDot plans'

        before do
          create(:gitlab_subscription, :premium, :expired, namespace: personal_namespace)
        end

        it 'links to the in-place upgrade for the personal namespace' do
          expect(cta).to include(
            type: 'upgrade', url: "#{portal_url}/gitlab/namespaces/#{personal_namespace.id}/upgrade/ultimate-id"
          )
        end
      end

      context 'when the plans cannot be fetched' do
        before do
          create(:gitlab_subscription, :premium, namespace: personal_namespace)
          allow_next_instance_of(GitlabSubscriptions::FetchSubscriptionPlansService) do |service|
            allow(service).to receive(:execute).and_return(nil)
          end
        end

        it 'falls back to the personal Billing page' do
          expect(cta).to include(type: 'upgrade', url: Gitlab::Routing.url_helpers.profile_billings_url)
        end
      end
    end

    context 'without a resource' do
      let(:resource) { nil }

      it { expect(cta).to be_nil }
    end

    context 'when the resource is a project in a personal namespace' do
      let_it_be(:personal_namespace) { create(:user_namespace) }

      let(:user) { personal_namespace.owner }
      let(:resource) { build_stubbed(:project, namespace: personal_namespace) }

      it 'routes to group selection before checkout', :aggregate_failures do
        expect(cta[:url]).to eq(unified_url('premium', namespace_id: nil))
        expect(cta[:url]).not_to include('gl_namespace_id')
      end
    end

    context 'with purchased GitLab Credits' do
      before do
        create(:gitlab_subscription_add_on_purchase, :gitlab_credits, namespace: group)
      end

      it 'routes every plan to the hand-raise lead modal', :aggregate_failures do
        expect(cta).to eq(
          type: 'talk_to_sales',
          text: 'Talk to sales',
          hand_raise_lead: {
            glm_content: 'feature_catalog_premium',
            cta_tracking: { action: 'click_button', label: 'feature_catalog_talk_to_sales', property: 'premium' }
          }
        )
      end
    end

    context 'with trial GitLab Credits' do
      before do
        create(:gitlab_subscription_add_on_purchase, :gitlab_credits, :active_trial, namespace: group)
      end

      it { expect(cta).to include(type: 'upgrade') }
    end

    context 'with expired GitLab Credits' do
      before do
        create(:gitlab_subscription_add_on_purchase, :gitlab_credits, :expired, namespace: group)
      end

      it { expect(cta).to include(type: 'upgrade') }
    end

    context 'without a user' do
      let(:user) { nil }

      it { expect(cta).to be_nil }
    end

    context 'when the viewer cannot purchase' do
      let(:user) { developer }

      it 'has no CTA' do
        expect(cta).to be_nil
      end

      it 'does not look up plans' do
        expect(GitlabSubscriptions::FetchSubscriptionPlansService).not_to receive(:new)

        cta
      end

      context 'with purchased GitLab Credits' do
        before do
          create(:gitlab_subscription_add_on_purchase, :gitlab_credits, namespace: group)
        end

        it { expect(cta).to be_nil }
      end
    end

    context 'when the viewer is a subgroup owner only' do
      let_it_be(:subgroup) { create(:group, parent: group, owners: developer) }

      let(:user) { developer }
      let(:resource) { subgroup }

      it 'checks billing on the root namespace' do
        expect(cta).to be_nil
      end
    end
  end

  context 'on self-managed' do
    def unified_url(tier)
      params = { deployment_type: 'self_managed', plan_type: 'base_product', tier: tier }
      "#{portal_url}/subscriptions/purchases/gitlab?#{params.to_query}"
    end

    let_it_be(:admin) { create(:admin) }
    let_it_be(:user_without_access) { create(:user) }
    let_it_be(:resource) { create(:group) }

    let(:user) { admin }
    let(:license) { nil }
    let(:billable_license) { nil }

    before do
      enable_admin_mode!(admin)
      allow(License).to receive_messages(current: license, billable_license: billable_license)
    end

    context 'with a Premium customer trialing Ultimate' do
      let(:plan) { :ultimate }
      let(:base_plan) { :premium }
      let(:license) { build_stubbed(:license, plan: License::ULTIMATE_PLAN) }
      let(:billable_license) { build_stubbed(:license, cloud: true, plan: License::PREMIUM_PLAN) }

      before do
        allow(license).to receive_messages(trial?: true, subscription_name: 'A-S00099999')
        allow(billable_license).to receive_messages(trial?: false, subscription_name: 'A-S00012345')
      end

      it 'upgrades the paid subscription, not the trial' do
        expect(cta).to eq(
          type: 'upgrade',
          text: 'Upgrade to Ultimate',
          url: "#{portal_url}/subscriptions/A-S00012345/upgrade/new"
        )
      end
    end

    context 'when the billable license is the trial itself' do
      let(:license) { build_stubbed(:license, plan: License::ULTIMATE_PLAN) }
      let(:billable_license) { license }

      before do
        allow(license).to receive_messages(trial?: true, subscription_name: 'A-S00099999')
      end

      it 'links to a new purchase instead of the trial subscription' do
        expect(cta).to eq(type: 'upgrade', text: 'Upgrade to Premium', url: unified_url('premium'))
      end
    end

    context 'with a trial license and no paid license underneath' do
      let(:license) { build_stubbed(:license, plan: License::ULTIMATE_PLAN) }

      before do
        allow(license).to receive(:trial?).and_return(true)
      end

      it 'links to a new purchase, even for a legacy trial license' do
        expect(cta).to eq(type: 'upgrade', text: 'Upgrade to Premium', url: unified_url('premium'))
      end
    end

    it 'links an admin without a license to the Premium purchase' do
      expect(cta).to eq(
        type: 'upgrade',
        text: 'Upgrade to Premium',
        url: unified_url('premium')
      )
    end

    context 'when the page is Ultimate' do
      let(:plan) { :ultimate }

      it 'links to the Ultimate purchase' do
        expect(cta).to eq(
          type: 'upgrade',
          text: 'Upgrade to Ultimate',
          url: unified_url('ultimate')
        )
      end
    end

    context 'with a cloud license' do
      let(:license) { build_stubbed(:license, cloud: true, plan: License::PREMIUM_PLAN) }

      it { expect(cta[:url]).to eq(unified_url('premium')) }

      context 'when upgrading from Premium to Ultimate' do
        let(:plan) { :ultimate }
        let(:base_plan) { :premium }

        before do
          allow(license).to receive(:subscription_name).and_return('A-S00012345')
        end

        it 'links to the subscription upgrade' do
          expect(cta).to eq(
            type: 'upgrade',
            text: 'Upgrade to Ultimate',
            url: "#{portal_url}/subscriptions/A-S00012345/upgrade/new"
          )
        end

        context 'when the subscription name needs encoding' do
          before do
            allow(license).to receive(:subscription_name).and_return('A S/1')
          end

          it { expect(cta[:url]).to eq("#{portal_url}/subscriptions/A%20S%2F1/upgrade/new") }
        end

        context 'when the license has no subscription name' do
          before do
            allow(license).to receive(:subscription_name).and_return(nil)
          end

          it 'falls back to a new Ultimate purchase' do
            expect(cta[:url]).to eq(unified_url('ultimate'))
          end
        end
      end
    end

    context 'with an expired paid cloud license' do
      let(:plan) { :ultimate }
      let(:base_plan) { :premium }
      let(:expired_days_ago) { 10 }
      let(:subscription_name) { 'A-S00012345' }
      let(:license) do
        build_stubbed(:license, cloud: true, plan: License::PREMIUM_PLAN,
          expired_days_ago: expired_days_ago, subscription_name: subscription_name)
      end

      it 'links to the subscription upgrade during the grace period' do
        expect(cta).to eq(
          type: 'upgrade',
          text: 'Upgrade to Ultimate',
          url: "#{portal_url}/subscriptions/A-S00012345/upgrade/new"
        )
      end

      context 'on the last day of the grace period' do
        let(:expired_days_ago) { 14 }

        it { expect(cta[:url]).to eq("#{portal_url}/subscriptions/A-S00012345/upgrade/new") }
      end

      context 'when the grace period has ended' do
        let(:expired_days_ago) { 15 }

        it 'links to a new purchase for the page plan' do
          expect(cta).to eq(type: 'upgrade', text: 'Upgrade to Ultimate', url: unified_url('ultimate'))
        end
      end

      context 'when the license has no subscription name' do
        let(:subscription_name) { nil }

        it { expect(cta).to include(type: 'upgrade', url: unified_url('ultimate')) }
      end
    end

    context 'when a Premium base plan has no license' do
      let(:plan) { :ultimate }
      let(:base_plan) { :premium }

      it 'links to a new Ultimate purchase' do
        expect(cta).to eq(type: 'upgrade', text: 'Upgrade to Ultimate', url: unified_url('ultimate'))
      end
    end

    context 'with a legacy license' do
      let(:license) { build_stubbed(:license, plan: License::PREMIUM_PLAN) }

      it { expect(cta).to eq(type: 'upgrade', text: 'Upgrade to Premium', url: unified_url('premium')) }

      context 'when upgrading from Premium to Ultimate' do
        let(:plan) { :ultimate }
        let(:base_plan) { :premium }
        let(:license) do
          build_stubbed(:license, plan: License::PREMIUM_PLAN, subscription_name: 'A-S00012345')
        end

        it 'links to the subscription upgrade' do
          expect(cta).to eq(
            type: 'upgrade',
            text: 'Upgrade to Ultimate',
            url: "#{portal_url}/subscriptions/A-S00012345/upgrade/new"
          )
        end
      end
    end

    context 'with an offline cloud license' do
      let(:license) { build_stubbed(:license, cloud: true, plan: License::PREMIUM_PLAN) }

      before do
        allow(license).to receive(:offline_cloud_license?).and_return(true)
      end

      it 'routes every plan to sales', :aggregate_failures do
        expect(cta).to eq(type: 'talk_to_sales', text: 'Talk to sales', url: sales_url)
        expect(described_class.new(user: user, resource: resource, plan: :ultimate, base_plan: :premium).build)
          .to include(type: 'talk_to_sales')
      end
    end

    context 'with purchased GitLab Credits' do
      before do
        create(:gitlab_subscription_add_on_purchase, :gitlab_credits, namespace: nil)
      end

      it 'routes to sales without a license' do
        expect(cta).to eq(type: 'talk_to_sales', text: 'Talk to sales', url: sales_url)
      end
    end

    context 'with trial GitLab Credits' do
      before do
        create(:gitlab_subscription_add_on_purchase, :gitlab_credits, :active_trial, namespace: nil)
      end

      it { expect(cta).to include(type: 'upgrade') }
    end

    context 'when the viewer is not an admin' do
      let(:user) { user_without_access }

      it 'has no CTA' do
        expect(cta).to be_nil
      end
    end
  end
end
