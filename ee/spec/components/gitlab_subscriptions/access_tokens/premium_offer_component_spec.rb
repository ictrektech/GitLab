# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::AccessTokens::PremiumOfferComponent, :aggregate_failures, :saas,
  feature_category: :acquisition do
  let(:premium_plan_id) { 2 }
  let(:premium_plan) { Hashie::Mash.new(code: ::Plan::PREMIUM, id: premium_plan_id, name: 'Premium') }
  let(:plans_data) { [premium_plan] }

  before do
    allow(root_ancestor).to receive(:plan_name_for_upgrading).and_return(::Plan::FREE)

    allow_next_instance_of(GitlabSubscriptions::FetchSubscriptionPlansService) do |service|
      allow(service).to receive(:execute).and_return(plans_data)
    end
  end

  subject(:render) { render_inline(described_class.new(resource: resource)) }

  shared_examples 'an access token premium offer card' do
    it 'renders the card, heading, body and footnote' do
      render

      expect(page).to have_css('[data-testid="access-tokens-premium-offer-card"]')
      expect(page).to have_content(heading)
      expect(page).to have_content('creation is not available on GitLab Free')
      expect(page).to have_content(s_('AccessTokens|You can still manage existing tokens.'))
    end

    it 'renders the upgrade CTA pointing at the purchase flow with tracking' do
      render

      button = page.find('[data-testid="upgrade-to-premium-button"]')

      expect(button).to have_content(s_('AccessTokens|Upgrade to Premium'))
      expect(button['href']).to include("plan_id=#{premium_plan_id}")
      expect(button['href']).to include("gl_namespace_id=#{root_ancestor.id}")
      expect(button['data-event-tracking']).to eq(upgrade_event)
    end

    context 'when the Premium plan is missing from the plans data' do
      let(:plans_data) { nil }

      it 'falls back to the pricing page for the upgrade CTA without raising' do
        render

        button = page.find('[data-testid="upgrade-to-premium-button"]')

        expect(button['href']).to eq(Gitlab::Routing.url_helpers.promo_pricing_url)
      end
    end

    it 'renders the explore plans CTA pointing at group billing with tracking' do
      render

      button = page.find('[data-testid="explore-plans-button"]')

      expect(button).to have_content(s_('AccessTokens|Explore plans'))
      expect(button['href']).to eq(
        Gitlab::Routing.url_helpers.group_billings_path(root_ancestor, source: tracking_source)
      )
      expect(button['data-event-tracking']).to eq(explore_event)
    end

    it 'links the docs from the body' do
      render

      link = page.find('a', text: docs_link_text)

      expect(link['href']).to eq(docs_url)
    end
  end

  context 'with a group' do
    let_it_be(:resource) { build_stubbed(:group) }

    let(:root_ancestor) { resource }
    let(:heading) { s_('AccessTokens|Try group access tokens with Premium') }
    let(:docs_link_text) { 'Group access token' }
    let(:docs_url) { help_page_path('user/group/settings/group_access_tokens.md') }
    let(:tracking_source) { 'group-access-tokens-upgrade-card' }
    let(:upgrade_event) { 'click_upgrade_to_premium_on_group_access_tokens' }
    let(:explore_event) { 'click_explore_plans_on_group_access_tokens' }

    it_behaves_like 'an access token premium offer card'

    it 'tracks the docs link' do
      render

      link = page.find('a', text: docs_link_text)

      expect(link['data-event-tracking']).to eq('click_learn_more_on_group_access_tokens')
    end
  end

  context 'with a project' do
    let_it_be(:group) { build_stubbed(:group) }
    let_it_be(:resource) { build_stubbed(:project, group: group) }

    let(:root_ancestor) { group }
    let(:heading) { s_('AccessTokens|Try project access tokens with Premium') }
    let(:docs_link_text) { 'Project access token' }
    let(:docs_url) { help_page_path('user/project/settings/project_access_tokens.md') }
    let(:tracking_source) { 'project-access-tokens-upgrade-card' }
    let(:upgrade_event) { 'click_upgrade_to_premium_on_project_access_tokens' }
    let(:explore_event) { 'click_explore_plans_on_project_access_tokens' }

    it_behaves_like 'an access token premium offer card'

    # The docs text is a contextual link rather than a CTA, so it is untracked
    # on this surface by design. Do not "restore symmetry" without agreeing the
    # analytics change first.
    # https://gitlab.com/gitlab-org/gitlab/-/merge_requests/251177#note_3782450693
    it 'leaves the docs link untracked' do
      render

      link = page.find('a', text: docs_link_text)

      expect(link['data-event-tracking']).to be_nil
    end
  end
end
