# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Security::ScanProfileResolver, feature_category: :security_testing_configuration do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be(:current_user) { create(:user) }
  let_it_be(:scan_profile) { create(:security_scan_profile, namespace: group) }

  let(:resolver) { described_class }

  describe '#resolve' do
    shared_examples 'raises resource not available error' do
      it 'raises a resource not available error' do
        expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ResourceNotAvailable) do
          resolve_scan_profile(id)
        end
      end
    end

    context 'when user does not have permission' do
      let(:id) { scan_profile.to_global_id }

      include_examples 'raises resource not available error'
    end

    context 'when user has permission' do
      before_all do
        group.add_developer(current_user)
      end

      before do
        stub_licensed_features(security_scan_profiles: true)
      end

      context 'when resolving by numeric persisted id' do
        context 'when scan profile exists' do
          let(:id) { scan_profile.to_global_id }

          it 'returns the scan profile' do
            expect(resolve_scan_profile(id)).to eq(scan_profile)
          end
        end

        context 'when scan profile does not exist' do
          let(:id) { build_scan_profile_gid(non_existing_record_id) }

          include_examples 'raises resource not available error'
        end

        context 'when the scan profile is a business logic profile' do
          let_it_be(:bl_profile) { create(:security_scan_profile, namespace: group, scan_type: :business_logic) }
          let(:id) { bl_profile.to_global_id }

          context 'when the bl_security_analyzer flag is enabled for the group' do
            before do
              stub_feature_flags(bl_security_analyzer: group)
              stub_application_setting(instance_level_ai_beta_features_enabled: true)
            end

            it 'returns the scan profile' do
              expect(resolve_scan_profile(id)).to eq(bl_profile)
            end

            context 'when the flow is beta' do
              before do
                allow(Ai::Catalog::FoundationalFlow.bl_security_experimental).to receive(:beta?).and_return(true)
                stub_application_setting(instance_level_ai_beta_features_enabled: false)
              end

              include_examples 'raises resource not available error'

              context 'with Experiment and beta features on' do
                before do
                  stub_application_setting(instance_level_ai_beta_features_enabled: true)
                end

                it 'returns the scan profile' do
                  expect(resolve_scan_profile(id)).to eq(bl_profile)
                end
              end
            end
          end

          context 'when the bl_security_analyzer flag is enabled only for the current user' do
            before do
              stub_feature_flags(bl_security_analyzer: current_user)
            end

            include_examples 'raises resource not available error'
          end

          context 'when the bl_security_analyzer flag is disabled' do
            before do
              stub_feature_flags(bl_security_analyzer: false)
            end

            include_examples 'raises resource not available error'

            context 'on GitLab Dedicated with the instance beta setting on', :dedicated do
              before do
                stub_application_setting(instance_level_ai_beta_features_enabled: true)
                allow(Ai::Catalog::FoundationalFlows::EnabledFlowsClient).to receive(:enabled?)
                  .with('bl_security').and_return(true)
              end

              it 'returns the scan profile' do
                expect(resolve_scan_profile(id)).to eq(bl_profile)
              end

              context 'when GitLab has not enabled the flow for the instance' do
                before do
                  allow(Ai::Catalog::FoundationalFlows::EnabledFlowsClient).to receive(:enabled?)
                    .with('bl_security').and_return(false)
                end

                include_examples 'raises resource not available error'
              end
            end
          end
        end

        context 'when the scan profile is a skillguard profile' do
          let_it_be(:skillguard_profile) do
            create(:security_scan_profile, namespace: group, scan_type: :skillguard)
          end

          let(:id) { skillguard_profile.to_global_id }

          context 'when the skillguard_analyzer flag is enabled for the group' do
            before do
              stub_feature_flags(skillguard_analyzer: group)
            end

            it 'returns the scan profile' do
              expect(resolve_scan_profile(id)).to eq(skillguard_profile)
            end
          end

          context 'when the skillguard_analyzer flag is enabled only for the current user' do
            before do
              stub_feature_flags(skillguard_analyzer: current_user)
            end

            include_examples 'raises resource not available error'
          end

          context 'when the skillguard_analyzer flag is disabled' do
            before do
              stub_feature_flags(skillguard_analyzer: false)
            end

            include_examples 'raises resource not available error'
          end
        end

        context 'when scan profile is soft-deleted' do
          let(:id) { scan_profile.to_global_id }

          before do
            ::Security::ScanProfile.find(scan_profile.id).destroy!
          end

          include_examples 'raises resource not available error'
        end
      end

      context 'when resolving by scan type enum' do
        context 'when scan type exists' do
          let(:id) { build_scan_profile_gid('secret_detection') }

          it 'returns the default scan profile matching the scan type' do
            result = resolve_scan_profile(id)

            expect(result.scan_type).to eq('secret_detection')
          end
        end

        context 'when resolving the business logic default profile' do
          let(:id) { build_scan_profile_gid('business_logic') }

          it 'returns the business logic default profile' do
            expect(resolve_scan_profile(id).scan_type).to eq('business_logic')
          end

          context 'when the bl_security_analyzer flag is disabled' do
            before do
              stub_feature_flags(bl_security_analyzer: false)
            end

            # A virtual ID carries no namespace to check the flag against. Like the triage
            # presets, the static preset stays readable; creating it is gated elsewhere.
            it 'still returns the static preset' do
              expect(resolve_scan_profile(id).scan_type).to eq('business_logic')
            end
          end
        end

        context 'when scan type exists but default profile does not' do
          let(:id) { build_scan_profile_gid('container_scanning') }

          include_examples 'raises resource not available error'
        end

        context 'when scan type does not exist in enum' do
          let(:id) { build_scan_profile_gid('non_existing_enum_type') }

          include_examples 'raises resource not available error'
        end
      end

      context 'when resolving by preset key' do
        let(:preset_keys) do
          %w[
            triage_and_remediation_conservative
            triage_and_remediation_standard
            triage_and_remediation_proactive
          ]
        end

        it 'returns the default profile matching the preset key', :aggregate_failures do
          preset_keys.each do |preset_key|
            expect(resolve_scan_profile(build_scan_profile_gid(preset_key)))
              .to have_attributes(scan_type: 'triage_and_remediation', preset_key: preset_key)
          end
        end

        context 'when the preset key is unknown' do
          let(:id) { build_scan_profile_gid('triage_and_remediation_relaxed') }

          include_examples 'raises resource not available error'
        end
      end

      context 'when security_scan_profiles feature is disabled' do
        let(:id) { scan_profile.to_global_id }

        before do
          stub_licensed_features(security_scan_profiles: false)
        end

        include_examples 'raises resource not available error'
      end
    end
  end

  def resolve_scan_profile(id)
    resolve(resolver, args: { id: id }, ctx: { current_user: current_user }, arg_style: :internal)
  end

  def build_scan_profile_gid(id)
    GlobalID.new(::Gitlab::GlobalId.build(model_name: 'Security::ScanProfile', id: id))
  end
end
