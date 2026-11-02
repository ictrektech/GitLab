# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'gitlab_subscriptions routing', feature_category: :subscription_management do
  it 'routes to track_cart_abandonment' do
    expect(post('/-/gitlab_subscriptions/hand_raise_leads/track_cart_abandonment')).to route_to(
      controller: 'gitlab_subscriptions/hand_raise_leads',
      action: 'track_cart_abandonment'
    )
  end

  it "routes to TrialsController when constraint matches saas", :saas_subscriptions_trials do
    expect(get('/-/trials/new')).to route_to('gitlab_subscriptions/trials#new')
  end

  it "routes to SelfManaged::TrialsController when constraint does not match saas" do
    expect(get('/-/trials/new')).to route_to('gitlab_subscriptions/self_managed/trials#new')
  end

  it "routes POST /-/trials to SelfManaged::TrialsController when constraint does not match saas" do
    expect(post('/-/trials')).to route_to('gitlab_subscriptions/self_managed/trials#create')
  end

  context 'when the instance is Dedicated' do
    before do
      allow(::Gitlab::Dedicated).to receive(:feature_available?)
        .with(:skip_ultimate_trial_experience).and_return(true)
    end

    it 'does not route GET /-/trials/new to the self managed trials controller' do
      expect(get('/-/trials/new')).not_to route_to('gitlab_subscriptions/self_managed/trials#new')
    end

    it 'does not route POST /-/trials to the self managed trials controller' do
      expect(post('/-/trials')).not_to route_to('gitlab_subscriptions/self_managed/trials#create')
    end
  end
end
