# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Groups::Security::ConfigurationController, feature_category: :security_testing_configuration do
  let_it_be(:group) { create(:group) }
  let_it_be(:maintainer) { create(:user, maintainer_of: group) }
  let_it_be(:reporter) { create(:user, reporter_of: group) }

  describe 'GET #show', :aggregate_failures do
    subject(:request) { get group_security_configuration_path(group) }

    context 'with authorized user' do
      before do
        sign_in(maintainer)
      end

      context 'when attributes feature is available' do
        before do
          stub_licensed_features(security_attributes: true)
        end

        it 'returns 200 response' do
          request

          expect(response).to have_gitlab_http_status(:ok)
        end
      end

      context 'when scan profiles feature is available' do
        before do
          stub_licensed_features(security_scan_profiles: true)
        end

        it 'returns 200 response' do
          request

          expect(response).to have_gitlab_http_status(:ok)
        end

        it 'pushes the custom secret detection profiles UI feature flag to the frontend' do
          request

          expect(response.body).to have_pushed_frontend_feature_flags(
            customScanProfilesUi: true
          )
        end

        context 'when custom_scan_profiles_ui is disabled' do
          before do
            stub_feature_flags(custom_scan_profiles_ui: false)
          end

          it 'pushes the disabled feature flag to the frontend' do
            request

            expect(response.body).to have_pushed_frontend_feature_flags(
              customScanProfilesUi: false
            )
          end
        end

        it 'pushes the custom_scan_profiles_dependency_scanning_ui flag for the root group' do
          request

          expect(response.body).to have_pushed_frontend_feature_flags(
            customScanProfilesDependencyScanningUi: true
          )
        end

        context 'when the custom_scan_profiles_dependency_scanning_ui flag is disabled' do
          before do
            stub_feature_flags(custom_scan_profiles_dependency_scanning_ui: false)
          end

          it 'pushes the flag as disabled' do
            request

            expect(response.body).to have_pushed_frontend_feature_flags(
              customScanProfilesDependencyScanningUi: false
            )
          end
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

        it 'pushes the scanner_wizard_attach_modes flag for the root group' do
          request

          expect(response.body).to have_pushed_frontend_feature_flags(scannerWizardAttachModes: true)
        end

        context 'when the scanner_wizard_attach_modes flag is disabled' do
          before do
            stub_feature_flags(scanner_wizard_attach_modes: false)
          end

          it 'pushes the flag as disabled' do
            request

            expect(response.body).to have_pushed_frontend_feature_flags(scannerWizardAttachModes: false)
          end
        end
      end
    end

    context 'with unauthorized user' do
      before do
        sign_in(reporter)
      end

      it 'returns 403 response' do
        request

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'when neither feature is available' do
      before do
        sign_in(maintainer)
      end

      it 'returns 403 response' do
        request

        expect(response).to have_gitlab_http_status(:forbidden)
      end
    end

    context 'with the scan coverage recommendation banner' do
      let_it_be(:developer) { create(:user, developer_of: group) }

      let(:payload) do
        { variant: 'tip', title: 'Enable scanning', message: 'Enable scanning', cta_text: 'Set up scanning',
          cta_url: '/inventory' }
      end

      before do
        stub_licensed_features(security_scan_profiles: true)
        allow_next_instance_of(Security::ScanCoverageBanners::GenerateContentService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.success(payload: payload))
        end
      end

      context 'as a Maintainer who has not dismissed it' do
        before do
          sign_in(maintainer)
        end

        it 'includes the banner payload as JSON on the mount point', :aggregate_failures do
          request

          expect(response).to have_gitlab_http_status(:ok)
          expect(scan_coverage_banner_data).to eq({
            'variant' => 'tip', 'title' => 'Enable scanning', 'message' => 'Enable scanning',
            'ctaText' => 'Set up scanning', 'ctaUrl' => '/inventory'
          })
        end
      end

      context 'as a Developer' do
        before do
          sign_in(developer)
        end

        it 'renders the JSON literal null, not an absent attribute', :aggregate_failures do
          expect(Security::ScanCoverageBanners::GenerateContentService).not_to receive(:new)

          request

          expect(response).to have_gitlab_http_status(:ok)
          expect(scan_coverage_banner_attribute).to eq('null')
          expect(scan_coverage_banner_data).to be_nil
        end
      end

      context 'as a Maintainer who already dismissed it' do
        let_it_be_with_refind(:dismissing_maintainer) { create(:user, maintainer_of: group) }

        before do
          create(:group_callout,
            user: dismissing_maintainer,
            group: group,
            feature_name: :scan_coverage_recommendation_banner,
            dismissed_at: 1.day.ago)
          sign_in(dismissing_maintainer)
        end

        it 'renders the JSON literal null, not an absent attribute', :aggregate_failures do
          expect(Security::ScanCoverageBanners::GenerateContentService).not_to receive(:new)

          request

          expect(response).to have_gitlab_http_status(:ok)
          expect(scan_coverage_banner_attribute).to eq('null')
          expect(scan_coverage_banner_data).to be_nil
        end
      end
    end

    context 'with the real scan coverage recommendation service' do
      let_it_be(:real_maintainer) { create(:user, maintainer_of: group) }

      before do
        create(:project, namespace: group)
        stub_licensed_features(security_scan_profiles: true)
        sign_in(real_maintainer)
      end

      it 'renders the banner built from the group\'s own real scan coverage, not a stub', :aggregate_failures do
        request

        expect(response).to have_gitlab_http_status(:ok)
        expect(scan_coverage_banner_data['title']).to eq(
          'None of your active projects are scanned for security issues'
        )
        expect(scan_coverage_banner_data['variant']).to eq('warning')
        expect(scan_coverage_banner_data['ctaUrl']).to eq(
          group_security_configuration_path(group, anchor: '/enable_scanners/approach')
        )
      end
    end
  end

  def scan_coverage_banner_attribute
    Nokogiri::HTML.parse(response.body).at_css('#js-group-security-configuration')['data-scan-coverage-banner']
  end

  def scan_coverage_banner_data
    Gitlab::Json::SafeParser.parse(scan_coverage_banner_attribute)
  end
end
