# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Oauth::ApplicationsController, feature_category: :system_access do
  let(:user) { create(:user, :with_namespace) }

  context 'when user is signed in' do
    before do
      sign_in(user)
    end

    describe 'POST #create' do
      it 'logs the audit event' do
        stub_licensed_features(extended_audit_events: true)

        application = build(:oauth_application)
        application_attributes = application.attributes.merge("scopes" => ["read_user"])

        expect do
          post oauth_applications_path, params: { authn_oauth_application: application_attributes }
        end.to change { AuditEventReader.count }.by(1)
      end
    end
  end
end
