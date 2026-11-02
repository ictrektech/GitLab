# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Govern::PolicyEvaluationsResolver, feature_category: :security_policy_management do
  include GraphqlHelpers
  include_context 'with policy store service authorization'
  include_context 'with policy store group containers'

  let_it_be(:organization_policy) { create(:govern_policy, :without_namespace, organization: organization) }
  let_it_be(:group_policy) { create(:govern_policy, namespace: group) }
  let_it_be(:other_group_policy) { create(:govern_policy, namespace: other_group) }

  let_it_be(:organization_evaluation) do
    create(:govern_policy_evaluation, policy: organization_policy, evaluated_at: 2.days.ago)
  end

  let_it_be(:group_evaluation) { create(:govern_policy_evaluation, policy: group_policy, evaluated_at: 1.day.ago) }
  let_it_be(:other_group_evaluation) { create(:govern_policy_evaluation, policy: other_group_policy) }

  let(:args) { {} }

  # The field is a connection, so unwrap the relation the resolver handed to it.
  subject(:result) { resolve(described_class, obj: container, args: args, ctx: { current_user: current_user }).items }

  specify do
    expect(described_class).to have_nullable_graphql_type(::Types::Govern::PolicyEvaluationType.connection_type)
  end

  # Every node carries its violations unpaginated, so a page costs evaluations times
  # violations. A smaller page halves the common case; nothing caps violations yet.
  it 'caps a page below the schema default' do
    expect(described_class.max_page_size).to eq(50)
    expect(described_class.max_page_size).to be < GitlabSchema.default_max_page_size
  end

  context 'when the parent is an organization' do
    it 'returns every evaluation the organization holds, newest first' do
      expect(result).to eq([other_group_evaluation, group_evaluation, organization_evaluation])
    end
  end

  context 'when the parent is a group' do
    let(:container) { group }

    it "returns only the evaluations of the group's own policies" do
      expect(result).to contain_exactly(group_evaluation)
    end

    context 'with filters' do
      let_it_be(:filtered_out_evaluation) do
        create(:govern_policy_evaluation, policy: group_policy, verdict: :deny, evaluated_at: 1.hour.ago)
      end

      let(:args) { { verdict: 'allow', evaluated_before: 12.hours.ago } }

      it 'applies them to the group evaluations' do
        expect(result).to contain_exactly(group_evaluation)
      end
    end
  end

  context 'when the parent is neither an organization nor a group' do
    let(:container) { build_stubbed(:project, organization: organization) }

    it 'returns no evaluations' do
      expect(result).to be_empty
    end
  end
end
