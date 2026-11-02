# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::SecretsController, feature_category: :secrets_management do
  let_it_be(:developer) { create(:user) }
  let_it_be(:reporter) { create(:user, :with_namespace) }
  let_it_be(:guest) { create(:user) }
  let_it_be(:planner) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be_with_reload(:secrets_manager) { build(:group_secrets_manager, group: group) }

  shared_examples 'group secrets manager page' do
    it 'renders the group secrets index template' do
      subject

      expect(response).to have_gitlab_http_status(:ok)
      expect(response).to render_template('groups/secrets/index')
    end
  end

  shared_examples 'page not found' do
    it 'returns a "not found" response' do
      subject

      expect(response).to have_gitlab_http_status(:not_found)
    end
  end

  describe 'GET /:namespace/:group/-/secrets' do
    subject(:request) { get group_secrets_url(group), params: { group_id: group.to_param } }

    before_all do
      secrets_manager.activate!
      group.add_developer(developer)
      group.add_reporter(reporter)
      group.add_guest(guest)
      group.add_planner(planner)
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

      it_behaves_like 'group secrets manager page'
    end

    context 'when user has a role higher than reporter' do
      before do
        stub_licensed_features(native_secrets_management: true)
        sign_in(developer)
      end

      it_behaves_like 'group secrets manager page'
    end

    it_behaves_like 'dismisses the secrets manager nav badge on view' do
      let(:secrets_container) { group }
    end

    context 'when user does not have read_secret permission' do
      before do
        stub_licensed_features(native_secrets_management: true)
      end

      context 'with guest role' do
        before do
          sign_in(guest)
        end

        it_behaves_like 'page not found'
      end

      context 'with planner role' do
        before do
          sign_in(planner)
        end

        it_behaves_like 'page not found'
      end
    end

    context 'when not enrolled' do
      before do
        stub_licensed_features(native_secrets_management: true)
        stub_application_setting(secrets_manager_instance_enrolled: false)
        sign_in(reporter)
      end

      it_behaves_like 'page not found'
    end

    context 'when feature license is disabled' do
      before do
        stub_licensed_features(native_secrets_management: false)
        sign_in(reporter)
      end

      it_behaves_like 'page not found'
    end

    context 'with an entitlement' do
      before do
        stub_licensed_features(native_secrets_management: true)
        sign_in(reporter)
      end

      {
        trial_eligible: :ok,
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

      # Toggling the namespace off in group settings has to close the page even
      # though the entitlement still permits reads. Read-only visibility of the
      # retained secrets is a planned follow-up.
      context 'when the top-level group opted out', :saas do
        before_all do
          create(:secrets_manager_namespace_enrollment, :disabled, namespace: group)
        end

        before do
          stub_secrets_manager_entitlement(state: :paid)
        end

        it_behaves_like 'page not found'
      end

      context 'when the secrets manager is not provisioned but the namespace is entitled' do
        let_it_be(:unprovisioned_group) { create(:group) }

        subject(:request) do
          get group_secrets_url(unprovisioned_group), params: { group_id: unprovisioned_group.to_param }
        end

        before_all do
          unprovisioned_group.add_reporter(reporter)
        end

        before do
          stub_secrets_manager_entitlement(state: :trial)
        end

        it_behaves_like 'group secrets manager page'
      end

      context 'when the secrets manager is provisioning' do
        let_it_be(:provisioning_group) { create(:group) }
        let_it_be(:provisioning_sm) { create(:group_secrets_manager, group: provisioning_group) }

        subject(:request) do
          get group_secrets_url(provisioning_group), params: { group_id: provisioning_group.to_param }
        end

        before_all do
          provisioning_group.add_reporter(reporter)
        end

        before do
          stub_secrets_manager_entitlement(state: :trial)
        end

        it_behaves_like 'group secrets manager page'
      end
    end
  end
end
