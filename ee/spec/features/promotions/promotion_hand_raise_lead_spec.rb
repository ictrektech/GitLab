# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Promotions > Hand Raise Lead', :js, :saas, :saas_gitlab_com_subscriptions, feature_category: :acquisition do
  include Features::HandRaiseLeadHelpers

  let_it_be(:user) { create(:user, :with_namespace, company: 'GitLab') }
  let_it_be(:group) { create(:group_with_plan, plan: :free_plan, owners: user) }

  before_all do
    create(:gitlab_subscription_add_on_purchase, :gitlab_credits, namespace: group)
  end

  before do
    # The test license enables group webhooks, which renders the hooks form instead of the promotion.
    stub_licensed_features(group_webhooks: false)

    allow_next_instance_of(::Gitlab::Llm::DuoChat) do |instance|
      allow(instance).to receive_messages(credits_available?: true, usage_billing_forbidden?: false)
    end

    sign_in(user)

    visit group_hooks_path(group)
  end

  it 'renders and submits the Talk to sales hand raise lead on the group webhooks promotion' do
    click_button 'Talk to sales'

    expect_fill_in_and_submit_hand_raise_lead(
      user, group, glm_content: 'group_webhooks', product_interaction: 'Hand Raise PQL'
    )
  end
end
