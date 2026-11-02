# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::SecurityOrchestrationPolicies::PolicyStore::ListService, :policy_store,
  feature_category: :security_policy_management do
  include_context 'with policy store service authorization'
  include_context 'with the policy store experiment active'

  subject(:service) { described_class.new(container: container, current_user: current_user) }

  describe '#execute' do
    let_it_be(:other_organization) { create(:organization) }

    let!(:policy) do
      create_policy(
        organization_id: organization.id,
        name: 'Test policy',
        trigger_type: 'deployment_requested'
      )
    end

    let!(:other_organization_policy) do
      create_policy(
        organization_id: other_organization.id,
        name: 'Other organization policy',
        trigger_type: 'deployment_requested'
      )
    end

    it 'returns only the policies of the given organization', :aggregate_failures do
      result = service.execute

      expect(result).to be_success
      expect(result.payload[:policies]).to contain_exactly(policy)
      expect(result.payload[:policies]).to all(be_a(Gitlab::PolicyStore::Policy))
    end

    it 'defaults page and per_page, returning the pagination metadata', :aggregate_failures do
      result = service.execute

      expect(result.payload[:page]).to eq(1)
      expect(result.payload[:per_page]).to eq(Gitlab::PolicyStore::Ports::PolicyRepository::DEFAULT_PER_PAGE)
      expect(result.payload[:has_next_page]).to be(false)
    end

    context 'with pagination' do
      let!(:other_policy) do
        create_policy(organization_id: organization.id, name: 'Other policy', trigger_type: 'deployment_requested')
      end

      subject(:service) do
        described_class.new(container: container, current_user: current_user, page: 2, per_page: 1)
      end

      it 'returns the requested page and reports whether another one follows', :aggregate_failures do
        result = service.execute

        expect(result.payload[:policies]).to contain_exactly(other_policy)
        expect(result.payload[:page]).to eq(2)
        expect(result.payload[:offset]).to eq(1)
        expect(result.payload[:per_page]).to eq(1)
        expect(result.payload[:has_next_page]).to be(false)
      end

      context 'with an offset instead of a page' do
        subject(:service) do
          described_class.new(container: container, current_user: current_user, offset: 1, per_page: 1)
        end

        # GraphQL cursors carry an offset, so the page translation is skipped.
        it 'skips that many rows and reports no page number', :aggregate_failures do
          result = service.execute

          expect(result.payload[:policies]).to contain_exactly(other_policy)
          expect(result.payload[:offset]).to eq(1)
          expect(result.payload[:page]).to be_nil
          expect(result.payload[:has_next_page]).to be(false)
        end
      end

      context 'with both a page and an offset' do
        it 'refuses the ambiguous request' do
          expect do
            described_class.new(container: container, current_user: current_user, page: 2, offset: 1)
          end.to raise_error(ArgumentError, 'page and offset are mutually exclusive')
        end
      end

      context 'with an offset past the port maximum' do
        subject(:service) do
          described_class.new(
            container: container, current_user: current_user, offset: described_class::MAX_OFFSET + 1, per_page: 1
          )
        end

        it 'clamps the offset', :aggregate_failures do
          result = service.execute

          expect(result.payload[:offset]).to eq(described_class::MAX_OFFSET)
          expect(result.payload[:policies]).to be_empty
        end
      end
    end

    context 'when the organization has no policies' do
      let_it_be(:empty_organization) { create(:organization) }
      let_it_be(:empty_org_owner) { create(:user) }

      subject(:service) { described_class.new(container: empty_organization, current_user: empty_org_owner) }

      before_all do
        create(:organization_user, :owner, organization: empty_organization, user: empty_org_owner)
      end

      before do
        opt_organization_into_policy_store!(empty_organization)
      end

      it 'returns an empty collection', :aggregate_failures do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:policies]).to be_empty
      end
    end

    context 'with namespace_ids' do
      include_context 'with policy store group containers'

      let!(:group_policy) do
        create_policy(
          organization_id: organization.id, namespace_id: group.id, name: 'Group policy',
          trigger_type: 'project.before_settings_update'
        )
      end

      let!(:other_group_policy) do
        create_policy(
          organization_id: organization.id, namespace_id: other_group.id, name: 'Other group policy',
          trigger_type: 'project.before_settings_update'
        )
      end

      let(:namespace_ids) { [group.id] }

      subject(:service) do
        described_class.new(container: container, current_user: current_user, namespace_ids: namespace_ids)
      end

      it "returns the namespaces' and the organization-wide policies" do
        expect(service.execute.payload[:policies]).to contain_exactly(group_policy, policy)
      end

      context 'on GitLab.com', :saas_policy_store_default_organization_isolation do
        it "still returns the organization-wide policies outside the default organization" do
          expect(service.execute.payload[:policies]).to contain_exactly(group_policy, policy)
        end
      end

      context 'with more namespaces than a group and its ancestors' do
        let(:namespace_ids) { (1..(described_class::MAX_NAMESPACE_IDS + 1)).to_a }

        it 'returns an invalid error', :aggregate_failures do
          result = service.execute

          expect(result).to be_error
          expect(result.reason).to eq(:invalid)
        end
      end

      context 'with a namespace repeated past the limit' do
        let(:namespace_ids) { Array.new(described_class::MAX_NAMESPACE_IDS + 1, group.id) }

        it 'counts it once' do
          expect(service.execute.payload[:policies]).to contain_exactly(group_policy, policy)
        end
      end

      context 'when namespace_ids is empty' do
        let(:namespace_ids) { [] }

        it 'returns only the organization-wide policies' do
          expect(service.execute.payload[:policies]).to contain_exactly(policy)
        end
      end

      context 'with a group container' do
        let(:container) { group }

        it 'raises, since a group reads its own hierarchy' do
          expect { service }.to raise_error(ArgumentError, 'namespace_ids applies only to an organization')
        end
      end
    end

    context 'when the organization is the default one' do
      include_context 'with the default organization as the policy store container'

      let!(:organization_wide_policy) do
        create_policy(
          organization_id: default_organization.id, name: 'Organization-wide policy',
          trigger_type: 'deployment_requested'
        )
      end

      let!(:group_policy) do
        create_policy(
          organization_id: default_organization.id, namespace_id: default_organization_group.id,
          name: 'Group policy', trigger_type: 'project.before_settings_update'
        )
      end

      let(:namespace_ids) { [default_organization_group.id] }
      let(:namespace_scoped_service) do
        described_class.new(container: container, current_user: current_user, namespace_ids: namespace_ids)
      end

      let(:group_service) { described_class.new(container: default_organization_group, current_user: current_user) }
      let(:project_service) do
        described_class.new(
          container: default_organization_project, current_user: default_organization_project_developer
        )
      end

      let_it_be(:default_organization_project) do
        create(:project, group: default_organization_group, organization: default_organization)
      end

      let_it_be(:default_organization_project_developer) do
        create(:user, developer_of: default_organization_project)
      end

      context 'on GitLab.com', :saas_policy_store_default_organization_isolation do
        it 'returns only the policies of the namespaces, never the organization-wide ones' do
          expect(namespace_scoped_service.execute.payload[:policies]).to contain_exactly(group_policy)
        end

        context 'when namespace_ids holds a blank entry' do
          let(:namespace_ids) { [nil, default_organization_group.id] }

          it 'returns no organization-wide policies' do
            expect(namespace_scoped_service.execute.payload[:policies]).to contain_exactly(group_policy)
          end
        end

        context 'without namespace_ids' do
          let(:trigger_type) { nil }
          let(:unfiltered_service) do
            described_class.new(container: container, current_user: current_user, trigger_type: trigger_type)
          end

          it 'returns no policies' do
            expect(unfiltered_service.execute.payload[:policies]).to be_empty
          end

          context 'with a trigger that carries no group hierarchy' do
            let(:trigger_type) { 'deployment_requested' }

            it 'returns no policies' do
              expect(unfiltered_service.execute.payload[:policies]).to be_empty
            end
          end

          context 'with a trigger that carries the group hierarchy' do
            let(:trigger_type) { 'project.before_settings_update' }

            it 'refuses the lookup' do
              response = unfiltered_service.execute

              expect(response).to be_error
              expect(response.reason).to eq(:invalid)
              expect(response.message)
                .to eq('namespace_ids is required for this trigger in the default organization')
            end
          end
        end

        context 'when namespace_ids is empty' do
          let(:namespace_ids) { [] }

          it 'returns no policies' do
            expect(namespace_scoped_service.execute.payload[:policies]).to be_empty
          end
        end

        it "returns only the group's policies to a group" do
          expect(group_service.execute.payload[:policies]).to contain_exactly(group_policy)
        end

        it "returns only its group's policies to a project" do
          expect(project_service.execute.payload[:policies]).to contain_exactly(group_policy)
        end
      end

      context 'on a self-managed instance' do
        it "returns the namespaces' and the organization-wide policies" do
          expect(namespace_scoped_service.execute.payload[:policies])
            .to contain_exactly(organization_wide_policy, group_policy)
        end

        it "returns the group's and the organization-wide policies to a group" do
          expect(group_service.execute.payload[:policies]).to contain_exactly(organization_wide_policy, group_policy)
        end

        it "returns its group's and the organization-wide policies to a project" do
          expect(project_service.execute.payload[:policies]).to contain_exactly(organization_wide_policy, group_policy)
        end
      end
    end

    context 'with a trigger_type' do
      let!(:promoted_deployment_policy) do
        create_policy(
          organization_id: organization.id,
          name: 'Promoted deployment policy',
          trigger_type: 'deployment_promoted'
        )
      end

      subject(:service) do
        described_class.new(container: container, current_user: current_user,
          trigger_type: 'deployment_promoted')
      end

      it 'returns only the policies for that trigger', :aggregate_failures do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:policies]).to contain_exactly(promoted_deployment_policy)
      end

      context 'when no policy targets it' do
        subject(:service) do
          described_class.new(container: container, current_user: current_user,
            trigger_type: 'environment_advanced')
        end

        it 'returns an empty collection' do
          expect(service.execute.payload[:policies]).to be_empty
        end
      end
    end

    context 'with lifecycle_state' do
      let!(:disabled_policy) do
        create_policy(
          organization_id: organization.id,
          name: 'Disabled policy',
          trigger_type: 'deployment_requested',
          lifecycle_state: 'disabled'
        )
      end

      it 'defaults to only the active policies' do
        expect(service.execute.payload[:policies]).to contain_exactly(policy)
      end

      context 'when lifecycle_state is disabled' do
        subject(:service) do
          described_class.new(container: organization, current_user: current_user, lifecycle_state: 'disabled')
        end

        it 'returns only the disabled policies' do
          expect(service.execute.payload[:policies]).to contain_exactly(disabled_policy)
        end
      end

      context 'when lifecycle_state is active' do
        subject(:service) do
          described_class.new(container: organization, current_user: current_user, lifecycle_state: 'active')
        end

        it 'matches the default and returns only the active policies' do
          expect(service.execute.payload[:policies]).to contain_exactly(policy)
        end
      end

      context 'when lifecycle_state is all' do
        subject(:service) do
          described_class.new(container: organization, current_user: current_user, lifecycle_state: 'all')
        end

        it 'returns every policy regardless of lifecycle state' do
          expect(service.execute.payload[:policies]).to contain_exactly(policy, disabled_policy)
        end
      end

      context 'when combined with a trigger_type' do
        subject(:service) do
          described_class.new(container: organization, current_user: current_user,
            trigger_type: 'deployment_requested', lifecycle_state: 'disabled')
        end

        it 'returns only the policies matching both filters' do
          expect(service.execute.payload[:policies]).to contain_exactly(disabled_policy)
        end
      end
    end

    context 'with ids' do
      let!(:promoted_deployment_policy) do
        create_policy(
          organization_id: organization.id,
          name: 'Promoted deployment policy',
          trigger_type: 'deployment_promoted'
        )
      end

      subject(:service) do
        described_class.new(container: container, current_user: current_user, ids: [policy.id])
      end

      it 'returns only the policies with those ids', :aggregate_failures do
        result = service.execute

        expect(result).to be_success
        expect(result.payload[:policies]).to contain_exactly(policy)
      end

      context 'when combined with a trigger_type' do
        subject(:service) do
          described_class.new(container: container, current_user: current_user,
            ids: [policy.id, promoted_deployment_policy.id], trigger_type: 'deployment_promoted')
        end

        it 'returns only the policies matching both filters' do
          expect(service.execute.payload[:policies]).to contain_exactly(promoted_deployment_policy)
        end
      end

      context 'when no policy has the ids' do
        subject(:service) do
          described_class.new(container: container, current_user: current_user,
            ids: [non_existing_record_id])
        end

        it 'returns an empty collection', :aggregate_failures do
          result = service.execute

          expect(result).to be_success
          expect(result.payload[:policies]).to be_empty
        end
      end

      context 'with the id of a policy in another organization' do
        subject(:service) do
          described_class.new(container: container, current_user: current_user,
            ids: [other_organization_policy.id])
        end

        it 'does not leak the other organization policy' do
          expect(service.execute.payload[:policies]).to be_empty
        end
      end

      context 'when ids is empty' do
        subject(:service) do
          described_class.new(container: container, current_user: current_user, ids: [])
        end

        it 'returns no policies rather than the unfiltered list' do
          expect(service.execute.payload[:policies]).to be_empty
        end
      end

      context 'when ids is nil' do
        subject(:service) do
          described_class.new(container: container, current_user: current_user, ids: nil)
        end

        it 'returns the unfiltered list' do
          expect(service.execute.payload[:policies]).to contain_exactly(policy, promoted_deployment_policy)
        end
      end

      context 'when an id falls outside the default page size' do
        let!(:padding_policies) do
          Array.new(Gitlab::PolicyStore::Ports::PolicyRepository::DEFAULT_PER_PAGE) do |index|
            create_policy(
              organization_id: organization.id, name: "Padding policy #{index}",
              trigger_type: 'deployment_requested'
            )
          end
        end

        subject(:service) do
          described_class.new(container: container, current_user: current_user,
            ids: [padding_policies.last.id])
        end

        it 'still finds the policy, since ids bypass the page bounds' do
          expect(service.execute.payload[:policies]).to contain_exactly(padding_policies.last)
        end
      end

      context 'when ids exceeds MAX_PER_PAGE' do
        subject(:service) do
          described_class.new(container: container, current_user: current_user,
            ids: Array.new(Gitlab::PolicyStore::Ports::PolicyRepository::MAX_PER_PAGE + 1) { |index| index })
        end

        it 'returns an invalid error rather than running an unbounded query', :aggregate_failures do
          result = service.execute

          expect(result).to be_error
          expect(result.reason).to eq(:invalid)
          expect(result.message).to match(/ids exceeds maximum/)
        end
      end
    end

    it_behaves_like 'a service that requires policy authorization', :read_govern_policy

    it_behaves_like 'a service gated by the policy store experiment', :list
  end

  context 'with a project container' do
    include_context 'with policy store group containers'

    let_it_be(:subgroup) { create(:group, parent: group, organization: organization) }
    let_it_be(:sibling_subgroup) { create(:group, parent: group, organization: organization) }
    let_it_be(:project) { create(:project, group: subgroup, organization: organization) }
    let_it_be(:project_developer) { create(:user, developer_of: project) }
    let_it_be(:project_guest) { create(:user, guest_of: project) }

    let(:container) { project }
    let(:current_user) { project_developer }

    def create_policy_in(namespace)
      create_policy(
        organization_id: organization.id, namespace_id: namespace.id, name: "#{namespace.name} policy",
        trigger_type: 'project.before_settings_update'
      )
    end

    it "returns the organization's and its ancestor groups' policies, but not a sibling's or a descendant's",
      :aggregate_failures do
      organization_policy = create_policy(
        organization_id: organization.id, name: 'Organization policy', trigger_type: 'deployment_requested'
      )
      group_policy = create_policy_in(group)
      subgroup_policy = create_policy_in(subgroup)
      create_policy_in(sibling_subgroup)
      create_policy_in(create(:group, parent: subgroup, organization: organization))

      result = service.execute

      expect(result).to be_success
      expect(result.payload[:policies]).to contain_exactly(organization_policy, group_policy, subgroup_policy)
    end

    it 'raises with namespace_ids, since a project reads its own hierarchy' do
      expect { described_class.new(container: project, current_user: project_developer, namespace_ids: [group.id]) }
        .to raise_error(ArgumentError, 'namespace_ids applies only to an organization')
    end

    context 'when the user is a project guest' do
      let(:current_user) { project_guest }

      it 'names the project in the forbidden error' do
        expect(service.execute.message)
          .to eq('You are not authorized to perform this action on policies in this project')
      end
    end
  end

  context 'with a group container' do
    include_context 'with policy store group containers'

    let(:container) { group }
    let(:current_user) { group_owner }

    let!(:org_wide_policy) do
      create_policy(
        organization_id: organization.id,
        name: 'Organization-wide policy',
        trigger_type: 'deployment_requested'
      )
    end

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

    it "returns the group's own, inherited, and descendant policies, but not a sibling group's", :aggregate_failures do
      subgroup = create(:group, parent: group, organization: organization)
      descendant_policy = create_policy(
        organization_id: organization.id,
        namespace_id: subgroup.id,
        name: 'Subgroup policy',
        trigger_type: 'project.before_settings_update'
      )

      result = service.execute

      expect(result).to be_success
      expect(result.payload[:policies]).to contain_exactly(group_policy, org_wide_policy, descendant_policy)
    end

    it 'is forbidden for an organization member who holds no group ability' do
      result = described_class.new(container: group, current_user: non_owner).execute

      expect(result).to be_error
      expect(result.reason).to eq(:forbidden)
    end

    it 'is allowed for the organization owner, who supervises every group of the organization' do
      result = described_class.new(container: group, current_user: owner).execute

      expect(result).to be_success
    end

    context 'when the group is a subgroup' do
      let_it_be(:subgroup) { create(:group, parent: group, organization: organization) }

      let(:container) { subgroup }

      it "returns its parent group's and the organization-wide policies as inherited", :aggregate_failures do
        subgroup_policy = create_policy(
          organization_id: organization.id,
          namespace_id: subgroup.id,
          name: 'Subgroup policy',
          trigger_type: 'project.before_settings_update'
        )

        result = service.execute

        expect(result).to be_success
        expect(result.payload[:policies]).to contain_exactly(subgroup_policy, group_policy, org_wide_policy)
      end

      it "returns its parent group's and organization-wide policies, but not a sibling sub-group's" do
        sibling_subgroup = create(:group, parent: group, organization: organization)
        create_policy(
          organization_id: organization.id,
          namespace_id: sibling_subgroup.id,
          name: 'Sibling subgroup policy',
          trigger_type: 'project.before_settings_update'
        )

        result = service.execute

        expect(result).to be_success
        expect(result.payload[:policies]).to contain_exactly(group_policy, org_wide_policy)
      end
    end

    context 'when the group has not opted into the experiment' do
      let_it_be(:non_opted_group) do
        create(:group, organization: organization).tap do |g|
          g.add_owner(group_owner)
        end
      end

      let(:container) { non_opted_group }

      it 'reports as forbidden since the experiment gate prevents the ability' do
        result = service.execute

        expect(result).to be_error
        expect(result.reason).to eq(:forbidden)
      end
    end
  end
end
