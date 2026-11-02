# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::PermissionTypes::ArtifactRegistry::RoleAssignment, feature_category: :system_access do
  include GraphqlHelpers

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryRoleAssignmentPermissions') }

  it 'exposes the expected fields' do
    expect(described_class).to have_graphql_fields(:update_role, :remove_member, :leave)
  end

  describe '#leave' do
    let_it_be(:user) { create(:user) }

    let(:identity) { ::Gitlab::Iam::Relationships::V1::Identity.new(local_id: user.id.to_s) }
    let(:role_id) { Authz::ArtifactRegistry::Roles.uuid_for(:artifact_viewer) }
    let(:relationship) do
      ::Gitlab::Iam::Relationships::V1::Relationship.new(
        subject: ::Gitlab::Iam::Relationships::V1::Subject.new(identity: identity),
        role: ::Gitlab::Iam::Relationships::V1::Role.new(id: role_id)
      )
    end

    subject(:leave) { resolve_field(:leave, relationship, current_user: current_user) }

    context 'when the assignment is the current user\'s own' do
      let(:current_user) { user }

      it { is_expected.to be(true) }
    end

    context 'when there is no current user' do
      let(:current_user) { nil }

      it { is_expected.to be(false) }
    end

    context 'when the assignment subject has no identity' do
      let(:current_user) { user }
      let(:identity) { nil }

      it { is_expected.to be(false) }
    end

    context 'when the assignment holds the organization_admin platform role' do
      let(:current_user) { user }
      let(:role_id) { Authz::Organizations::Roles.organization_admin_uuid }

      it { is_expected.to be(false) }
    end
  end

  context 'with an organization that has an Artifact Registry namespace' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:user) { create(:user, organization: organization) }
    let_it_be(:namespace_mapping) { create(:artifact_registry_namespace_mapping, organization: organization) }

    let(:admin_role_id) { Authz::ArtifactRegistry::Roles.uuid_for(:artifact_admin) }

    def relationship(
      identity: ::Gitlab::Iam::Relationships::V1::Identity.new(local_id: user.id.to_s),
      object: ::Gitlab::Iam::Relationships::V1::Object.new(id: namespace_mapping.ar_namespace_id),
      role: ::Gitlab::Iam::Relationships::V1::Role.new(id: admin_role_id))
      ::Gitlab::Iam::Relationships::V1::Relationship.new(
        subject: ::Gitlab::Iam::Relationships::V1::Subject.new(identity: identity), object: object, role: role
      )
    end

    describe '#update_role' do
      before do
        check = instance_double(::Authz::ArtifactRegistry::AccessManagerCheckService, execute: true)
        allow(::Authz::ArtifactRegistry::AccessManagerCheckService).to receive(:new)
          .with(current_user: user, organization: organization).and_return(check)
      end

      where(:missing) { [:identity, :object] }

      with_them do
        it 'is not treated as a namespace admin assignment' do
          expect(::Authz::ArtifactRegistry::LookupRoleAssignmentsService).not_to receive(:new)

          result = resolve_field(:update_role, relationship(missing => nil),
            current_user: user, ctx: { current_organization: organization })

          expect(result).to be(true)
        end
      end

      where(:role) do
        [
          nil,
          ref(:organization_admin_role)
        ]
      end

      with_them do
        let(:organization_admin_role) do
          ::Gitlab::Iam::Relationships::V1::Role.new(id: Authz::Organizations::Roles.organization_admin_uuid)
        end

        it 'is false when the row holds no Artifact Registry role' do
          result = resolve_field(:update_role, relationship(role: role),
            current_user: user, ctx: { current_organization: organization })

          expect(result).to be(false)
        end
      end
    end

    describe '#remove_member' do
      let_it_be(:other_user) { create(:user, organization: organization) }

      let(:other_identity) { ::Gitlab::Iam::Relationships::V1::Identity.new(local_id: other_user.id.to_s) }
      let(:organization_admin_role) do
        ::Gitlab::Iam::Relationships::V1::Role.new(id: Authz::Organizations::Roles.organization_admin_uuid)
      end

      let(:viewer_role) do
        ::Gitlab::Iam::Relationships::V1::Role.new(id: Authz::ArtifactRegistry::Roles.uuid_for(:artifact_viewer))
      end

      before do
        check = instance_double(::Authz::ArtifactRegistry::AccessManagerCheckService, execute: true)
        allow(::Authz::ArtifactRegistry::AccessManagerCheckService).to receive(:new)
          .with(current_user: user, organization: organization).and_return(check)
      end

      where(:role, :expected) do
        [
          [ref(:viewer_role), true],
          [nil, false],
          [ref(:organization_admin_role), false]
        ]
      end

      with_them do
        it 'is true only when another user\'s row holds an Artifact Registry role' do
          result = resolve_field(:remove_member, relationship(identity: other_identity, role: role),
            current_user: user, ctx: { current_organization: organization })

          expect(result).to be(expected)
        end
      end
    end
  end
end
