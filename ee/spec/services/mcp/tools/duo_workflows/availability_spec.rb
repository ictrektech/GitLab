# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::DuoWorkflows::Availability, :request_store, feature_category: :mcp_server do
  using RSpec::Parameterized::TableSyntax

  let_it_be_with_refind(:user) { create(:user) }

  let(:tool) { Mcp::Tools::DuoWorkflows::GetDuoSessionService.new(name: 'get_duo_session') }

  subject(:available?) { tool.available?(user) }

  it 'is included by every duo_agent_platform tool', :aggregate_failures do
    dap_tools = Mcp::Tools::Manager.new.tools.values.select { |t| t.toolset == :duo_agent_platform }

    expect(dap_tools.map(&:class)).to contain_exactly(
      Mcp::Tools::DuoWorkflows::GetDuoSessionService,
      Mcp::Tools::DuoWorkflows::ListDuoAgentsAndFlowsService,
      Mcp::Tools::DuoWorkflows::ListDuoSessionsService,
      Mcp::Tools::DuoWorkflows::SendDuoSessionInputService,
      Mcp::Tools::DuoWorkflows::StartDuoSessionService
    )
    expect(dap_tools).to all(be_a(described_class))
  end

  context 'when user is nil' do
    it { expect(tool.available?(nil)).to be(false) }
  end

  context 'when on GitLab.com', :saas do
    let_it_be(:group) { create(:group, guests: user) }

    before do
      stub_licensed_features(ai_workflows: true)
    end

    context 'when the user belongs to a top-level group on a supported plan with DAP turned on' do
      before do
        create(:gitlab_subscription, namespace: group, hosted_plan: create(:premium_plan))
        create(:namespace_ai_settings, namespace: group, feature_settings: { duo_agent_platform_enabled: true })
      end

      context 'when the user has a Duo seat' do
        before do
          purchase = create(:gitlab_subscription_add_on_purchase, :duo_enterprise, namespace: group)
          create(:gitlab_subscription_user_add_on_assignment, user: user, add_on_purchase: purchase)
        end

        it { is_expected.to be(true) }

        it 'runs the check once per user within a request' do
          tool.available?(user)

          expect { tool.available?(user) }.not_to exceed_query_limit(0)
        end
      end

      context 'when the user has no Duo seat' do
        before do
          purchase = create(:gitlab_subscription_add_on_purchase, :duo_enterprise, namespace: group)
          create(:gitlab_subscription_user_add_on_assignment, add_on_purchase: purchase)
        end

        it { is_expected.to be(false) }
      end
    end

    context 'when the user has a Duo seat in a group with DAP turned off' do
      before do
        create(:gitlab_subscription, namespace: group, hosted_plan: create(:premium_plan))
        create(:namespace_ai_settings, namespace: group, feature_settings: { duo_agent_platform_enabled: false })
        purchase = create(:gitlab_subscription_add_on_purchase, :duo_enterprise, namespace: group)
        create(:gitlab_subscription_user_add_on_assignment, user: user, add_on_purchase: purchase)
      end

      it { is_expected.to be(false) }
    end

    context 'when the user belongs only to a free group' do
      it { is_expected.to be(false) }
    end
  end

  context 'when on Self-Managed' do
    where(:duo_availability, :ai_workflows_license, :entitlement, :dap_setting, :excluded_by_rule, :expected) do
      :default_on  | true  | :seat    | true  | false | true
      :default_off | true  | :seat    | true  | false | true
      :never_on    | true  | :seat    | true  | false | false
      :default_on  | false | :credits | true  | false | true
      :default_on  | false | :seat    | true  | false | false
      :default_on  | true  | :seat    | false | false | false
      :default_on  | true  | :none    | true  | false | false
      :default_on  | true  | :seat    | true  | true  | false
    end

    with_them do
      before do
        stub_application_setting(
          duo_features_enabled: duo_availability == :default_on,
          lock_duo_features_enabled: duo_availability == :never_on
        )
        stub_licensed_features(ai_workflows: ai_workflows_license)

        case entitlement
        when :seat
          purchase = create(:gitlab_subscription_add_on_purchase, :self_managed, :duo_enterprise)
          create(:gitlab_subscription_user_add_on_assignment, user: user, add_on_purchase: purchase)
        when :credits
          create(:gitlab_subscription_add_on_purchase, :gitlab_credits, :self_managed)
        end

        ::Ai::Setting.for_organization(user.organization)
          .update!(feature_settings: { duo_agent_platform_enabled: dap_setting })

        create(:ai_instance_accessible_entity_rules, :duo_agent_platform) if excluded_by_rule
      end

      it { is_expected.to be(expected) }
    end
  end
end
