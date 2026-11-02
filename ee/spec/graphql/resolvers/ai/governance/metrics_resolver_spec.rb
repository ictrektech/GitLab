# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Ai::Governance::MetricsResolver, feature_category: :compliance_management do
  include GraphqlHelpers

  it 'has the correct nullable graphql type' do
    expect(described_class).to have_nullable_graphql_type(Types::Ai::Governance::MetricsType)
  end

  it 'has the expected arguments' do
    expect(described_class).to have_graphql_arguments(:timeframe, :agent_class)
  end

  it 'defines the timeframe argument as optional with the expected type and default' do
    argument = described_class.arguments['timeframe']

    expect(argument.type).to eq(Types::Ai::Governance::MetricsTimeframeEnum)
    expect(argument.default_value).to eq(:last_7_days)
  end

  it 'defines the agent_class argument as optional with the expected type and default' do
    argument = described_class.arguments['agentClass']

    expect(argument.type).to eq(Types::Ai::Governance::AgentClassEnum)
    expect(argument.default_value).to eq(:all)
  end

  it 'authorizes read_agent_artifacts' do
    expect(described_class).to require_graphql_authorizations(:read_agent_artifacts)
  end

  describe '#resolve' do
    let_it_be(:group) { create(:group) }
    let_it_be(:member_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: group) }
    let_it_be(:user) { create(:user) }
    let_it_be(:membership) { create(:group_member, :guest, member_role: member_role, user: user, group: group) }

    let(:lookahead) do
      instance_double(GraphQL::Execution::Lookahead, selections: [], selects?: false).tap do |lookahead|
        allow(lookahead).to receive(:selects?).with(:session_distribution).and_return(session_distribution_selected)
      end
    end

    let(:session_distribution_selected) { true }

    before do
      stub_licensed_features(custom_roles: true, group_level_compliance_dashboard: true)
    end

    def resolve_metrics
      resolve(described_class, obj: group, ctx: { current_user: user }, lookahead: lookahead,
        args: { timeframe: :last_7_days, agent_class: :all })
    end

    def expect_session_distribution(requested)
      expect(::Ai::Governance::MetricsService).to receive(:new)
        .with(group, hash_including(session_distribution: requested))
        .and_return(instance_double(::Ai::Governance::MetricsService,
          execute: ServiceResponse.success(payload: {})))
    end

    it 'requests the session distribution when it is selected' do
      expect_session_distribution(true)

      resolve_metrics
    end

    context 'when the session distribution is not selected' do
      let(:session_distribution_selected) { false }

      it 'does not request it' do
        expect_session_distribution(false)

        resolve_metrics
      end
    end

    context 'when the ai_governance_dashboard_charts feature flag is disabled' do
      before do
        stub_feature_flags(ai_governance_dashboard_charts: false)
      end

      it 'does not request the session distribution' do
        expect_session_distribution(false)

        resolve_metrics
      end
    end
  end
end
