# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Projects::SecretsController, feature_category: :secrets_management do
  let_it_be(:developer) { create(:user) }
  let_it_be(:reporter) { create(:user, :with_namespace) }
  let_it_be(:guest) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be_with_reload(:secrets_manager) { build(:project_secrets_manager, project: project) }

  shared_examples 'renders the project secrets index template' do
    it do
      subject

      expect(response).to have_gitlab_http_status(:ok)
      expect(response).to render_template('projects/secrets/index')
    end
  end

  shared_examples 'returns a "not found" response' do
    it do
      subject

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  describe 'GET /:namespace/:project/-/secrets' do
    subject(:request) { get project_secrets_url(project), params: { project_id: project.to_param } }

    before_all do
      secrets_manager.activate!
      project.add_developer(developer)
      project.add_reporter(reporter)
      project.add_guest(guest)
    end

    before do
      # SM availability requires enrollment; the entitlement-aware policy also
      # requires an entitled namespace. Enroll + entitle by default so positive-path
      # tests are reachable. Negative-path tests override the license or enrollment.
      enroll_instance_in_secrets_manager
    end

    context 'when all conditions are met' do
      before do
        stub_licensed_features(native_secrets_management: true)
        sign_in(reporter)
      end

      it_behaves_like 'renders the project secrets index template'
    end

    context 'when user has a role higher than reporter' do
      before do
        stub_licensed_features(native_secrets_management: true)
        sign_in(developer)
      end

      it_behaves_like 'renders the project secrets index template'
    end

    it_behaves_like 'dismisses the secrets manager nav badge on view' do
      let(:secrets_container) { project }
    end

    context 'when user is not Reporter+' do
      before do
        stub_licensed_features(native_secrets_management: true)
        sign_in(guest)
      end

      it_behaves_like 'returns a "not found" response'
    end

    context 'when not enrolled' do
      before do
        stub_licensed_features(native_secrets_management: true)
        stub_application_setting(secrets_manager_instance_enrolled: false)
        sign_in(reporter)
      end

      it_behaves_like 'returns a "not found" response'
    end

    context 'when feature license is disabled' do
      before do
        stub_licensed_features(native_secrets_management: false)
        sign_in(reporter)
      end

      it_behaves_like 'returns a "not found" response'
    end

    context 'with an entitlement' do
      before do
        stub_licensed_features(native_secrets_management: true)
        sign_in(reporter)
      end

      {
        trial_eligible: :not_found,
        trial: :ok,
        paid: :ok,
        offline_paid: :ok,
        blocked: :ok, # read-only
        ineligible: :not_found
      }.each do |state, http_status|
        context "when the entitlement state is #{state}" do
          before do
            stub_secrets_manager_entitlement(state: state)
          end

          it "responds with #{http_status}" do
            request

            expect(response).to have_gitlab_http_status(http_status)
          end
        end
      end

      context 'when the secrets manager is not provisioned but the namespace is entitled' do
        before do
          secrets_manager.update!(status: SecretsManagement::ProjectSecretsManager::STATUSES[:deprovisioning])
          stub_secrets_manager_entitlement(state: :trial)
        end

        it_behaves_like 'renders the project secrets index template'
      end

      context 'when the secrets manager is provisioning' do
        before do
          secrets_manager.update!(status: SecretsManagement::ProjectSecretsManager::STATUSES[:provisioning])
          stub_secrets_manager_entitlement(state: :trial)
        end

        it_behaves_like 'renders the project secrets index template'
      end
    end
  end
end
