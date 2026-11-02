# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Authz::ArtifactRegistry::RoleAssignmentType, feature_category: :system_access do
  include GraphqlHelpers

  specify { expect(described_class.graphql_name).to eq('ArtifactRegistryRoleAssignment') }

  it 'exposes the expected fields' do
    expect(described_class).to have_graphql_fields(
      :resource_id, :role, :assignee, :granted_by, :created_at, :user_permissions
    )
  end

  describe '#granted_by' do
    let_it_be(:granter) { create(:user) }
    let_it_be(:other_granter) { create(:user) }

    def tuple(granted_by: nil)
      ::Gitlab::Iam::Relationships::V1::Relationship.new(granted_by: granted_by)
    end

    def granter_subject(local_id)
      ::Gitlab::Iam::Relationships::V1::Subject.new(
        identity: ::Gitlab::Iam::Relationships::V1::Identity.new(local_id: local_id)
      )
    end

    def resolve_granted_by(relationship)
      resolve_field(:granted_by, relationship, current_user: granter)
    end

    it 'resolves the user who granted the role' do
      expect(batch_sync { resolve_granted_by(tuple(granted_by: granter_subject(granter.id.to_s))) }).to eq(granter)
    end

    it 'returns nil when granted_by is unset' do
      expect(resolve_granted_by(tuple)).to be_nil
    end

    it 'returns nil when granted_by is a principal' do
      principal = ::Gitlab::Iam::Relationships::V1::Subject.new(
        principal: ::Gitlab::Iam::Relationships::V1::Principal.new
      )

      expect(resolve_granted_by(tuple(granted_by: principal))).to be_nil
    end

    it 'returns nil when the local_id matches no user' do
      expect(batch_sync { resolve_granted_by(tuple(granted_by: granter_subject(non_existing_record_id.to_s))) })
        .to be_nil
    end

    it 'batches the user lookups' do
      relationships = [granter, other_granter].map { |user| tuple(granted_by: granter_subject(user.id.to_s)) }

      result = batch_sync(max_queries: 1) { relationships.map { |relationship| resolve_granted_by(relationship) } }

      expect(result).to eq([granter, other_granter])
    end
  end
end
