# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'shared/_promotion_link_project', feature_category: :acquisition do
  let(:user) { build(:user) }
  let(:namespace) { build_stubbed(:group, name: 'Our group') }

  subject do
    render 'shared/promotions/promotion_link_project', location: 'some_location'

    rendered
  end

  before do
    allow(view).to receive(:current_user).and_return(user)
    view.instance_variable_set(:@group, namespace)
  end

  context 'when gitlab_com_subscriptions saas feature is available', :saas_gitlab_com_subscriptions do
    context 'for namespace admin users' do
      before do
        allow(view).to receive(:can?).with(user, :admin_namespace, namespace).and_return(true)
      end

      it 'does not offer a trial' do
        build_stubbed(:gitlab_subscription, namespace: namespace)
        allow(view).to receive(:promotion_purchased_gitlab_credits?).and_return(true)

        is_expected.not_to have_text('Try it for free')
      end

      context 'without purchased GitLab Credits' do
        let(:checkout_url) { 'https://customers.gitlab.com/subscriptions/new?plan_id=premium' }

        before do
          allow(view).to receive(:promotion_purchased_gitlab_credits?).and_return(false)
          allow(view).to receive(:promotion_upgrade_to_premium_url)
            .with(namespace, source: 'some_location').and_return(checkout_url)
        end

        it { is_expected.to have_link 'Upgrade to Premium', href: checkout_url }

        it 'tracks the click with internal events' do
          is_expected.to have_selector(
            'a[data-event-tracking="click_upgrade_to_premium_on_promotion"][data-event-property="some_location"]'
          )
        end

        it { is_expected.not_to have_selector('.js-hand-raise-lead-trigger') }
      end

      context 'with purchased GitLab Credits' do
        before do
          allow(view).to receive(:promotion_purchased_gitlab_credits?).and_return(true)
        end

        it { is_expected.to have_selector('.js-hand-raise-lead-trigger[data-glm-content="some_location"]') }
        it { is_expected.not_to have_link 'Upgrade to Premium' }
      end
    end

    context 'for regular users' do
      context 'for groups' do
        it { is_expected.to have_text("Contact an owner of group Our group to upgrade the plan.") }
      end

      context 'for a project in a personal namespace' do
        let(:user2) { build_stubbed(:user, name: 'Joe') }
        let(:project) { build_stubbed(:project, namespace: build_stubbed(:namespace, owner: user2)) }

        before do
          view.instance_variable_set(:@project, project)
        end

        it { is_expected.to have_text("Contact owner Joe to upgrade the plan.") }
      end
    end
  end

  context 'when gitlab_com_subscriptions saas feature is not available' do
    context 'for admin users' do
      let(:user) { build_stubbed(:admin) }

      context 'with active license' do
        it { is_expected.to have_text('Start GitLab Ultimate trial') }
      end

      context 'with expired license' do
        let(:expired_license) { build_stubbed(:license, expired: true) }

        before do
          allow(License).to receive(:current).and_return(expired_license)
        end

        it { is_expected.to have_text('Buy GitLab Enterprise Edition') }
      end
    end

    context 'for regular users' do
      it { is_expected.to have_text('Contact your Administrator to upgrade your license.') }
    end
  end
end
