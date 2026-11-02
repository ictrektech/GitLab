# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::Security::InventoryController, feature_category: :security_asset_inventories do
  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, owners: user) }

  before do
    stub_licensed_features(security_inventory: true)

    sign_in(user)
  end

  describe '#show', :aggregate_failures do
    subject(:request) { get group_security_inventory_path(group) }

    it_behaves_like 'internal event tracking' do
      let(:event) { 'view_group_security_inventory' }
      let(:namespace) { group }
    end

    context 'with authorized users' do
      let_it_be(:user) { create(:user) }

      before_all do
        group.add_developer(user)
        sign_in(user)
      end

      it 'returns 200 response' do
        request

        expect(response).to have_gitlab_http_status(:ok)
      end

      it 'pushes the bl_security_analyzer flag for the root group' do
        stub_application_setting(instance_level_ai_beta_features_enabled: true)

        request

        expect(response.body).to have_pushed_frontend_feature_flags(blSecurityAnalyzer: true)
      end

      context 'when the flow is beta' do
        before do
          allow(Ai::Catalog::FoundationalFlow.bl_security_experimental).to receive(:beta?).and_return(true)
        end

        it 'pushes the flag as disabled with Experiment and beta features off' do
          stub_application_setting(instance_level_ai_beta_features_enabled: false)

          request

          expect(response.body).to have_pushed_frontend_feature_flags(blSecurityAnalyzer: false)
        end

        it 'pushes the flag as enabled with Experiment and beta features on' do
          stub_application_setting(instance_level_ai_beta_features_enabled: true)

          request

          expect(response.body).to have_pushed_frontend_feature_flags(blSecurityAnalyzer: true)
        end
      end

      context 'when the bl_security_analyzer flag is disabled' do
        before do
          stub_feature_flags(bl_security_analyzer: false)
        end

        it 'pushes the flag as disabled' do
          request

          expect(response.body).to have_pushed_frontend_feature_flags(blSecurityAnalyzer: false)
        end

        context 'on GitLab Dedicated with the instance beta setting on', :dedicated do
          before do
            stub_application_setting(instance_level_ai_beta_features_enabled: true)
            allow(Ai::Catalog::FoundationalFlows::EnabledFlowsClient).to receive(:enabled?)
              .with('bl_security').and_return(true)
          end

          it 'pushes the flag as enabled' do
            request

            expect(response.body).to have_pushed_frontend_feature_flags(blSecurityAnalyzer: true)
          end

          context 'when GitLab has not enabled the flow for the instance' do
            before do
              allow(Ai::Catalog::FoundationalFlows::EnabledFlowsClient).to receive(:enabled?)
                .with('bl_security').and_return(false)
            end

            it 'pushes the flag as disabled' do
              request

              expect(response.body).to have_pushed_frontend_feature_flags(blSecurityAnalyzer: false)
            end
          end
        end
      end

      it 'pushes the triage and remediation profiles UI feature flag to the frontend' do
        request

        expect(response.body).to have_pushed_frontend_feature_flags(
          triageAndRemediationProfilesUi: true
        )
      end

      context 'when triage_and_remediation_profiles_ui is disabled' do
        before do
          stub_feature_flags(triage_and_remediation_profiles_ui: false)
        end

        it 'pushes the disabled feature flag to the frontend' do
          request

          expect(response.body).to have_pushed_frontend_feature_flags(
            triageAndRemediationProfilesUi: false
          )
        end
      end
    end

    context 'with unauthorized users' do
      let_it_be(:user) { create(:user) }

      before_all do
        group.add_reporter(user)
        sign_in(user)
      end

      it 'returns 403 response' do
        request

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when security inventory feature is disabled' do
      before do
        stub_licensed_features(security_inventory: false)
      end

      it 'returns 403 response' do
        request

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end
  end
end
