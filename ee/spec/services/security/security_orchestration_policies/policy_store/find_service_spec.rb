# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecurityOrchestrationPolicies::PolicyStore::FindService, :policy_store,
  feature_category: :security_policy_management do
  include_context 'with policy store service authorization'

  let(:policy) do
    create_policy(
      organization_id: organization.id,
      name: 'Test policy',
      trigger_type: 'deployment_requested'
    )
  end

  subject(:service) do
    described_class.new(container: container, current_user: current_user, policy_id: policy.id)
  end

  include_context 'with the policy store experiment active'

  describe '#execute' do
    it 'returns the policy as a store value object', :aggregate_failures do
      result = service.execute

      expect(result).to be_success
      expect(result.payload[:policy]).to be_a(Gitlab::PolicyStore::Policy)
      expect(result.payload[:policy].id).to eq(policy.id)
    end

    context 'when the policy does not exist' do
      subject(:service) do
        described_class.new(container: container, current_user: current_user, policy_id: non_existing_record_id)
      end

      it 'returns a not found error', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:not_found)
        expect(result.message).to eq('Policy was not found')
      end
    end

    context 'when the policy belongs to another organization' do
      let(:policy) do
        create_policy(
          organization_id: create(:organization).id,
          name: 'Other organization policy',
          trigger_type: 'deployment_requested'
        )
      end

      it 'returns the same not found error as a missing policy', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:not_found)
        expect(result.message).to eq('Policy was not found')
      end
    end

    context 'when the policy belongs to a group within the organization' do
      include_context 'with policy store group containers'

      let(:policy) do
        create_policy(
          organization_id: organization.id,
          namespace_id: group.id,
          name: 'Group policy',
          trigger_type: 'project.before_settings_update'
        )
      end

      it 'returns the policy (organization owner supervises every group)' do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:policy].id).to eq(policy.id)
      end
    end

    it_behaves_like 'a service that requires policy authorization', :read_govern_policy
    it_behaves_like 'a service gated by the policy store experiment', :find
  end

  context 'with a group container' do
    include_context 'with policy store group containers'
    include_context 'with the policy store experiment active'

    let(:container) { group }
    let(:current_user) { group_owner }

    let(:group_policy) do
      create_policy(
        organization_id: organization.id,
        namespace_id: group.id,
        name: 'Group policy',
        trigger_type: 'project.before_settings_update'
      )
    end

    it "returns the group's own policy" do
      result = described_class.new(container: group, current_user: group_owner, policy_id: group_policy.id).execute

      expect(result).to be_success
    end

    it 'returns an organization-wide policy the group inherits' do
      result = described_class.new(container: group, current_user: group_owner, policy_id: policy.id).execute

      expect(result).to be_success
      expect(result.payload[:policy]).to eq(policy)
    end

    it "returns a descendant group's policy" do
      subgroup = create(:group, parent: group, organization: organization)
      descendant_policy = create_policy(
        organization_id: organization.id,
        namespace_id: subgroup.id,
        name: 'Subgroup policy',
        trigger_type: 'project.before_settings_update'
      )

      result = described_class.new(container: group, current_user: group_owner, policy_id: descendant_policy.id)
        .execute

      expect(result).to be_success
    end

    it "reports another group's policy as not found" do
      foreign = create_policy(
        organization_id: organization.id,
        namespace_id: other_group.id,
        name: 'Other group policy',
        trigger_type: 'project.before_settings_update'
      )

      result = described_class.new(container: group, current_user: group_owner, policy_id: foreign.id).execute

      expect(result).to be_error
      expect(result.reason).to eq(:not_found)
    end

    it "reports a sibling group's policy as not found, even to the organization owner" do
      sibling_policy = create_policy(
        organization_id: organization.id,
        namespace_id: group.id,
        name: 'Sibling group policy',
        trigger_type: 'project.before_settings_update'
      )

      result = described_class.new(container: other_group, current_user: owner, policy_id: sibling_policy.id).execute

      expect(result).to be_error
      expect(result.reason).to eq(:not_found)
    end

    context 'with a sub-group container whose experiment gate is open' do
      let_it_be(:subgroup) { create(:group, parent: group, organization: organization) }
      let_it_be(:sibling_subgroup) { create(:group, parent: group, organization: organization) }

      before do
        allow(subgroup).to receive(:policy_store_experiment_active?).and_return(true)
      end

      it "returns its parent group's policy" do
        result = described_class.new(container: subgroup, current_user: group_owner, policy_id: group_policy.id).execute

        expect(result).to be_success
      end

      it "reports a sibling sub-group's policy as not found" do
        sibling_subgroup_policy = create_policy(
          organization_id: organization.id,
          namespace_id: sibling_subgroup.id,
          name: 'Sibling subgroup policy',
          trigger_type: 'project.before_settings_update'
        )

        result = described_class.new(container: subgroup, current_user: group_owner,
          policy_id: sibling_subgroup_policy.id).execute

        expect(result).to be_error
        expect(result.reason).to eq(:not_found)
      end
    end
  end

  context 'with a project container' do
    include_context 'with policy store group containers'
    include_context 'with the policy store experiment active'

    let_it_be(:subgroup) { create(:group, parent: group, organization: organization) }
    let_it_be(:sibling_subgroup) { create(:group, parent: group, organization: organization) }
    let_it_be(:project) { create(:project, group: subgroup, organization: organization) }
    let_it_be(:project_developer) { create(:user, developer_of: project) }

    let(:container) { project }
    let(:current_user) { project_developer }

    def find_from_project(policy)
      described_class.new(container: project, current_user: project_developer, policy_id: policy.id).execute
    end

    def create_policy_in(namespace)
      create_policy(
        organization_id: organization.id,
        namespace_id: namespace.id,
        name: "#{namespace.name} policy",
        trigger_type: 'project.before_settings_update'
      )
    end

    it 'returns an organization-wide policy' do
      expect(find_from_project(policy)).to be_success
    end

    it "returns its group's and its ancestor group's policies", :aggregate_failures do
      expect(find_from_project(create_policy_in(subgroup))).to be_success
      expect(find_from_project(create_policy_in(group))).to be_success
    end

    it "reports a sibling sub-group's policy as not found", :aggregate_failures do
      result = find_from_project(create_policy_in(sibling_subgroup))

      expect(result).to be_error
      expect(result.reason).to eq(:not_found)
    end

    it "reports another group's policy as not found", :aggregate_failures do
      result = find_from_project(create_policy_in(other_group))

      expect(result).to be_error
      expect(result.reason).to eq(:not_found)
    end
  end

  shared_examples 'a default organization container' do
    let(:policy) do
      create_policy(
        organization_id: default_organization.id, name: 'Organization-wide policy',
        trigger_type: 'deployment_requested'
      )
    end

    context 'on GitLab.com', :saas_policy_store_default_organization_isolation do
      it 'does not find an organization-wide policy', :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:not_found)
      end
    end

    context 'on a self-managed instance' do
      it 'finds an organization-wide policy' do
        expect(service.execute).to be_success
      end
    end
  end

  context 'with a group container in the default organization' do
    include_context 'with the default organization as the policy store container'

    let(:container) { default_organization_group }

    it_behaves_like 'a default organization container'
  end

  context 'with a project container in the default organization' do
    include_context 'with the default organization as the policy store container'

    let_it_be(:default_organization_project) do
      create(:project, group: default_organization_group, organization: default_organization)
    end

    let_it_be(:project_developer) { create(:user, developer_of: default_organization_project) }

    let(:container) { default_organization_project }
    let(:current_user) { project_developer }

    it_behaves_like 'a default organization container'
  end

  context 'with the default organization as the container' do
    include_context 'with the default organization as the policy store container'

    let(:policy) do
      create_policy(
        organization_id: default_organization.id, namespace_id: default_organization_group.id,
        name: 'Group policy', trigger_type: 'project.before_settings_update'
      )
    end

    context 'on GitLab.com', :saas_policy_store_default_organization_isolation do
      it "does not find a tenant's group policy", :aggregate_failures do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:not_found)
      end
    end

    context 'on a self-managed instance' do
      it 'finds the group policy' do
        expect(service.execute).to be_success
      end
    end

    it_behaves_like 'a default organization container'
  end

  context 'on GitLab.com in an organization of its own', :saas_policy_store_default_organization_isolation do
    it 'finds an organization-wide policy' do
      expect(service.execute).to be_success
    end
  end
end
