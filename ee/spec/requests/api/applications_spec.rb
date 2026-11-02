# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Applications, :api, :with_current_organization, feature_category: :system_access do
  let_it_be(:admin) { create(:admin) }

  let(:granular_scopes) { [{ access: 'user', permissions: ['execute_mcp_tool'] }] }
  let(:params) do
    { name: 'application_name', redirect_uri: 'http://application.url', scopes: 'api', granular_scopes: granular_scopes }
  end

  before do
    stub_licensed_features(extended_audit_events: true)
  end

  describe 'POST /applications' do
    subject(:create_application) { post api('/applications', admin, admin_mode: true), params: params }

    it 'audits the created application with its scopes', :aggregate_failures do
      expect { create_application }.to change { AuditEventReader.count }.by(1)

      expect(response).to have_gitlab_http_status(:created)
      expect(AuditEventReader.last.details).to include(
        custom_message: 'OAuth application added', scopes: match_array(%w[api granular])
      )
    end

    context 'when the declaration is refused' do
      # The endpoint creates instance applications, and the instance boundary rule
      # does not allow personal_projects access
      let(:granular_scopes) { [{ access: 'personal_projects', permissions: ['read_job'] }] }

      it 'audits nothing', :aggregate_failures do
        expect { create_application }.not_to change { AuditEventReader.count }

        expect(response).to have_gitlab_http_status(:bad_request)
      end
    end
  end
end
