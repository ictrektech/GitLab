# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Artifact Registry role assignments lookup', feature_category: :system_access do
  include GraphqlHelpers

  let_it_be(:current_organization) { create(:organization) }
  let_it_be(:current_user) { create(:user, organization: current_organization) }
  let_it_be(:assignee) { create(:user, organization: current_organization) }
  let_it_be(:granter) { create(:user, organization: current_organization) }

  let(:resource_id) { Gitlab::Utils.uuid_v7 }
  let(:resource_ids) { [resource_id] }

  let(:role_assignment) do
    ::Gitlab::Iam::Relationships::V1::Relationship.new(
      subject: ::Gitlab::Iam::Relationships::V1::Subject.new(
        identity: ::Gitlab::Iam::Relationships::V1::Identity.new(local_id: assignee.id.to_s)
      ),
      object: ::Gitlab::Iam::Relationships::V1::Object.new(id: resource_id),
      kind: :KIND_ASSIGNMENT,
      role: ::Gitlab::Iam::Relationships::V1::Role.new(id: Authz::ArtifactRegistry::Roles.uuid_for(:artifact_admin)),
      granted_by: ::Gitlab::Iam::Relationships::V1::Subject.new(
        identity: ::Gitlab::Iam::Relationships::V1::Identity.new(local_id: granter.id.to_s)
      )
    )
  end

  let(:service_response) do
    ServiceResponse.success(payload: { role_assignments: [role_assignment], next_page_token: 'next' })
  end

  let(:query) do
    graphql_query_for(
      :artifact_registry_role_assignments,
      { resourceIds: resource_ids, first: 10 },
      <<~FIELDS
        nodes { resourceId role assignee { id username } grantedBy { username } }
        pageInfo { hasNextPage endCursor }
      FIELDS
    )
  end

  def assignments
    graphql_data_at(:artifact_registry_role_assignments, :nodes)
  end

  context 'when the user is authenticated and the query is valid' do
    before do
      allow_next_instance_of(::Authz::ArtifactRegistry::LookupRoleAssignmentsService) do |service|
        allow(service).to receive(:execute).and_return(service_response)
      end
    end

    it 'returns the role assignments as a connection', :aggregate_failures do
      post_graphql(query, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(assignments.size).to eq(1)

      node = assignments.first
      expect(node['resourceId']).to eq(resource_id)
      expect(node['role']).to eq('ARTIFACT_ADMIN')
      expect(node['assignee']['id']).to eq(assignee.to_global_id.to_s)
      expect(node['grantedBy']['username']).to eq(granter.username)
      expect(graphql_data_at(:artifact_registry_role_assignments, :pageInfo, :endCursor)).to eq('next')
    end

    it 'reads through the service scoped to the given resources and page size', :aggregate_failures do
      received = nil
      allow(::Authz::ArtifactRegistry::LookupRoleAssignmentsService).to receive(:new) do |**kwargs|
        received = kwargs
        instance_double(::Authz::ArtifactRegistry::LookupRoleAssignmentsService, execute: service_response)
      end

      post_graphql(query, current_user: current_user)

      expect(received[:objects]).to eq([{ resource_id: resource_id, ancestor_ids: [] }])
      expect(received[:page_size]).to eq(10)
      expect(received[:organization]).to eq(current_organization)
    end

    it 'forwards the role filter and pagination cursor to the service', :aggregate_failures do
      received = nil
      allow(::Authz::ArtifactRegistry::LookupRoleAssignmentsService).to receive(:new) do |**kwargs|
        received = kwargs
        instance_double(::Authz::ArtifactRegistry::LookupRoleAssignmentsService, execute: service_response)
      end

      filtered_query = graphql_query_for(
        :artifact_registry_role_assignments,
        { resourceIds: resource_ids, roles: [:ARTIFACT_VIEWER], first: 10, after: 'opaque-cursor' },
        'nodes { resourceId }'
      )

      post_graphql(filtered_query, current_user: current_user)

      expect(received[:roles]).to eq([:artifact_viewer])
      expect(received[:page_after]).to eq('opaque-cursor')
    end

    # The connection renders at most max_page_size nodes while the end cursor
    # comes from IAM, so the fetch must be clamped to the same bound or the
    # rows between them would be silently skipped.
    it 'never fetches more from IAM than the connection can render', :aggregate_failures do
      received = nil
      allow(::Authz::ArtifactRegistry::LookupRoleAssignmentsService).to receive(:new) do |**kwargs|
        received = kwargs
        instance_double(::Authz::ArtifactRegistry::LookupRoleAssignmentsService, execute: service_response)
      end

      max = ::Resolvers::Authz::ArtifactRegistry::RoleAssignmentsResolver::MAX_PAGE_SIZE

      oversized_query = graphql_query_for(
        :artifact_registry_role_assignments,
        { resourceIds: resource_ids, first: max + 50 },
        'nodes { resourceId }'
      )
      post_graphql(oversized_query, current_user: current_user)
      expect(received[:page_size]).to eq(max)

      unbounded_query = graphql_query_for(
        :artifact_registry_role_assignments,
        { resourceIds: resource_ids },
        'nodes { resourceId }'
      )
      post_graphql(unbounded_query, current_user: current_user)
      expect(received[:page_size]).to eq(max)
    end

    it 'returns an argument error for a non-positive first without calling IAM' do
      expect(::Authz::ArtifactRegistry::LookupRoleAssignmentsService).not_to receive(:new)

      negative_query = graphql_query_for(
        :artifact_registry_role_assignments,
        { resourceIds: resource_ids, first: -1 },
        'nodes { resourceId }'
      )
      post_graphql(negative_query, current_user: current_user)

      expect_graphql_errors_to_include('`first` must be a positive integer.')
    end

    context 'when a returned tuple holds the organization_admin platform role' do
      let(:role_assignment) do
        ::Gitlab::Iam::Relationships::V1::Relationship.new(
          subject: ::Gitlab::Iam::Relationships::V1::Subject.new(
            identity: ::Gitlab::Iam::Relationships::V1::Identity.new(local_id: assignee.id.to_s)
          ),
          object: ::Gitlab::Iam::Relationships::V1::Object.new(id: resource_id),
          kind: :KIND_ASSIGNMENT,
          role: ::Gitlab::Iam::Relationships::V1::Role.new(
            id: Authz::Organizations::Roles.organization_admin_uuid
          )
        )
      end

      it 'returns a nil role instead of raising on the undeclared enum value' do
        expect(Gitlab::AppLogger).not_to receive(:warn)

        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(assignments.first['role']).to be_nil
      end
    end

    context 'when a returned tuple holds a role RoleEnum does not declare and does not expect' do
      before do
        allow(Authz::ArtifactRegistry::Roles).to receive(:name_for).and_call_original
        allow(Authz::ArtifactRegistry::Roles).to receive(:name_for)
          .with(role_assignment.role.id).and_return(:artifact_super_admin)
      end

      it 'returns a nil role and logs the drift' do
        expect(Gitlab::AppLogger).to receive(:warn).with(hash_including(role_key: :artifact_super_admin))

        post_graphql(query, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(assignments.first['role']).to be_nil
      end
    end

    context 'when the service returns an error' do
      let(:service_response) { ServiceResponse.error(message: 'The requested resources could not be found.') }

      it 'surfaces a top-level error' do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_present
      end
    end
  end

  context 'when filtering by assignee' do
    let_it_be(:namespace_mapping) do
      create(:artifact_registry_namespace_mapping, organization: current_organization)
    end

    let(:namespace_id) { namespace_mapping.ar_namespace_id }
    let(:other_resource_id) { Gitlab::Utils.uuid_v7 }
    let(:iam_client) { instance_double(Authn::IamService::LookupRelationshipsClient) }
    let(:ar_client) do
      instance_double(ArtifactRegistry::Client,
        namespace: ArtifactRegistry::Namespace.new('id' => namespace_id, 'slug' => 'acme', 'status' => 'active'),
        repositories: ArtifactRegistry::Page.new(nodes: [resource_id, other_resource_id].map do |id|
          ArtifactRegistry::Repository.new('id' => id)
        end))
    end

    let(:assignee_args) { { assigneeIds: [assignee.to_global_id.to_s] } }

    let(:query) do
      graphql_query_for(
        :artifact_registry_role_assignments,
        assignee_args,
        <<~FIELDS
          nodes { resourceId assignee { id } }
          pageInfo { hasNextPage endCursor }
        FIELDS
      )
    end

    def tuple(user, object_id)
      ::Gitlab::Iam::Relationships::V1::Relationship.new(
        subject: ::Gitlab::Iam::Relationships::V1::Subject.new(
          identity: ::Gitlab::Iam::Relationships::V1::Identity.new(local_id: user.id.to_s)
        ),
        object: ::Gitlab::Iam::Relationships::V1::Object.new(id: object_id),
        kind: :KIND_ASSIGNMENT
      )
    end

    before do
      issuer = instance_double(Authn::TokenExchange::TokenIssuer, token: 'ar-token')
      allow(Authn::TokenExchange::TokenIssuer).to receive(:new).and_return(issuer)
      allow(Authn::IamService::LookupRelationshipsClient).to receive(:new).and_return(iam_client)

      # The organization memoizes its client, so stub the accessor rather than
      # Client.new, or one example's double would leak into the next.
      allow(current_organization).to receive(:artifact_registry_client).and_return(ar_client)
    end

    context 'when the caller owns the organization' do
      let_it_be(:owner) { create(:user, :organization_owner, organization: current_organization) }

      before do
        allow(iam_client).to receive(:lookup_resources).and_return(
          ::Gitlab::Iam::Lookup::V1::LookupResourcesResponse.new(
            relationships: [tuple(assignee, resource_id), tuple(assignee, namespace_id)]
          )
        )
      end

      it "returns the assignee's repository assignments", :aggregate_failures do
        post_graphql(query, current_user: owner)

        expect(graphql_errors).to be_nil
        expect(assignments).to contain_exactly(
          { 'resourceId' => resource_id, 'assignee' => { 'id' => assignee.to_global_id.to_s } }
        )
        expect(iam_client).to have_received(:lookup_resources).with(hash_including(subject_id: assignee.id.to_s))
      end
    end

    context 'when the caller administers the Artifact Registry namespace but does not own the organization' do
      before do
        allow(iam_client).to receive(:lookup).and_return(
          ::Gitlab::Iam::Lookup::V1::LookupRelationshipsResponse.new(
            relationships: [tuple(assignee, resource_id), tuple(current_user, other_resource_id)]
          )
        )
      end

      it "returns only the assignee's repository assignments", :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(graphql_errors).to be_nil
        expect(assignments.pluck('resourceId')).to eq([resource_id])
        expect(iam_client).to have_received(:lookup).with(hash_including(
          objects: [
            { id: resource_id, ancestor_ids: [namespace_id] },
            { id: other_resource_id, ancestor_ids: [namespace_id] }
          ]
        ))
      end

      context 'when paging through the result' do
        let(:assignee_args) { { assigneeIds: [assignee.to_global_id.to_s], first: 1 } }

        before do
          allow(iam_client).to receive(:lookup).and_return(
            ::Gitlab::Iam::Lookup::V1::LookupRelationshipsResponse.new(
              relationships: [tuple(assignee, resource_id), tuple(assignee, other_resource_id)]
            )
          )
        end

        it 'returns every assignment across pages', :aggregate_failures do
          post_graphql(query, current_user: current_user)

          first_page = assignments.pluck('resourceId')
          end_cursor = graphql_data_at(:artifact_registry_role_assignments, :pageInfo, :endCursor)
          expect(graphql_data_at(:artifact_registry_role_assignments, :pageInfo, :hasNextPage)).to be(true)

          next_query = graphql_query_for(
            :artifact_registry_role_assignments,
            assignee_args.merge(after: end_cursor),
            'nodes { resourceId } pageInfo { hasNextPage }'
          )
          post_graphql(next_query, current_user: current_user)

          expect(first_page + assignments.pluck('resourceId')).to match_array([resource_id, other_resource_id])
          expect(graphql_data_at(:artifact_registry_role_assignments, :pageInfo, :hasNextPage)).to be(false)
        end

        ['not base64!', Base64.urlsafe_encode64('abc'), Base64.urlsafe_encode64('-1')].each do |cursor|
          it "rejects the cursor #{cursor.inspect}" do
            cursor_query = graphql_query_for(
              :artifact_registry_role_assignments, assignee_args.merge(after: cursor), 'nodes { resourceId }'
            )
            post_graphql(cursor_query, current_user: current_user)

            expect_graphql_errors_to_include('Invalid cursor.')
          end
        end

        it 'rejects an invalid cursor before the lookup' do
          expect(::Authz::ArtifactRegistry::LookupAssigneeRoleAssignmentsService).not_to receive(:new)

          cursor_query = graphql_query_for(
            :artifact_registry_role_assignments, assignee_args.merge(after: 'not base64!'), 'nodes { resourceId }'
          )
          post_graphql(cursor_query, current_user: current_user)

          expect_graphql_errors_to_include('Invalid cursor.')
        end

        it 'returns an empty page for a cursor past the end', :aggregate_failures do
          cursor_query = graphql_query_for(
            :artifact_registry_role_assignments,
            assignee_args.merge(after: Base64.urlsafe_encode64('9999999999999999999')),
            'nodes { resourceId } pageInfo { hasNextPage }'
          )
          post_graphql(cursor_query, current_user: current_user)

          expect(graphql_errors).to be_nil
          expect(assignments).to be_empty
          expect(graphql_data_at(:artifact_registry_role_assignments, :pageInfo, :hasNextPage)).to be(false)
        end
      end
    end

    context 'when the caller cannot manage Artifact Registry access' do
      before do
        allow(iam_client).to receive(:lookup)
          .and_raise(Authn::IamService::LookupRelationshipsClient::RequestError.new('x', reason: :permission_denied))
      end

      it 'returns the not authorized error' do
        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_include('You are not authorized to read these role assignments.')
        expect(assignments).to be_nil
      end
    end

    [-1, 0].each do |first|
      context "when first is #{first}" do
        let(:assignee_args) { { assigneeIds: [assignee.to_global_id.to_s], first: first } }

        it 'returns an argument error without calling IAM' do
          expect(Authn::IamService::LookupRelationshipsClient).not_to receive(:new)

          post_graphql(query, current_user: current_user)

          expect_graphql_errors_to_include('`first` must be a positive integer.')
        end
      end
    end

    context 'when combined with resourceIds' do
      let(:assignee_args) { { assigneeIds: [assignee.to_global_id.to_s], resourceIds: [resource_id] } }

      it 'returns an argument error without calling IAM' do
        expect(Authn::IamService::LookupRelationshipsClient).not_to receive(:new)

        post_graphql(query, current_user: current_user)

        expect_graphql_errors_to_include('`assigneeIds` cannot be combined with `resourceIds`.')
      end
    end
  end

  context 'when the user is not authenticated' do
    it 'returns a top-level error and does not call the service' do
      expect(::Authz::ArtifactRegistry::LookupRoleAssignmentsService).not_to receive(:new)

      post_graphql(query, current_user: nil)

      expect(graphql_errors).to be_present
    end
  end

  describe 'userPermissions' do
    let(:own_assignment) do
      ::Gitlab::Iam::Relationships::V1::Relationship.new(
        subject: ::Gitlab::Iam::Relationships::V1::Subject.new(
          identity: ::Gitlab::Iam::Relationships::V1::Identity.new(local_id: current_user.id.to_s)
        ),
        object: ::Gitlab::Iam::Relationships::V1::Object.new(id: resource_id),
        kind: :KIND_ASSIGNMENT,
        role: ::Gitlab::Iam::Relationships::V1::Role.new(id: Authz::ArtifactRegistry::Roles.uuid_for(:artifact_viewer))
      )
    end

    let(:service_response) do
      ServiceResponse.success(payload: { role_assignments: [role_assignment, own_assignment], next_page_token: '' })
    end

    let(:query) do
      graphql_query_for(
        :artifact_registry_role_assignments,
        { resourceIds: resource_ids, first: 10 },
        'nodes { assignee { id } userPermissions { updateRole removeMember leave } }'
      )
    end

    let(:can_grant_roles) { true }

    def permissions_for(user)
      assignments.find { |node| node.dig('assignee', 'id') == user.to_global_id.to_s }['userPermissions']
    end

    before do
      allow_next_instance_of(::Authz::ArtifactRegistry::LookupRoleAssignmentsService) do |service|
        allow(service).to receive(:execute).and_return(service_response)
      end

      check = instance_double(::Authz::ArtifactRegistry::AccessManagerCheckService, execute: can_grant_roles)
      allow(::Authz::ArtifactRegistry::AccessManagerCheckService).to receive(:new)
        .with(current_user: current_user, organization: current_organization).and_return(check)
    end

    context 'when the user can grant Artifact Registry roles' do
      it 'allows changing and removing other members, and leaving only on their own row', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(permissions_for(assignee)).to eq('updateRole' => true, 'removeMember' => true, 'leave' => false)
        expect(permissions_for(current_user)).to eq('updateRole' => true, 'removeMember' => false, 'leave' => true)
      end
    end

    context 'when the user cannot grant Artifact Registry roles' do
      let(:can_grant_roles) { false }

      it 'allows only leaving their own row', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(permissions_for(assignee)).to eq('updateRole' => false, 'removeMember' => false, 'leave' => false)
        expect(permissions_for(current_user)).to eq('updateRole' => false, 'removeMember' => false, 'leave' => true)
      end
    end

    context 'when the user is an Artifact Admin on the registry namespace but not an owner' do
      let_it_be(:namespace_mapping) do
        create(:artifact_registry_namespace_mapping, organization: current_organization)
      end

      let(:lookup_client) { instance_double(Authn::IamService::LookupRelationshipsClient) }

      before do
        allow(::Authz::ArtifactRegistry::AccessManagerCheckService).to receive(:new).and_call_original
        allow(Authn::IamDataAccessService).to receive(:configured?).and_return(true)
        allow(Authn::TokenExchange::TokenIssuer).to receive(:new)
          .and_return(instance_double(Authn::TokenExchange::TokenIssuer, token: 'ar-token'))
        allow(Authn::IamService::LookupRelationshipsClient).to receive(:new).and_return(lookup_client)
        allow(lookup_client).to receive(:read).and_return(
          ::Gitlab::Iam::Lookup::V1::ReadRelationshipsResponse.new(relationships: [
            ::Gitlab::Iam::Relationships::V1::Relationship.new(
              role: ::Gitlab::Iam::Relationships::V1::Role.new(id: Authz::ArtifactRegistry::Roles.uuid_for(:artifact_admin))
            )
          ])
        )
      end

      it 'allows changing and removing other members with one IAM call', :aggregate_failures do
        post_graphql(query, current_user: current_user)

        expect(permissions_for(assignee)).to eq('updateRole' => true, 'removeMember' => true, 'leave' => false)
        expect(lookup_client).to have_received(:read).once
      end
    end

    context 'when the assignments are on the Artifact Registry namespace' do
      let_it_be(:namespace_mapping) do
        create(:artifact_registry_namespace_mapping, organization: current_organization)
      end

      let(:resource_id) { namespace_mapping.ar_namespace_id }
      let(:role_assignment) { assignment_for(assignee, :artifact_admin) }
      let(:own_assignment) { assignment_for(current_user, :artifact_viewer) }
      let(:namespace_admins) { [role_assignment] }
      let(:admin_lookup_response) do
        ServiceResponse.success(payload: { role_assignments: namespace_admins, next_page_token: '' })
      end

      let(:admin_lookups) { [] }

      def assignment_for(user, role)
        ::Gitlab::Iam::Relationships::V1::Relationship.new(
          subject: ::Gitlab::Iam::Relationships::V1::Subject.new(
            identity: ::Gitlab::Iam::Relationships::V1::Identity.new(local_id: user.id.to_s)
          ),
          object: ::Gitlab::Iam::Relationships::V1::Object.new(id: resource_id),
          kind: :KIND_ASSIGNMENT,
          role: ::Gitlab::Iam::Relationships::V1::Role.new(id: Authz::ArtifactRegistry::Roles.uuid_for(role))
        )
      end

      before do
        allow(::Authz::ArtifactRegistry::LookupRoleAssignmentsService).to receive(:new) do |**kwargs|
          admin_lookup = kwargs[:roles] == [:artifact_admin]
          admin_lookups << kwargs if admin_lookup

          instance_double(::Authz::ArtifactRegistry::LookupRoleAssignmentsService,
            execute: admin_lookup ? admin_lookup_response : service_response)
        end
      end

      context 'when another member is the last Artifact Admin' do
        it 'blocks changing or removing that member', :aggregate_failures do
          post_graphql(query, current_user: current_user)

          expect(permissions_for(assignee)).to eq('updateRole' => false, 'removeMember' => false, 'leave' => false)
          expect(permissions_for(current_user)).to eq('updateRole' => true, 'removeMember' => false, 'leave' => true)
        end
      end

      context 'when the current user is the last Artifact Admin' do
        let(:role_assignment) { assignment_for(assignee, :artifact_viewer) }
        let(:own_assignment) { assignment_for(current_user, :artifact_admin) }
        let(:namespace_admins) { [own_assignment] }

        it 'blocks changing their own role and leaving', :aggregate_failures do
          post_graphql(query, current_user: current_user)

          expect(permissions_for(current_user)).to eq('updateRole' => false, 'removeMember' => false, 'leave' => false)
          expect(permissions_for(assignee)).to eq('updateRole' => true, 'removeMember' => true, 'leave' => false)
        end
      end

      context 'when there are two Artifact Admins' do
        let(:own_assignment) { assignment_for(current_user, :artifact_admin) }
        let(:namespace_admins) { [role_assignment, own_assignment] }

        it 'allows every action and looks up the admins once', :aggregate_failures do
          post_graphql(query, current_user: current_user)

          expect(permissions_for(assignee)).to eq('updateRole' => true, 'removeMember' => true, 'leave' => false)
          expect(permissions_for(current_user)).to eq('updateRole' => true, 'removeMember' => false, 'leave' => true)
          expect(admin_lookups.size).to eq(1)
        end
      end

      context 'when the other admin is blocked' do
        let(:blocked_admin) { create(:user, :blocked, organization: current_organization) }
        let(:own_assignment) { assignment_for(current_user, :artifact_admin) }
        let(:namespace_admins) { [assignment_for(blocked_admin, :artifact_admin), own_assignment] }

        it 'treats the current user as the last Artifact Admin' do
          post_graphql(query, current_user: current_user)

          expect(permissions_for(current_user)).to eq('updateRole' => false, 'removeMember' => false, 'leave' => false)
        end
      end

      context 'when the admin lookup has more than one page' do
        let(:admin_lookup_response) do
          ServiceResponse.success(payload: { role_assignments: namespace_admins, next_page_token: 'next' })
        end

        it 'allows changing or removing the admin' do
          post_graphql(query, current_user: current_user)

          expect(permissions_for(assignee)).to eq('updateRole' => true, 'removeMember' => true, 'leave' => false)
        end
      end

      context 'when the other admin is not an organization member' do
        let(:outside_admin) { create(:user) }
        let(:namespace_admins) { [role_assignment, assignment_for(outside_admin, :artifact_admin)] }

        it 'treats the member as the last Artifact Admin' do
          post_graphql(query, current_user: current_user)

          expect(permissions_for(assignee)).to eq('updateRole' => false, 'removeMember' => false, 'leave' => false)
        end
      end

      context 'when the only admin is blocked' do
        let(:blocked_admin) { create(:user, :blocked, organization: current_organization) }
        let(:role_assignment) { assignment_for(blocked_admin, :artifact_admin) }

        it 'allows changing or removing the blocked admin' do
          post_graphql(query, current_user: current_user)

          expect(permissions_for(blocked_admin)).to eq('updateRole' => true, 'removeMember' => true, 'leave' => false)
        end
      end

      context 'when the admin assignment is on a repository' do
        let(:resource_id) { Gitlab::Utils.uuid_v7 }

        it 'allows changing or removing the admin without looking up the admins', :aggregate_failures do
          post_graphql(query, current_user: current_user)

          expect(permissions_for(assignee)).to eq('updateRole' => true, 'removeMember' => true, 'leave' => false)
          expect(admin_lookups).to be_empty
        end
      end

      context 'with more namespace admin rows on the page' do
        let(:page_assignments) { [] }
        let(:namespace_admins) { page_assignments }
        let(:service_response) do
          ServiceResponse.success(payload: { role_assignments: page_assignments, next_page_token: '' })
        end

        def show_admins(count)
          admins = create_list(:user, count, organization: current_organization)
          page_assignments.replace(admins.map { |admin| assignment_for(admin, :artifact_admin) })
        end

        it 'does not add database queries per row', :aggregate_failures do
          show_admins(2)
          post_graphql(query, current_user: current_user)
          control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
            post_graphql(query, current_user: current_user)
          end

          show_admins(4)

          expect { post_graphql(query, current_user: current_user) }.not_to exceed_all_query_limit(control)
          expect(assignments.size).to eq(4)
          expect(admin_lookups.size).to eq(3)
        end
      end

      context 'when the admin lookup fails' do
        let(:admin_lookup_response) { ServiceResponse.error(message: 'unavailable') }

        it 'blocks changing or removing the admin' do
          post_graphql(query, current_user: current_user)

          expect(permissions_for(assignee)).to eq('updateRole' => false, 'removeMember' => false, 'leave' => false)
        end
      end
    end
  end
end
