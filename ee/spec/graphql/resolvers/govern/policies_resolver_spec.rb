# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Govern::PoliciesResolver, :policy_store,
  feature_category: :security_policy_management do
  include GraphqlHelpers
  include_context 'with the policy store experiment active'

  let_it_be(:organization) { create(:organization) }
  let_it_be(:other_organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, :owner, organization: organization).user }

  let(:parent) { organization }
  let(:args) { {} }

  let!(:deployment_policy) do
    create_policy(organization_id: organization.id, name: 'Deployment policy', trigger_type: 'deployment_requested')
  end

  let!(:other_organization_policy) do
    create_policy(organization_id: other_organization.id, name: 'Other policy', trigger_type: 'deployment_requested')
  end

  before do
    opt_organization_into_policy_store!(organization)
  end

  subject(:result) { resolve_policies(args) }

  # The field applies the forward-only connection extension, so the helper must too
  # or `first`/`after` never reach the resolver and the result is a bare connection.
  def resolve_policies(args)
    resolve(
      described_class,
      obj: parent,
      args: args,
      ctx: { current_user: current_user },
      field_opts: { connection_extension: Gitlab::Graphql::Extensions::ForwardOnlyExternallyPaginatedArrayExtension }
    )
  end

  it 'returns only the policies of the organization as a single page', :aggregate_failures do
    expect(result.items).to contain_exactly(deployment_policy)
    expect(result.has_next_page).to be(false)
    expect(result.end_cursor).to be_nil
  end

  context 'with pagination arguments' do
    let!(:promoted_policy) do
      create_policy(organization_id: organization.id, name: 'Promoted policy', trigger_type: 'deployment_promoted')
    end

    let(:args) { { first: 1 } }

    it 'returns the first page with a cursor to the next one', :aggregate_failures do
      expect(result.items).to contain_exactly(deployment_policy)
      expect(result.has_next_page).to be(true)
      expect(result.end_cursor).to be_present
    end

    it 'walks every policy across pages without overlap', :aggregate_failures do
      second_page = resolve_policies(first: 1, after: result.end_cursor)

      expect(second_page.items).to contain_exactly(promoted_policy)
      expect(second_page.has_next_page).to be(false)
      expect(second_page.end_cursor).to be_nil
    end

    # The cursor is an offset, so the page size is free to change between requests.
    it 'continues from the same row when first changes between requests', :aggregate_failures do
      third_policy = create_policy(organization_id: organization.id, name: 'Third policy',
        trigger_type: 'deployment_requested')

      second_page = resolve_policies(first: 2, after: result.end_cursor)

      expect(second_page.items).to eq([promoted_policy, third_policy])
      expect(second_page.has_next_page).to be(false)
    end

    it 'passes the decoded offset straight to the service' do
      expect(::Security::SecurityOrchestrationPolicies::PolicyStore::ListService).to receive(:new)
        .with(hash_including(offset: 0, per_page: 1))
        .and_call_original

      result
    end

    context 'when first is 0' do
      let(:args) { { first: 0 } }

      # ListService clamps per_page to at least 1, so the resolver short-circuits instead.
      it 'returns an empty page without a next page', :aggregate_failures do
        expect(::Security::SecurityOrchestrationPolicies::PolicyStore::ListService).not_to receive(:new)

        expect(result.items).to be_empty
        expect(result.has_next_page).to be(false)
      end
    end

    context 'when first exceeds the port limit' do
      let(:args) { { first: Gitlab::PolicyStore::Ports::PolicyRepository::MAX_PER_PAGE + 1 } }

      it 'requests at most the field max page size from the service' do
        expect(::Security::SecurityOrchestrationPolicies::PolicyStore::ListService).to receive(:new)
          .with(hash_including(offset: 0, per_page: Gitlab::PolicyStore::Ports::PolicyRepository::MAX_PER_PAGE))
          .and_call_original

        result
      end
    end

    context 'with a cursor that is not base64' do
      let(:args) { { first: 1, after: 'not-a-valid-cursor' } }

      it 'returns an argument error naming the cursor' do
        expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ArgumentError, 'Invalid pagination cursor') do
          result
        end
      end
    end

    context 'with a cursor that decodes to something other than digits' do
      where(:raw_cursor) { %w[-3 1_0 +2] }

      with_them do
        let(:args) { { first: 1, after: Base64.strict_encode64(raw_cursor) } }

        it 'rejects it rather than coercing it to an offset' do
          expect_graphql_error_to_be_created(Gitlab::Graphql::Errors::ArgumentError, 'Invalid pagination cursor') do
            result
          end
        end
      end
    end

    context 'with a cursor for offset 0' do
      let(:args) { { first: 1, after: Base64.strict_encode64('0') } }

      # 0 is the first row, so it is a valid cursor rather than an edge case to reject.
      it 'returns the first page', :aggregate_failures do
        expect(result.items).to contain_exactly(deployment_policy)
        expect(result.has_next_page).to be(true)
      end
    end

    context 'with a cursor beyond the last offset the port serves' do
      let(:args) { { first: 1, after: Base64.strict_encode64('500000') } }

      # The service owns the clamp, so the resolver passes the offset through untouched.
      it 'lets the service clamp it instead of advertising rows it cannot reach', :aggregate_failures do
        expect(::Security::SecurityOrchestrationPolicies::PolicyStore::ListService).to receive(:new)
          .with(hash_including(offset: 500_000))
          .and_call_original

        expect(result.items).to be_empty
        expect(result.has_next_page).to be(false)
      end
    end

    context 'when paging near the port maximum offset' do
      def stub_service_window(offset:, per_page:)
        allow(::Security::SecurityOrchestrationPolicies::PolicyStore::ListService)
          .to receive(:new).and_wrap_original do |original, **kwargs|
          service = original.call(**kwargs)
          allow(service).to receive(:execute).and_return(
            ServiceResponse.success(
              payload: { policies: [deployment_policy], offset: offset, per_page: per_page, has_next_page: true }
            )
          )
          service
        end
      end

      context 'when the next offset is exactly the maximum' do
        let(:args) { { first: 1, after: Base64.strict_encode64((described_class::MAX_OFFSET - 1).to_s) } }

        # MAX_OFFSET itself is still served, so the boundary is inclusive.
        it 'still advertises the last reachable window', :aggregate_failures do
          stub_service_window(offset: described_class::MAX_OFFSET - 1, per_page: 1)

          expect(result.has_next_page).to be(true)
          expect(result.end_cursor).to eq(Base64.strict_encode64(described_class::MAX_OFFSET.to_s))
        end
      end

      context 'when the next offset would pass the maximum' do
        let(:args) { { first: 1, after: Base64.strict_encode64(described_class::MAX_OFFSET.to_s) } }

        # A cursor past MAX_OFFSET clamps back to the same window, so a client would loop.
        it 'reports no next page even though the service says more rows follow', :aggregate_failures do
          stub_service_window(offset: described_class::MAX_OFFSET, per_page: 1)

          expect(result.items).to contain_exactly(deployment_policy)
          expect(result.has_next_page).to be(false)
          expect(result.end_cursor).to be_nil
        end
      end
    end
  end

  context 'when the parent is a group' do
    include_context 'with policy store service authorization'
    include_context 'with policy store group containers'

    let(:parent) { group }
    let(:current_user) { group_owner }

    let!(:group_policy) do
      create_policy(
        organization_id: organization.id,
        namespace_id: group.id,
        name: 'Group policy',
        trigger_type: 'project.before_settings_update'
      )
    end

    let!(:other_group_policy) do
      create_policy(
        organization_id: organization.id,
        namespace_id: other_group.id,
        name: 'Other group policy',
        trigger_type: 'project.before_settings_update'
      )
    end

    it "returns the group's own and inherited organization-wide policies, but not a sibling group's" do
      expect(result.items).to contain_exactly(group_policy, deployment_policy)
    end

    context 'with a trigger_type argument' do
      let!(:promoted_group_policy) do
        create_policy(
          organization_id: organization.id,
          namespace_id: group.id,
          name: 'Promoted group policy',
          trigger_type: 'project.after_create'
        )
      end

      let(:args) { { trigger_type: 'project.after_create' } }

      it 'returns only the group policies responding to the trigger' do
        expect(result.items).to contain_exactly(promoted_group_policy)
      end
    end

    context 'with an ids argument' do
      let!(:another_group_policy) do
        create_policy(
          organization_id: organization.id,
          namespace_id: group.id,
          name: 'Another group policy',
          trigger_type: 'project.before_settings_update'
        )
      end

      let(:args) { { ids: [group_policy.id] } }

      it 'returns only the group policies with those ids' do
        expect(result.items).to contain_exactly(group_policy)
      end
    end

    context 'when the user is not a group owner' do
      let(:current_user) { create(:user) }

      it { is_expected.to be_nil }
    end

    context 'when the experiment is disabled for the group' do
      let_it_be(:disabled_group) do
        create(:group, organization: organization).tap do |g|
          g.namespace_settings.update!(policy_store_experiment_enabled: false)
          g.add_owner(group_owner)
        end
      end

      let(:parent) { disabled_group }

      it { is_expected.to be_nil }
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(security_policies_v2: false)
      end

      it { is_expected.to be_nil }
    end

    describe 'schema execution' do
      it 'resolves policies through the group policyStore field' do
        result = GitlabSchema.execute(
          "{ group(fullPath: \"#{group.full_path}\") " \
            '{ policyStore { policies { nodes { id name triggerType namespaceId } } } } }',
          context: { current_user: group_owner }
        ).to_h

        expect(result['errors']).to be_nil
        expect(result.dig('data', 'group', 'policyStore', 'policies', 'nodes')).to contain_exactly(
          { 'id' => group_policy.id, 'name' => 'Group policy', 'triggerType' => 'project.before_settings_update',
            'namespaceId' => group.id },
          { 'id' => deployment_policy.id, 'name' => 'Deployment policy', 'triggerType' => 'deployment_requested',
            'namespaceId' => nil }
        )
      end
    end
  end

  context 'with a trigger_type argument' do
    let(:args) { { trigger_type: 'deployment_requested' } }

    it 'returns the policies responding to the trigger' do
      expect(result.items).to contain_exactly(deployment_policy)
    end

    context 'with a trigger type REST rejects as invalid' do
      let(:args) { { trigger_type: 'unknown_trigger' } }

      # Deliberate divergence: REST returns 400 for unknown triggers, GraphQL keeps the
      # argument a String (the catalog is data) and returns an empty list instead.
      it { expect(result.items).to be_empty }
    end
  end

  context 'with an ids argument' do
    let!(:promoted_policy) do
      create_policy(organization_id: organization.id, name: 'Promoted policy', trigger_type: 'deployment_promoted')
    end

    let(:args) { { ids: [deployment_policy.id] } }

    it 'returns only the policies with those ids' do
      expect(result.items).to contain_exactly(deployment_policy)
    end

    # The port returns every id match at once, and the connection would truncate
    # them to `first` while still reporting no next page, so the pair is rejected.
    context 'when combined with first' do
      let(:args) { { ids: [deployment_policy.id, promoted_policy.id], first: 1 } }

      it 'rejects the combination' do
        expect_graphql_error_to_be_created(
          Gitlab::Graphql::Errors::ArgumentError, 'ids cannot be combined with first or after'
        ) { result }
      end
    end

    context 'when combined with after' do
      let(:args) { { ids: [deployment_policy.id], after: Base64.strict_encode64('0') } }

      it 'rejects the combination' do
        expect_graphql_error_to_be_created(
          Gitlab::Graphql::Errors::ArgumentError, 'ids cannot be combined with first or after'
        ) { result }
      end
    end

    context 'when combined with trigger_type' do
      let(:args) { { ids: [deployment_policy.id, promoted_policy.id], trigger_type: 'deployment_promoted' } }

      it 'returns only the policies matching both filters' do
        expect(result.items).to contain_exactly(promoted_policy)
      end
    end

    context 'with ids no policy has' do
      let(:args) { { ids: [non_existing_record_id] } }

      it { expect(result.items).to be_empty }
    end

    context 'when the user is not an organization owner and passes ids' do
      let_it_be(:current_user) { create(:user) }

      it { is_expected.to be_nil }
    end

    context 'when ids exceeds the port limit' do
      let(:args) { { ids: Array.new(Gitlab::PolicyStore::Ports::PolicyRepository::MAX_PER_PAGE + 1) { |index| index } } }

      # graphql-ruby catches a GraphQL::ExecutionError raised from #resolve and returns it
      # as the field's value rather than letting it propagate, so it is asserted here, not raised.
      it 'returns a GraphQL execution error naming the limit', :aggregate_failures do
        expect(result).to be_a(GraphQL::ExecutionError)
        expect(result.message).to match(/ids exceeds maximum/)
      end
    end
  end

  context 'when the user is not an organization owner' do
    let_it_be(:current_user) { create(:user) }

    it { is_expected.to be_nil }
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(security_policies_v2: false)
    end

    it { is_expected.to be_nil }
  end

  context 'when the experiment is disabled for the instance' do
    before do
      stub_application_setting(policy_store_experiment_enabled: false)
    end

    it { is_expected.to be_nil }
  end

  context 'when the license does not include security orchestration policies' do
    before do
      stub_licensed_features(security_orchestration_policies: false)
    end

    it { is_expected.to be_nil }
  end

  describe 'schema execution' do
    let_it_be(:organization_owner) { create(:organization_user, :owner, organization: organization).user }

    it 'resolves ids through the value object, which BaseObject#id cannot answer' do
      result = GitlabSchema.execute(
        "{ organization(id: \"#{organization.to_global_id}\") " \
          '{ policyStore { policies { nodes { id name triggerType } pageInfo { hasNextPage endCursor } } } } }',
        context: { current_user: organization_owner }
      ).to_h

      expect(result['errors']).to be_nil
      expect(result.dig('data', 'organization', 'policyStore', 'policies', 'nodes')).to contain_exactly(
        { 'id' => deployment_policy.id, 'name' => 'Deployment policy', 'triggerType' => 'deployment_requested' }
      )
      expect(result.dig('data', 'organization', 'policyStore', 'policies', 'pageInfo')).to eq(
        { 'hasNextPage' => false, 'endCursor' => nil }
      )
    end

    it 'returns every id match through the field when ids are given without pagination arguments' do
      promoted_policy = create_policy(
        organization_id: organization.id, name: 'Promoted policy', trigger_type: 'deployment_promoted'
      )

      result = GitlabSchema.execute(
        "{ organization(id: \"#{organization.to_global_id}\") { policyStore " \
          "{ policies(ids: [#{deployment_policy.id}, #{promoted_policy.id}]) " \
          '{ nodes { name } pageInfo { hasNextPage } } } } }',
        context: { current_user: organization_owner }
      ).to_h

      expect(result['errors']).to be_nil
      expect(result.dig('data', 'organization', 'policyStore', 'policies', 'nodes').pluck('name'))
        .to contain_exactly('Deployment policy', 'Promoted policy')
    end

    it 'caps first at the port page size through the real field' do
      expect(::Security::SecurityOrchestrationPolicies::PolicyStore::ListService).to receive(:new)
        .with(hash_including(per_page: Gitlab::PolicyStore::Ports::PolicyRepository::MAX_PER_PAGE))
        .and_call_original

      result = GitlabSchema.execute(
        "{ organization(id: \"#{organization.to_global_id}\") { policyStore " \
          "{ policies(first: #{Gitlab::PolicyStore::Ports::PolicyRepository::MAX_PER_PAGE + 1}) { nodes { id } } } } }",
        context: { current_user: organization_owner }
      ).to_h

      expect(result['errors']).to be_nil
    end
  end
end
