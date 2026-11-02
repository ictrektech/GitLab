# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::Automate::GovernanceController, feature_category: :ai_abstraction_layer do
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:group) { create(:group) }

  subject(:get_index) { get group_automate_governance_path(group) }

  def permitted_tabs
    Gitlab::Json::SafeParser.parse(Nokogiri::HTML(response.body).at_css('#js-governance')['data-permitted-tabs'])
  end

  before do
    stub_licensed_features(ai_features: true)
    group.namespace_settings.update!(duo_features_enabled: true)
    allow(::Ai::Catalog).to receive(:mcp_servers_available?).and_return(false)
    sign_in(user)
  end

  describe 'GET index' do
    before_all do
      group.add_owner(user)
    end

    context 'when licensed and the user can read tool rules' do
      it "renders index with 200 status code", :aggregate_failures do
        get_index

        expect(response).to have_gitlab_http_status(:ok)
        expect(response.body).to include('data-ai-audit-events-storage-enabled')
      end
    end

    context 'when AI features are not licensed' do
      before do
        stub_licensed_features(ai_features: false)
      end

      it 'renders index with 200 status code' do
        get_index

        expect(response).to have_gitlab_http_status(:ok)
      end
    end

    context 'when the user is a guest' do
      let_it_be(:guest) { create(:user, guest_of: group) }

      before do
        sign_in(guest)
      end

      it 'renders index with no permitted tabs', :aggregate_failures do
        get_index

        expect(response).to have_gitlab_http_status(:ok)
        expect(permitted_tabs).to eq([])
      end
    end

    context 'when the user is a security manager' do
      # Rendering the sidebar for a Security Manager needs a personal namespace (User#already_forked?).
      let_it_be(:security_manager) { create(:user, :with_namespace) }

      before_all do
        group.add_security_manager(security_manager)
      end

      before do
        stub_licensed_features(ai_features: true, group_level_compliance_dashboard: true)
        sign_in(security_manager)
      end

      it 'renders index with the dashboard and audit events tabs permitted', :aggregate_failures do
        get_index

        expect(response).to have_gitlab_http_status(:ok)
        expect(permitted_tabs).to eq(%w[dashboard agent-artifacts])
      end
    end

    context 'when the ai_governance_per_tab_permissions flag is disabled' do
      before do
        stub_feature_flags(ai_governance_per_tab_permissions: false)
      end

      it 'renders index with every tab permitted', :aggregate_failures do
        get_index

        expect(response).to have_gitlab_http_status(:ok)
        expect(permitted_tabs).to eq(::Ai::Governance::PageAvailability::TABS)
      end

      context 'when AI features are not licensed' do
        before do
          stub_licensed_features(ai_features: false)
        end

        it 'renders 404' do
          get_index

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end

      context 'when the user cannot read tool rules (not an owner)' do
        let_it_be(:reporter) { create(:user, reporter_of: group) }

        before do
          sign_in(reporter)
        end

        it 'renders 404' do
          get_index

          expect(response).to have_gitlab_http_status(:not_found)
        end
      end
    end

    context 'when the group is a subgroup' do
      let_it_be_with_reload(:subgroup) { create(:group, parent: group) }

      subject(:get_index) { get group_automate_governance_path(subgroup) }

      before do
        subgroup.namespace_settings.update!(duo_features_enabled: true)
      end

      it 'renders 404, since the tool-rules GraphQL surface only resolves root namespaces' do
        get_index

        expect(response).to have_gitlab_http_status(:not_found)
      end
    end
  end

  describe 'GET the legacy settings path' do
    it 'redirects to the new path' do
      get "/groups/#{group.full_path}/-/settings/gitlab_duo/governance"

      expect(response).to redirect_to(group_automate_governance_path(group))
    end

    it 'keeps the query string' do
      get "/groups/#{group.full_path}/-/settings/gitlab_duo/governance?tab=agent-artifacts"

      expect(response).to redirect_to(group_automate_governance_path(group, tab: 'agent-artifacts'))
    end
  end
end
