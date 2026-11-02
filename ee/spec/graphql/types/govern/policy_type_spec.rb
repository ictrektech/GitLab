# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['GovernPolicy'], feature_category: :security_policy_management do
  include GraphqlHelpers

  specify do
    expect(described_class).to have_graphql_fields(
      :id, :organization_id, :namespace_id, :group, :inherited, :name, :description, :version, :trigger_type,
      :rules, :policy_rego, :actions, :policy_scope, :scope_rego, :scope_dimensions, :mode,
      :lifecycle_state, :created_at, :updated_at
    )
  end

  describe '#inherited' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:parent_group) { create(:group, organization: organization) }
    let_it_be(:group) { create(:group, parent: parent_group, organization: organization) }
    let_it_be(:subgroup) { create(:group, parent: group, organization: organization) }

    def inherited_for(namespace_id, container:)
      policy = ::Gitlab::PolicyStore::Policy.new(
        id: 1, organization_id: organization.id, namespace_id: namespace_id, name: 'Gate',
        trigger_type: 'deployment_requested'
      )

      resolve_field(:inherited, policy, ctx: { policy_store_container: container })
    end

    it 'is true for organization-wide and ancestor group policies listed by a group', :aggregate_failures do
      expect(inherited_for(nil, container: group)).to be(true)
      expect(inherited_for(parent_group.id, container: group)).to be(true)
    end

    it "is false for the group's own and descendant groups' policies", :aggregate_failures do
      expect(inherited_for(group.id, container: group)).to be(false)
      expect(inherited_for(subgroup.id, container: group)).to be(false)
    end

    it 'is true for every policy listed by a project' do
      expect(inherited_for(group.id, container: build_stubbed(:project, group: group))).to be(true)
    end

    it 'is false outside a group or project policy list', :aggregate_failures do
      expect(inherited_for(nil, container: organization)).to be(false)
      expect(inherited_for(nil, container: nil)).to be(false)
    end
  end

  describe '#policy_rego' do
    let(:rules) { [{ 'rego' => "package governance\ndeny := true\n" }] }

    let(:policy) do
      ::Gitlab::PolicyStore::Policy.new(
        id: 1, organization_id: 1, name: 'Gate', trigger_type: 'deployment_requested', rules: rules
      )
    end

    subject(:policy_rego) { resolve_field(:policy_rego, policy) }

    it 'merges the compiled rules into one governance module' do
      expect(policy_rego).to eq("package governance\ndeny := true\n")
    end

    context 'when the rules cannot be merged' do
      let(:rules) { [{ 'not_rego' => 'no compiled program' }] }

      it 'tracks the error and resolves to nil rather than failing the read' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception)
          .with(instance_of(::Gitlab::PolicyStore::Error), policy_id: policy.id)

        expect(policy_rego).to be_nil
      end
    end
  end
end
