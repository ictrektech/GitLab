# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::ResourceAccessTokens, feature_category: :system_access do
  let_it_be(:user) { create(:user) }

  before do
    stub_licensed_features(audit_events: true)

    # Creating a resource access token with audit events enabled executes ~101 queries
    # due to bot user creation, membership creation, and audit logging.
    #
    allow(Gitlab::QueryLimiting::Transaction).to receive(:threshold).and_return(110)
  end

  shared_examples 'audit event carries user agent' do |source_type|
    describe "POST /#{source_type}s/:id/access_tokens" do
      let(:path) { "/#{source_type}s/#{resource.id}/access_tokens" }
      let(:params) do
        { name: 'test', scopes: ['api'], expires_at: 1.month.from_now.to_date.iso8601 }
      end

      context 'when User-Agent header is present' do
        let(:raw_user_agent) { "Custom-User-Agent/1.0\nInjected" }
        let(:sanitized_user_agent) { 'Custom-User-Agent/1.0Injected' }

        it 'creates an audit event with the sanitized user agent', :aggregate_failures do
          expect do
            post api(path, user), params: params, headers: { 'User-Agent' => raw_user_agent }
          end.to change { AuditEventReader.count }.by(1)

          expect(response).to have_gitlab_http_status(:created)
          expect(AuditEventReader.where(author_id: user.id).last.details).to include(user_agent: sanitized_user_agent)
        end
      end

      context 'when User-Agent header is not present' do
        it 'creates an audit event without a user agent', :aggregate_failures do
          expect do
            post api(path, user), params: params
          end.to change { AuditEventReader.count }.by(1)

          expect(response).to have_gitlab_http_status(:created)
          expect(AuditEventReader.where(author_id: user.id).last.details).not_to have_key(:user_agent)
        end
      end
    end
  end

  context 'for project access tokens' do
    let_it_be(:group) { create(:group) }
    let_it_be(:resource) { create(:project, group: group) }

    before_all do
      resource.add_maintainer(user)
    end

    it_behaves_like 'audit event carries user agent', 'project'
  end

  context 'for group access tokens' do
    let_it_be(:resource) { create(:group) }

    before_all do
      resource.add_owner(user)
    end

    it_behaves_like 'audit event carries user agent', 'group'
  end
end
