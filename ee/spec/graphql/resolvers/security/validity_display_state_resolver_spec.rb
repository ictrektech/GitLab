# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Security::ValidityDisplayStateResolver, feature_category: :secret_detection do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:project) { create(:project, developers: user) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
  let_it_be(:build) { create(:ci_build, pipeline: pipeline) }
  let_it_be(:security_scan) { create(:security_scan, project: project, build: build, scan_type: :secret_detection) }

  specify do
    expect(described_class)
      .to have_nullable_graphql_type(Types::Vulnerabilities::ValidityDisplayStateEnum)
  end

  describe '#resolve' do
    before do
      stub_licensed_features(security_dashboard: true, secret_detection_validity_checks: true)
      project.security_setting.update!(validity_checks_enabled: true)
    end

    def finding_with(external_type:, external_id:)
      create(:security_finding,
        scan: security_scan,
        finding_data: {
          'identifiers' => [
            { 'external_type' => external_type, 'external_id' => external_id, 'name' => external_id }
          ],
          'raw_source_code_extract' => 'fake-token-value'
        }
      )
    end

    def resolve_state(finding)
      resolve(described_class, obj: finding, ctx: { current_user: user }, arg_style: :internal)
    end

    context 'with a token type supported for the detecting analyzer' do
      let(:finding) do
        finding_with(
          external_type: ::Security::SecretDetection::RuleIdentifiers::GITLEAKS_TYPE,
          external_id: 'gitlab_personal_access_token'
        )
      end

      it 'returns pending_verification when no status row exists' do
        expect(resolve_state(finding).value).to eq('pending_verification')
      end

      it 'returns the stored status when a row exists' do
        create(:security_finding_token_status, security_finding: finding, status: :active)

        expect(resolve_state(finding).value).to eq('active')
      end
    end

    context 'with a token type supported only for the other analyzer' do
      let(:finding) do
        finding_with(
          external_type: ::Security::SecretDetection::RuleIdentifiers::GITLEAKS_TYPE,
          external_id: 'OpenAiProjectKey'
        )
      end

      it 'returns not_checked_by_analyzer' do
        expect(resolve_state(finding)).to eq('not_checked_by_analyzer')
      end

      # A status row left over from before scheduling was restricted must
      # not show as a verdict.
      it 'ignores a leftover status row' do
        create(:security_finding_token_status, security_finding: finding, status: :inactive)

        expect(resolve_state(finding)).to eq('not_checked_by_analyzer')
      end
    end

    context 'with a token type in no registry' do
      let(:finding) do
        finding_with(
          external_type: ::Security::SecretDetection::RuleIdentifiers::GITLEAKS_TYPE,
          external_id: 'no_such_vendor_token'
        )
      end

      it 'returns no_vendor_support' do
        expect(resolve_state(finding)).to eq('no_vendor_support')
      end
    end

    context 'when the display gates fail' do
      let(:finding) do
        finding_with(
          external_type: ::Security::SecretDetection::RuleIdentifiers::GITLEAKS_TYPE,
          external_id: 'gitlab_personal_access_token'
        )
      end

      it 'returns nil when the project setting is disabled' do
        project.security_setting.update!(validity_checks_enabled: false)

        expect(resolve_state(finding)).to be_nil
      end

      it 'returns nil when the license is missing' do
        stub_licensed_features(security_dashboard: true, secret_detection_validity_checks: false)

        expect(resolve_state(finding)).to be_nil
      end

      it 'returns nil for a non secret detection finding' do
        sast_scan = create(:security_scan, project: project, build: build, scan_type: :sast)
        sast_finding = create(:security_finding, scan: sast_scan)

        expect(resolve_state(sast_finding)).to be_nil
      end

      it 'returns nil when the project has no security setting' do
        project.security_setting.destroy!

        expect(resolve_state(finding.reload)).to be_nil
      end

      it 'returns nil without a finding' do
        expect(resolve_state(nil)).to be_nil
      end

      it 'returns nil for a user without read_vulnerability' do
        non_member = create(:user)

        result = resolve(described_class, obj: finding, ctx: { current_user: non_member }, arg_style: :internal)

        expect(result).to be_nil
      end
    end
  end
end
