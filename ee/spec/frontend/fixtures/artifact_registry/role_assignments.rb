# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry repository role assignments (JavaScript fixtures)',
  feature_category: :artifact_registry do
  include GraphqlHelpers
  include JavaScriptFixturesHelpers

  query_path = 'packages_and_registries/artifact_registry/graphql/queries/get_repository_role_assignments.query.graphql'

  let_it_be(:organization) { create(:organization) }
  let_it_be(:user) { create(:user, name: 'Avery Admin', username: 'avery-admin', organization: organization) }
  let_it_be(:viewer) { create(:user, name: 'Vic Viewer', username: 'vic-viewer', organization: organization) }
  let_it_be(:other) { create(:user, name: 'Oli Other', username: 'oli-other', organization: organization) }

  let(:resource_id) { '01937b2e-0000-7000-8000-000000000401' }
  let(:query) { get_graphql_query_as_string(query_path, ee: true) }
  let(:client) { instance_double(Authn::IamService::LookupRelationshipsClient) }

  def assignment(subject:, role_id:)
    ::Gitlab::Iam::Relationships::V1::Relationship.new(
      subject: subject,
      object: ::Gitlab::Iam::Relationships::V1::Object.new(id: resource_id),
      kind: :KIND_ASSIGNMENT,
      role: ::Gitlab::Iam::Relationships::V1::Role.new(id: role_id)
    )
  end

  def identity(member)
    ::Gitlab::Iam::Relationships::V1::Subject.new(
      identity: ::Gitlab::Iam::Relationships::V1::Identity.new(local_id: member.id.to_s)
    )
  end

  before do
    issuer = instance_double(Authn::TokenExchange::TokenIssuer, token: 'ar-token')
    allow(Authn::TokenExchange::TokenIssuer).to receive(:new).and_return(issuer)
    allow(Authn::IamService::LookupRelationshipsClient).to receive(:new).and_return(client)

    allow(client).to receive(:lookup).and_return(
      ::Gitlab::Iam::Lookup::V1::LookupRelationshipsResponse.new(
        relationships: [
          assignment(subject: identity(user), role_id: Authz::ArtifactRegistry::Roles.uuid_for(:artifact_admin)),
          assignment(subject: identity(viewer), role_id: Authz::ArtifactRegistry::Roles.uuid_for(:artifact_viewer)),
          assignment(subject: ::Gitlab::Iam::Relationships::V1::Subject.new,
            role_id: Authz::ArtifactRegistry::Roles.uuid_for(:artifact_contributor)),
          assignment(subject: identity(other), role_id: '01937b2e-0000-7000-8000-00000000ffff')
        ],
        next_page_token: 'next-page'
      )
    )
  end

  describe GraphQL::Query, 'the direct members read of a repository', type: :request do
    it "ee/graphql/#{query_path}.json", :aggregate_failures do
      post_graphql(query, current_user: user, variables: { resourceId: resource_id, first: 100 })

      expect_graphql_errors_to_be_empty
      nodes = graphql_data_at(:artifact_registry_role_assignments, :nodes)

      expect(nodes.pluck('role')).to eq(['ARTIFACT_ADMIN', 'ARTIFACT_VIEWER', 'ARTIFACT_CONTRIBUTOR', nil])
      expect(nodes.map { |node| node.dig('assignee', 'username') })
        .to eq(['avery-admin', 'vic-viewer', nil, 'oli-other'])
      expect(graphql_data_at(:artifact_registry_role_assignments, :page_info))
        .to include('hasNextPage' => true, 'endCursor' => 'next-page')
    end
  end
end
