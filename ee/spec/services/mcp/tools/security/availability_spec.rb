# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Security::Availability, :request_store, feature_category: :mcp_server do
  using RSpec::Parameterized::TableSyntax

  let_it_be_with_refind(:user) { create(:user) }

  it 'is included by every code_security tool', :aggregate_failures do
    security_tools = Mcp::Tools::Manager.new.tools.values.select { |t| t.toolset == :code_security }

    expect(security_tools.map(&:class)).to contain_exactly(
      Mcp::Tools::Security::AttachScanProfileService,
      Mcp::Tools::Security::GetVulnerabilityService,
      Mcp::Tools::Security::ListVulnerabilitiesService,
      Mcp::Tools::Security::SaveVulnerabilityService
    )
    expect(security_tools).to all(be_a(described_class))
  end

  where(:tool_class, :tool_name, :licensed_feature) do
    Mcp::Tools::Security::GetVulnerabilityService    | 'get_vulnerability'    | :security_dashboard
    Mcp::Tools::Security::ListVulnerabilitiesService | 'list_vulnerabilities' | :security_dashboard
    Mcp::Tools::Security::SaveVulnerabilityService   | 'save_vulnerability'   | :security_dashboard
    Mcp::Tools::Security::AttachScanProfileService   | 'attach_scan_profile'  | :security_scan_profiles
  end

  with_them do
    let(:tool) { tool_class.new(name: tool_name) }

    subject(:available?) { tool.available?(user) }

    context 'when user is nil' do
      it { expect(tool.available?(nil)).to be(false) }
    end

    context 'when on Self-Managed' do
      it 'is available when the instance license includes the feature' do
        stub_licensed_features(licensed_feature => true)

        expect(available?).to be(true)
      end

      it 'is not available when the instance license does not include the feature' do
        stub_licensed_features(licensed_feature => false)

        expect(available?).to be(false)
      end
    end

    context 'when on GitLab.com', :saas_gitlab_com_subscriptions do
      let_it_be(:group) { create(:group, developers: user) }

      before do
        stub_licensed_features(licensed_feature => true)
      end

      context 'when the user belongs to a top-level group on the Ultimate plan' do
        before do
          create(:gitlab_subscription, namespace: group, hosted_plan: create(:ultimate_plan))
        end

        it { is_expected.to be(true) }

        it 'runs the check once per user within a request' do
          tool.available?(user)

          expect { tool.available?(user) }.not_to exceed_query_limit(0)
        end
      end

      context 'when the user has access to an Ultimate project but not its group' do
        let_it_be(:ultimate_group) { create(:group) }
        let_it_be(:project) { create(:project, group: ultimate_group, developers: user) }

        before do
          create(:gitlab_subscription, namespace: ultimate_group, hosted_plan: create(:ultimate_plan))
        end

        it { is_expected.to be(true) }
      end

      context 'when the user belongs only to a Premium group' do
        before do
          create(:gitlab_subscription, namespace: group, hosted_plan: create(:premium_plan))
        end

        it { is_expected.to be(false) }
      end

      context 'when the user belongs only to a free group' do
        it { is_expected.to be(false) }
      end
    end
  end
end
