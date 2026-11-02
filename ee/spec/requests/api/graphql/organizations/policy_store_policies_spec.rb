# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organization policyStore policies', :policy_store, feature_category: :security_policy_management do
  include GraphqlHelpers
  include_context 'with the policy store experiment active'

  let_it_be(:organization) { create(:organization) }
  let_it_be(:other_organization) { create(:organization) }
  let_it_be(:organization_owner) { create(:organization_user, :owner, organization: organization).user }
  let_it_be(:organization_member) { create(:organization_user, organization: organization).user }

  let(:current_user) { organization_owner }
  let(:trigger_type) { nil }
  let(:ids) { nil }
  let(:first) { nil }
  let(:after) { nil }

  let(:query) do
    <<~QUERY
      query organizationPolicyStorePolicies(
        $id: OrganizationsOrganizationID!, $triggerType: String, $ids: [Int!], $first: Int, $after: String
      ) {
        organization(id: $id) {
          policyStore {
            policies(triggerType: $triggerType, ids: $ids, first: $first, after: $after) {
              nodes {
                id
                organizationId
                name
                triggerType
                policyRego
                scopeRego
                mode
                lifecycleState
                createdAt
                updatedAt
              }
              pageInfo {
                hasNextPage
                endCursor
              }
            }
          }
        }
      }
    QUERY
  end

  let!(:deployment_policy) do
    create_policy(organization_id: organization.id, name: 'Deployment policy', trigger_type: 'deployment_requested')
  end

  let!(:other_organization_policy) do
    create_policy(organization_id: other_organization.id, name: 'Other policy', trigger_type: 'deployment_requested')
  end

  before do
    opt_organization_into_policy_store!(organization)
  end

  subject(:request) do
    post_graphql(
      query,
      current_user: current_user,
      variables: { id: organization.to_global_id.to_s, triggerType: trigger_type, ids: ids, first: first, after: after }
    )
  end

  def policy_store
    graphql_data.dig('organization', 'policyStore')
  end

  def policies_connection
    policy_store&.fetch('policies')
  end

  def policies
    policies_connection&.fetch('nodes')
  end

  def page_info
    policies_connection&.fetch('pageInfo')
  end

  it 'returns the policies of the organization as a single page', :aggregate_failures do
    request

    expect(page_info).to eq('hasNextPage' => false, 'endCursor' => nil)
    expect(policies).to contain_exactly(
      a_hash_including(
        'id' => deployment_policy.id,
        'organizationId' => organization.id,
        'name' => 'Deployment policy',
        'triggerType' => 'deployment_requested',
        'policyRego' => nil,
        'mode' => 'warn',
        'lifecycleState' => 'active'
      )
    )
  end

  context 'when the organization is the default one on GitLab.com',
    :saas_policy_store_default_organization_isolation do
    include_context 'with the default organization as the policy store container'

    let(:organization) { default_organization }

    before do
      create_policy(
        organization_id: default_organization.id, namespace_id: default_organization_group.id,
        name: 'Group policy', trigger_type: 'project.before_settings_update'
      )
    end

    it 'returns no policies' do
      request

      expect_graphql_errors_to_be_empty
      expect(policies).to be_empty
    end

    context 'with a trigger that carries the group hierarchy' do
      let(:trigger_type) { 'project.before_settings_update' }

      it 'returns the error' do
        request

        expect(graphql_errors).to contain_exactly(a_hash_including(
          'message' => 'namespace_ids is required for this trigger in the default organization'
        ))
      end
    end
  end

  context "when a policy belongs to a private group the organization owner isn't a member of" do
    let_it_be(:private_group) { create(:group, :private, organization: organization) }

    let(:query) do
      <<~QUERY
        query organizationPolicyStorePolicies($id: OrganizationsOrganizationID!) {
          organization(id: $id) {
            policyStore { policies { nodes { name namespaceId } } }
          }
        }
      QUERY
    end

    before do
      create_policy(
        organization_id: organization.id, namespace_id: private_group.id, name: 'Private group policy',
        trigger_type: 'project.before_settings_update'
      )
    end

    it 'returns its namespace id, because the organization owner can read every group of the organization' do
      request

      expect(policies).to include({ 'name' => 'Private group policy', 'namespaceId' => private_group.id })
    end
  end

  context 'when the policy rules carry compiled rego' do
    let!(:rego_policy) do
      create_policy(
        organization_id: organization.id, name: 'Rego policy', trigger_type: 'deployment_requested',
        rules: [{ 'type' => 'custom', 'value' => "package governance\ndeny := true\n" }]
      )
    end

    let(:ids) { [rego_policy.id] }

    it 'exposes policyRego as the merged governance module, mirroring REST' do
      request

      expect(policies).to contain_exactly(
        a_hash_including('name' => 'Rego policy', 'policyRego' => "package governance\ndeny := true\n")
      )
    end
  end

  context 'with pagination' do
    let!(:promoted_policy) do
      create_policy(organization_id: organization.id, name: 'Promoted policy', trigger_type: 'deployment_promoted')
    end

    let(:first) { 1 }

    it 'walks every policy of the organization one page at a time', :aggregate_failures do
      request

      expect(policies).to contain_exactly(a_hash_including('name' => 'Deployment policy'))
      expect(page_info).to include('hasNextPage' => true)
      expect(page_info['endCursor']).to be_present

      post_graphql(
        query,
        current_user: current_user,
        variables: { id: organization.to_global_id.to_s, first: 1, after: page_info['endCursor'] }
      )

      expect(policies).to contain_exactly(a_hash_including('name' => 'Promoted policy'))
      expect(page_info).to eq('hasNextPage' => false, 'endCursor' => nil)
    end

    it 'continues from the same row when first changes between requests', :aggregate_failures do
      create_policy(organization_id: organization.id, name: 'Third policy', trigger_type: 'deployment_requested')

      request

      expect(policies.pluck('name')).to eq(['Deployment policy'])

      post_graphql(
        query,
        current_user: current_user,
        variables: { id: organization.to_global_id.to_s, first: 2, after: page_info['endCursor'] }
      )

      expect(policies.pluck('name')).to eq(['Promoted policy', 'Third policy'])
      expect(page_info).to eq('hasNextPage' => false, 'endCursor' => nil)
    end

    context 'with an invalid cursor' do
      let(:after) { 'not-a-valid-cursor' }

      it 'returns an argument error' do
        request

        expect_graphql_errors_to_include('Invalid pagination cursor')
      end
    end

    context 'with a last argument' do
      let(:query) do
        <<~QUERY
          query organizationPolicyStorePolicies($id: OrganizationsOrganizationID!) {
            organization(id: $id) {
              policyStore {
                policies(last: 1) { nodes { name } }
              }
            }
          }
        QUERY
      end

      # Forward-only: the port has no reverse cursor, so `last`/`before` are not exposed.
      it 'rejects the argument, since the connection paginates forward only' do
        request

        expect_graphql_errors_to_include(
          /'last' doesn't exist on type 'PolicyStore'|Field 'policies' doesn't accept argument 'last'/
        )
      end
    end
  end

  context 'with a triggerType filter' do
    context 'when policies respond to the trigger' do
      let(:trigger_type) { 'deployment_requested' }

      it 'returns the matching policies' do
        request

        expect(policies).to contain_exactly(a_hash_including('name' => 'Deployment policy'))
      end
    end

    context 'with a trigger type REST rejects as invalid' do
      let(:trigger_type) { 'unknown_trigger' }

      # Deliberate divergence: REST returns 400 for unknown triggers, GraphQL keeps the
      # argument a String (the catalog is data) and returns an empty list instead.
      it 'returns an empty list rather than an error' do
        request

        expect(policies).to eq([])
        expect_graphql_errors_to_be_empty
      end
    end
  end

  context 'with an ids filter' do
    let!(:promoted_policy) do
      create_policy(organization_id: organization.id, name: 'Promoted policy', trigger_type: 'deployment_promoted')
    end

    let(:ids) { [deployment_policy.id] }

    it 'returns only the policies with those ids' do
      request

      expect(policies).to contain_exactly(a_hash_including('name' => 'Deployment policy'))
    end

    context 'when combined with triggerType' do
      let(:ids) { [deployment_policy.id, promoted_policy.id] }
      let(:trigger_type) { 'deployment_promoted' }

      it 'returns only the policies matching both filters' do
        request

        expect(policies).to contain_exactly(a_hash_including('name' => 'Promoted policy'))
      end
    end

    context 'with ids no policy has' do
      let(:ids) { [non_existing_record_id] }

      it 'returns an empty list rather than an error' do
        request

        expect(policies).to eq([])
        expect_graphql_errors_to_be_empty
      end
    end

    context 'when combined with first' do
      let(:ids) { [deployment_policy.id, promoted_policy.id] }
      let(:first) { 1 }

      # Rejected rather than truncated: the connection would otherwise drop one of the
      # requested policies and still report hasNextPage false.
      it 'returns an argument error' do
        request

        expect_graphql_errors_to_include('ids cannot be combined with first or after')
      end
    end
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', [:read_govern_policy, :read_organization] do
    let_it_be(:granular_organization) { create(:organization) }

    # Without a policy the granted case would pass vacuously on an empty list.
    let!(:granular_policy) do
      create_policy(organization_id: granular_organization.id, name: 'Granular policy',
        trigger_type: 'deployment_requested')
    end

    let(:user) { create(:organization_user, :owner, organization: granular_organization).user }
    let(:boundary_object) { :instance }
    let(:query) do
      <<~QUERY
        query organizationPolicyStorePolicies($id: OrganizationsOrganizationID!) {
          organization(id: $id) {
            policyStore {
              policies { nodes { name } }
            }
          }
        }
      QUERY
    end

    let(:request) do
      post_graphql(query, variables: { id: granular_organization.to_global_id.to_s },
        token: { personal_access_token: pat })
    end

    before do
      opt_organization_into_policy_store!(granular_organization)
    end
  end

  context 'with an instance-scoped token and a group-owned policy' do
    let_it_be(:owned_group) { create(:group, organization: organization) }
    let_it_be(:token_owner) { create(:organization_user, :owner, organization: organization).user }

    let!(:group_owned_policy) do
      create_policy(organization_id: organization.id, namespace_id: owned_group.id, name: 'Group-owned policy',
        trigger_type: 'project.before_settings_update')
    end

    let(:pat) do
      assignables = [:read_govern_policy, :read_organization].map do |permission|
        ::Authz::PermissionGroups::Assignable.for_permission(permission).min_by(&:name).name
      end

      create(:granular_pat, user: token_owner, boundary: ::Authz::Boundary.for(:instance),
        permissions: assignables.uniq)
    end

    it 'returns the group-owned policy alongside the organization-wide one' do
      post_graphql(query, variables: { id: organization.to_global_id.to_s }, token: { personal_access_token: pat })

      expect(policies.pluck('name')).to contain_exactly('Deployment policy', 'Group-owned policy')
    end
  end

  context 'when the user is an organization member without the owner role' do
    let(:current_user) { organization_member }

    it 'returns null policies while the catalogs stay reachable' do
      request

      expect(policy_store).to be_present
      expect(policies).to be_nil
      expect_graphql_errors_to_be_empty
    end
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(security_policies_v2: false)
    end

    it 'returns a null policyStore, so the flag works as a kill switch on its own' do
      request

      expect(policy_store).to be_nil
    end
  end

  context 'when the experiment is disabled for the instance' do
    before do
      stub_application_setting(policy_store_experiment_enabled: false)
    end

    it 'returns a null policyStore' do
      request

      expect(policy_store).to be_nil
    end
  end

  context 'when the license does not include security orchestration policies' do
    before do
      stub_licensed_features(security_orchestration_policies: false)
    end

    it 'returns a null policyStore' do
      request

      expect(policy_store).to be_nil
    end
  end
end
