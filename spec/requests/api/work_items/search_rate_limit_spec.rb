# frozen_string_literal: true

require 'spec_helper'

# Kept in its own file: the rate limiter shared examples freeze time and reset the rate limiting
# Redis, which the main listing specs do not expect.
RSpec.describe 'Work item REST list endpoints enforcing the search rate limit',
  feature_category: :portfolio_management do
  let_it_be(:group) { create(:group, :public) }
  let_it_be(:project) { create(:project, :public, group: group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:user2) { create(:user) }
  let_it_be(:issuable) { create(:work_item, project: project, title: 'rate limited search term') }

  shared_examples 'a list route enforcing the search rate limit' do
    it_behaves_like 'issuable API rate-limited search'

    context 'without a search param' do
      it 'does not consult the search rate limiter' do
        allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?).and_call_original
        expect(Gitlab::ApplicationRateLimiter)
          .not_to receive(:throttled_request?).with(anything, anything, :search_rate_limit, any_args)

        get api(url, user)

        expect(response).to have_gitlab_http_status(:ok)
      end
    end
  end

  describe 'GET /namespaces/:id/-/work_items' do
    let(:url) { "/namespaces/#{CGI.escape(project.project_namespace.full_path)}/-/work_items" }

    it_behaves_like 'a list route enforcing the search rate limit'
  end

  describe 'GET /projects/:id/-/work_items' do
    let(:url) { "/projects/#{project.id}/-/work_items" }

    it_behaves_like 'a list route enforcing the search rate limit'
  end

  describe 'GET /groups/:id/-/work_items' do
    let(:url) { "/groups/#{group.id}/-/work_items" }

    it_behaves_like 'a list route enforcing the search rate limit'
  end
end
