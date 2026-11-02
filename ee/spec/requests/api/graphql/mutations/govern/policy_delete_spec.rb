# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Deleting a policy in the policy store', :policy_store, feature_category: :security_policy_management do
  include GraphqlHelpers
  include_context 'with the policy store experiment active'

  let_it_be(:organization) { create(:organization) }
  let_it_be(:organization_owner) { create(:organization_user, :owner, organization: organization).user }
  let_it_be(:organization_member) { create(:organization_user, organization: organization).user }

  let(:current_user) { organization_owner }

  let!(:policy) do
    create_policy(
      organization_id: organization.id,
      name: 'Block production deployments',
      trigger_type: 'deployment_requested'
    )
  end

  # A second policy pins the blast radius: deleting one policy must not touch others.
  let!(:other_policy) do
    create_policy(
      organization_id: organization.id,
      name: 'Require approval on secrets access',
      trigger_type: 'deployment_requested'
    )
  end

  let(:policy_id) { policy.id }

  let(:params) do
    {
      organization_id: organization.to_global_id.to_s,
      id: policy_id
    }
  end

  let(:mutation) { graphql_mutation(:govern_policy_delete, params) }

  before do
    opt_organization_into_policy_store!(organization)
  end

  subject(:request) { post_graphql_mutation(mutation, current_user: current_user) }

  def mutation_response
    graphql_mutation_response(:govern_policy_delete)
  end

  def organization_policies
    ::Gitlab::PolicyStore.list(organization_id: organization.id)
  end

  it 'deletes only the requested policy' do
    request

    expect_graphql_errors_to_be_empty
    expect(mutation_response['errors']).to eq([])
    expect(organization_policies.map(&:id)).to contain_exactly(other_policy.id)
  end

  context 'when the policy is scoped to a namespace' do
    let_it_be(:group) { create(:group, organization: organization) }

    let!(:policy) do
      create_policy(
        organization_id: organization.id,
        namespace_id: group.id,
        name: 'Group-scoped policy',
        trigger_type: 'project.before_settings_update'
      )
    end

    # Through the organization container, the owner manages every policy of
    # the organization, namespace-scoped ones included.
    it 'deletes the policy for an organization owner' do
      request

      expect_graphql_errors_to_be_empty
      expect(mutation_response['errors']).to eq([])
      expect(organization_policies.map(&:id)).to contain_exactly(other_policy.id)
    end
  end

  context 'when the container is a group' do
    include_context 'with policy store group containers'

    let_it_be(:group_maintainer) { create(:user).tap { |user| group.add_maintainer(user) } }

    let(:current_user) { group_owner }
    let(:policy_namespace_id) { group.id }

    let!(:policy) do
      create_policy(
        organization_id: organization.id,
        namespace_id: policy_namespace_id,
        name: 'Group-scoped policy',
        trigger_type: 'project.before_settings_update'
      )
    end

    let(:params) { { group_path: group.full_path, id: policy_id } }

    it 'deletes only the group policy' do
      request

      expect_graphql_errors_to_be_empty
      expect(mutation_response['errors']).to eq([])
      expect(organization_policies.map(&:id)).to contain_exactly(other_policy.id)
    end

    context 'when the policy belongs to another group' do
      let(:policy_namespace_id) { other_group.id }

      # Indistinguishable from a missing id, so probing ids across groups leaks nothing.
      it 'returns the not found message without deleting anything' do
        request

        expect_graphql_errors_to_be_empty
        expect(mutation_response['errors']).to contain_exactly('Policy was not found')
        expect(organization_policies.size).to eq(2)
      end
    end

    context "when a sub-group owner targets the parent group's policy through the sub-group" do
      let_it_be(:subgroup) { create(:group, parent: group, organization: organization) }

      let(:params) { { group_path: subgroup.full_path, id: policy_id } }

      it 'returns the not found message without deleting anything' do
        request

        expect_graphql_errors_to_be_empty
        expect(mutation_response['errors']).to contain_exactly('Policy was not found')
        expect(organization_policies.size).to eq(2)
      end
    end

    context 'when the policy is organization-wide' do
      let(:policy_namespace_id) { nil }

      it 'returns the not found message without deleting anything' do
        request

        expect_graphql_errors_to_be_empty
        expect(mutation_response['errors']).to contain_exactly('Policy was not found')
        expect(organization_policies.size).to eq(2)
      end
    end

    context 'when the user is a group member without the owner role' do
      let(:current_user) { group_maintainer }

      it_behaves_like 'a mutation that returns a top-level access error'

      it 'does not delete the policy' do
        request

        expect(organization_policies.size).to eq(2)
      end
    end

    context 'when the user does not belong to the group' do
      let(:current_user) { create(:user) }

      it_behaves_like 'a mutation that returns a top-level access error'
    end

    context 'when the experiment is not active for the group' do
      before do
        NamespaceSetting.find_by!(namespace_id: group.id).update!(policy_store_experiment_enabled: false)
      end

      it_behaves_like 'a mutation that returns a top-level access error'

      it 'does not delete the policy' do
        request

        expect(organization_policies.size).to eq(2)
      end
    end

    context 'when the group does not exist' do
      let(:params) { super().merge(group_path: 'does/not/exist') }

      it_behaves_like 'a mutation that returns a top-level access error'
    end

    context 'when the organization is supplied as well' do
      let(:params) { super().merge(organization_id: organization.to_global_id.to_s) }

      it_behaves_like 'a mutation that returns top-level errors',
        errors: ['One and only one of [organizationId, groupPath] arguments is required.']
    end
  end

  context 'when neither container argument is supplied' do
    let(:params) { { id: policy_id } }

    it_behaves_like 'a mutation that returns top-level errors',
      errors: ['One and only one of [organizationId, groupPath] arguments is required.']

    it 'does not delete the policy' do
      request

      expect(organization_policies.size).to eq(2)
    end
  end

  context 'when the organization is the default one on GitLab.com',
    :saas_policy_store_default_organization_isolation do
    include_context 'with the default organization as the policy store container'

    let(:organization) { default_organization }
    let(:group_policy) do
      create_policy(
        organization_id: default_organization.id, namespace_id: default_organization_group.id,
        name: 'Group policy', trigger_type: 'project.before_settings_update'
      )
    end

    let(:policy_id) { group_policy.id }

    it "returns the not found message without deleting a tenant's group policy", :aggregate_failures do
      request

      expect_graphql_errors_to_be_empty
      expect(mutation_response['errors']).to contain_exactly('Policy was not found')
      expect(Gitlab::PolicyStore.find(group_policy.id)).to be_present
    end
  end

  context 'when the policy does not exist' do
    let(:policy_id) { non_existing_record_id }

    it 'returns the not found message without deleting anything' do
      request

      expect_graphql_errors_to_be_empty
      expect(mutation_response['errors']).to contain_exactly('Policy was not found')
      expect(organization_policies.size).to eq(2)
    end
  end

  context 'when the policy belongs to another organization' do
    let_it_be(:foreign_organization) { create(:organization) }

    let!(:foreign_policy) do
      create_policy(
        organization_id: foreign_organization.id,
        name: 'Foreign policy',
        trigger_type: 'deployment_requested'
      )
    end

    let(:policy_id) { foreign_policy.id }

    # Cross-organization ids must be indistinguishable from missing ones.
    it 'returns the not found message without deleting anything' do
      request

      expect_graphql_errors_to_be_empty
      expect(mutation_response['errors']).to contain_exactly('Policy was not found')
      expect(::Gitlab::PolicyStore.list(organization_id: foreign_organization.id).size).to eq(1)
    end
  end

  context 'when the service fails for an unmapped reason' do
    before do
      allow_next_instance_of(::Security::SecurityOrchestrationPolicies::PolicyStore::DestroyService) do |service|
        allow(service).to receive(:execute).and_return(
          ServiceResponse.error(message: 'store internals', reason: :unavailable)
        )
      end
    end

    it 'tracks the reason and surfaces a generic error' do
      expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(
        an_instance_of(Mutations::Govern::PolicyDelete::UnmappedReasonError),
        service_message: 'store internals'
      )

      request

      expect(graphql_errors).to contain_exactly(
        a_hash_including('message' => Mutations::Govern::PolicyDelete::UNMAPPED_REASON_MESSAGE)
      )
    end
  end

  context 'when the user is an organization member without the owner role' do
    let(:current_user) { organization_member }

    it_behaves_like 'a mutation that returns a top-level access error'

    it 'does not delete the policy' do
      request

      expect(organization_policies.size).to eq(2)
    end
  end

  context 'when the user does not belong to the organization' do
    let(:current_user) { create(:user) }

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when the feature flag is disabled' do
    before do
      stub_feature_flags(security_policies_v2: false)
    end

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when the experiment is disabled for the instance' do
    before do
      stub_application_setting(policy_store_experiment_enabled: false)
    end

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  context 'when the license does not include security orchestration policies' do
    before do
      stub_licensed_features(security_orchestration_policies: false)
    end

    it_behaves_like 'a mutation that returns a top-level access error'
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', [:delete_govern_policy] do
    let(:user) { organization_owner }
    let(:boundary_object) { :instance }
    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end

  context 'when the container is a group and the token is scoped to it' do
    include_context 'with policy store group containers'

    # The token factory takes the organization from the user, and a granular scope must
    # sit in the same organization as its group, so this owner lives in the group's.
    let_it_be(:group_token_owner) do
      create(:user, organization: organization).tap { |user| group.add_owner(user) }
    end

    let!(:policy) do
      create_policy(
        organization_id: organization.id,
        namespace_id: group.id,
        name: 'Group-scoped policy',
        trigger_type: 'project.before_settings_update'
      )
    end

    let(:params) { super().except(:organization_id).merge(group_path: group.full_path) }

    it_behaves_like 'authorizing granular token permissions for GraphQL', [:delete_govern_policy] do
      let(:user) { group_token_owner }
      let(:boundary_object) { group }
      let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
    end
  end
end
