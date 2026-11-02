# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::ArtifactRegistry::RevokeRoleAssignmentsService, feature_category: :system_access do
  include ExclusiveLeaseHelpers

  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:user, organization: organization) }
  let_it_be(:assignee_a) { create(:user, organization: organization) }
  let_it_be(:assignee_b) { create(:user, organization: organization) }

  let(:resource_id) { Gitlab::Utils.uuid_v7 }
  let(:other_resource_id) { Gitlab::Utils.uuid_v7 }
  let(:token) { 'ar-token' }
  let(:client) { instance_double(Authn::IamService::UpdateRelationshipsClient) }
  let(:ar_client) { instance_double(ArtifactRegistry::Client) }
  # The last-admin guard reads the namespace admins through IAM. By default an
  # unrelated user is an admin, so no change here removes the last one.
  let(:lookup_client) { instance_double(Authn::IamService::LookupRelationshipsClient) }
  let(:revocations) do
    [
      { assignee: assignee_a, resource_id: resource_id },
      { assignee: assignee_b, resource_id: other_resource_id }
    ]
  end

  subject(:execute) do
    described_class.new(current_user: current_user, organization: organization, revocations: revocations).execute
  end

  def admins_response(user_ids, next_page_token: '')
    ::Gitlab::Iam::Lookup::V1::LookupRelationshipsResponse.new(
      relationships: user_ids.map do |user_id|
        ::Gitlab::Iam::Relationships::V1::Relationship.new(
          subject: ::Gitlab::Iam::Relationships::V1::Subject.new(
            identity: ::Gitlab::Iam::Relationships::V1::Identity.new(local_id: user_id.to_s)
          )
        )
      end,
      next_page_token: next_page_token
    )
  end

  before do
    issuer = instance_double(Authn::TokenExchange::TokenIssuer, token: token)
    allow(Authn::TokenExchange::TokenIssuer).to receive(:new).and_return(issuer)

    allow(Authn::IamService::UpdateRelationshipsClient).to receive(:new).and_return(client)
    allow(client).to receive(:revoke_roles).and_return(::Gitlab::Iam::Update::V1::DeleteRelationshipsResponse.new)

    allow(ArtifactRegistry::Client).to receive(:new).and_return(ar_client)
    allow(ar_client).to receive(:verify_repositories).and_return([])

    allow(Authn::IamService::LookupRelationshipsClient).to receive(:new).and_return(lookup_client)
    allow(lookup_client).to receive(:lookup).and_return(admins_response([non_existing_record_id]))
  end

  context 'when all revocations are valid' do
    it 'deletes every assignment in a single call and returns success', :aggregate_failures do
      expect(client).to receive(:revoke_roles) do |keys, organization_uuid:, token:|
        expect(token).to eq('ar-token')
        expect(organization_uuid).to eq(organization.uuid)
        expect(keys).to match_array([
          { assignee_id: assignee_a.id, resource_id: resource_id },
          { assignee_id: assignee_b.id, resource_id: other_resource_id }
        ])

        ::Gitlab::Iam::Update::V1::DeleteRelationshipsResponse.new
      end

      result = execute
      expect(result).to be_success
      expect(result.payload[:revoked_role_count]).to eq(2)
    end
  end

  # IAM lets callers delete keys where they are the subject without an admin
  # grant, so leaving needs no extra check in Rails.
  context 'when the caller revokes their own role' do
    let(:revocations) { [{ assignee: current_user, resource_id: resource_id }] }

    it "deletes the caller's own assignment", :aggregate_failures do
      expect(client).to receive(:revoke_roles) do |keys, **_kwargs|
        expect(keys).to contain_exactly({ assignee_id: current_user.id, resource_id: resource_id })

        ::Gitlab::Iam::Update::V1::DeleteRelationshipsResponse.new
      end

      result = execute
      expect(result).to be_success
      expect(result.payload[:revoked_role_count]).to eq(1)
    end
  end

  # IAM only accepts canonical lowercase ids, so the service normalizes case
  # instead of rejecting an uppercase id.
  context 'when a resource_id is an uppercase UUIDv7' do
    let(:revocations) do
      [{ assignee: assignee_a, resource_id: resource_id.upcase }]
    end

    it 'downcases the id before deleting' do
      expect(client).to receive(:revoke_roles) do |keys, **_kwargs|
        expect(keys).to match_array([{ assignee_id: assignee_a.id, resource_id: resource_id }])

        ::Gitlab::Iam::Update::V1::DeleteRelationshipsResponse.new
      end

      expect(execute).to be_success
    end
  end

  # Deleting the same key twice is harmless, so duplicates collapse instead of
  # erroring the way the grant path must, and the count reports distinct
  # assignments.
  context 'when the same revocation is listed twice' do
    let(:revocations) do
      [
        { assignee: assignee_a, resource_id: resource_id },
        { assignee: assignee_a, resource_id: resource_id }
      ]
    end

    it 'sends one key and counts one revocation', :aggregate_failures do
      expect(client).to receive(:revoke_roles) do |keys, **_kwargs|
        expect(keys).to eq([{ assignee_id: assignee_a.id, resource_id: resource_id }])

        ::Gitlab::Iam::Update::V1::DeleteRelationshipsResponse.new
      end

      result = execute
      expect(result).to be_success
      expect(result.payload[:revoked_role_count]).to eq(1)
    end
  end

  context 'when there is no current user' do
    let(:current_user) { nil }

    it 'returns an error and does not call IAM', :aggregate_failures do
      expect(client).not_to receive(:revoke_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('signed in')
    end
  end

  context 'when the organization could not be determined' do
    let(:organization) { nil }

    it 'returns an error and does not call IAM', :aggregate_failures do
      expect(client).not_to receive(:revoke_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('Organization')
    end
  end

  # Its own organization, because the rest of this file runs with none and the
  # shared organization caches the association once it is loaded.
  describe 'the parent named on each object' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:namespace_mapping) { create(:artifact_registry_namespace_mapping, organization: organization) }
    let_it_be(:current_user) { create(:user, organization: organization) }
    let_it_be(:assignee_a) { create(:user, organization: organization) }
    let_it_be(:assignee_b) { create(:user, organization: organization) }

    it 'names the namespace for a repository, so a namespace admin is accepted' do
      expect(client).to receive(:revoke_roles) do |keys, **_kwargs|
        expect(keys).to all(include(parent_id: namespace_mapping.ar_namespace_id))
      end

      expect(execute).to be_success
    end

    it 'asks AR about the repositories once, and not about the namespace' do
      expect(ar_client).to receive(:verify_repositories).once.with(
        namespace_id: namespace_mapping.ar_namespace_id,
        repository_ids: match_array([resource_id, other_resource_id])
      ).and_return([])

      expect(execute).to be_success
    end

    # The gap this closes. IAM has no organization binding on Object.id, so a
    # named parent it cannot check would let an admin on one namespace revoke
    # roles on another organization's repository.
    context 'when AR says the repository is not in this namespace' do
      it 'names no parent, so IAM still requires a role on the repository' do
        allow(ar_client).to receive(:verify_repositories).and_return([resource_id])

        expect(client).to receive(:revoke_roles) do |keys, **_kwargs|
          expect(keys).to contain_exactly(
            { assignee_id: assignee_a.id, resource_id: resource_id },
            { assignee_id: assignee_b.id, resource_id: other_resource_id,
              parent_id: namespace_mapping.ar_namespace_id }
          )
        end

        expect(execute).to be_success
      end
    end

    # Revocation has to keep working while someone is offboarded, so an outage
    # drops the parent instead of refusing. Grant fails closed here because
    # granting an unverified resource creates access.
    context 'when AR cannot answer' do
      where(:reason, :error) do
        [
          ['an outage', ArtifactRegistry::Client::UnavailableError.new('down', status: 503)],
          ['a missing credential', ArtifactRegistry::Client::AuthorizationError.new('no credential')],
          ['a bad batch', ArgumentError.new('repository_ids must carry between 1 and 1000 entries')]
        ]
      end

      with_them do
        it 'logs it, names no parent, and still revokes' do
          allow(ar_client).to receive(:verify_repositories).and_raise(error)
          expect(Gitlab::ErrorTracking).to receive(:track_exception).with(error)

          expect(client).to receive(:revoke_roles) do |keys, **_kwargs|
            expect(keys.map { |key| key.key?(:parent_id) }).to all(be false)
          end

          expect(execute).to be_success
        end
      end
    end

    context 'when the revocation targets the namespace itself' do
      let(:revocations) do
        [{ assignee: assignee_a, resource_id: namespace_mapping.ar_namespace_id }]
      end

      it 'names no parent' do
        expect(client).to receive(:revoke_roles) do |keys, **_kwargs|
          expect(keys.first[:parent_id]).to be_nil
        end

        expect(execute).to be_success
      end
    end
  end

  context 'when the organization has no Artifact Registry namespace' do
    it 'names no parent and still revokes' do
      expect(client).to receive(:revoke_roles) do |keys, **_kwargs|
        expect(keys.first[:parent_id]).to be_nil
      end

      expect(execute).to be_success
    end
  end

  context 'when the caller is not a member of the organization' do
    let_it_be(:organization) { create(:organization) }

    it 'returns an error and does not call IAM', :aggregate_failures do
      expect(client).not_to receive(:revoke_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('another organization')
    end
  end

  # Revoke applies no organization rule to the assignee, unlike grant.
  # Requiring membership would make a role unrevokable the moment someone is
  # removed from the organization, which is exactly when it has to go
  # (gitlab-org/gitlab#610042).
  context 'when the caller is a member of the organization but not owned by it' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:current_user) { create(:user) }
    let_it_be(:assignee_a) { create(:user, organization: current_user.organization) }

    let(:revocations) do
      [{ assignee: assignee_a, resource_id: resource_id }]
    end

    before do
      create(:organization_user, organization: organization, user: current_user)
    end

    it 'revokes even though the assignee is not a member of that organization', :aggregate_failures do
      expect(current_user.organization_id).not_to eq(organization.id)
      expect(Organizations::OrganizationUser.member_ids_among(organization, [assignee_a.id])).to be_empty
      expect(client).to receive(:revoke_roles)

      expect(execute).to be_success
    end
  end

  context 'when no revocations are given' do
    let(:revocations) { [] }

    it 'returns an error and does not call IAM', :aggregate_failures do
      expect(client).not_to receive(:revoke_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('At least one')
    end
  end

  context 'when one assignee is owned by a different organization' do
    let_it_be(:other_org_user) { create(:user, organization: create(:organization)) }

    let(:revocations) do
      [
        { assignee: assignee_a, resource_id: resource_id },
        { assignee: other_org_user, resource_id: resource_id }
      ]
    end

    # Which organization owns the account says nothing about who may be
    # revoked. IAM keys the subject by organization plus user, so a key naming
    # someone with no identity in this one matches no tuple.
    it 'sends both keys and lets IAM answer for a subject it does not know' do
      expect(client).to receive(:revoke_roles) do |keys, **_kwargs|
        expect(keys).to contain_exactly(
          { assignee_id: assignee_a.id, resource_id: resource_id },
          { assignee_id: other_org_user.id, resource_id: resource_id }
        )
      end

      expect(execute).to be_success
    end
  end

  context 'when one assignee is nil (user not found)' do
    let(:revocations) do
      [{ assignee: nil, resource_id: resource_id }]
    end

    it 'deletes nothing and returns the generic not-found error', :aggregate_failures do
      expect(client).not_to receive(:revoke_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('could not be found')
    end
  end

  context 'when one resource_id is not a valid UUID' do
    let(:revocations) do
      [{ assignee: assignee_a, resource_id: 'not-a-uuid' }]
    end

    it 'deletes nothing and returns the bare message without a position prefix', :aggregate_failures do
      expect(client).not_to receive(:revoke_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('UUIDv7')
      expect(result.message).not_to include('Revocation ')
    end
  end

  context 'when one resource_id is a UUIDv4' do
    let(:revocations) do
      [{ assignee: assignee_a, resource_id: 'c7a3b3f4-9d3a-4e46-9c3e-3a1f0b2d4e5f' }]
    end

    it 'deletes nothing and returns an error', :aggregate_failures do
      expect(client).not_to receive(:revoke_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('UUIDv7')
    end
  end

  context 'when a revocation targets the organization itself' do
    let(:revocations) { [{ assignee: assignee_a, resource_id: organization.uuid }] }

    it 'deletes nothing and returns an error', :aggregate_failures do
      expect(client).not_to receive(:revoke_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('Organization roles cannot be changed.')
    end
  end

  context 'when several revocations are invalid for different reasons' do
    let(:revocations) do
      [
        { assignee: assignee_a, resource_id: 'not-a-uuid' },
        { assignee: nil, resource_id: resource_id }
      ]
    end

    it 'reports every validation error, identified by position', :aggregate_failures do
      expect(client).not_to receive(:revoke_roles)

      result = execute
      expect(result).to be_error
      expect(result.message).to include('Revocation 1 on resource not-a-uuid', 'UUIDv7')
      expect(result.message).to include("Revocation 2 on resource #{resource_id}", 'could not be found')
    end
  end

  context 'when the IAM delete fails' do
    {
      not_found: 'could not be found',
      permission_denied: 'not authorized to revoke',
      unauthenticated: 'Could not authenticate',
      invalid_request: 'revocation request was invalid',
      unavailable: 'service is unavailable',
      timeout: 'did not respond in time',
      unknown: 'could not be completed'
    }.each do |reason, message_fragment|
      it "translates the #{reason} reason into a user-facing message and exposes it as reason", :aggregate_failures do
        allow(client).to receive(:revoke_roles).and_raise(
          Authn::IamService::UpdateRelationshipsClient::RequestError.new('diagnostic', reason: reason)
        )

        result = execute
        expect(result).to be_error
        expect(result.message).to include(message_fragment)
        expect(result.reason).to eq(reason)
      end
    end
  end

  describe 'the last Artifact Admin guard' do
    let_it_be(:namespace_mapping) { create(:artifact_registry_namespace_mapping, organization: organization) }
    let(:namespace_id) { namespace_mapping.ar_namespace_id }
    let(:revocations) { [{ assignee: assignee_a, resource_id: namespace_id }] }

    # The mapping is cached on the shared organization, so clear it for the
    # examples outside this group.
    after do
      organization.reset
    end

    shared_examples 'blocking the change' do
      it 'refuses without revoking anything', :aggregate_failures do
        expect(client).not_to receive(:revoke_roles)

        result = execute
        expect(result).to be_error
        expect(result.reason).to eq(:last_admin)
        expect(result.message).to eq('You cannot remove or demote the last Artifact Admin.')
      end
    end

    shared_examples 'allowing the change' do
      it 'revokes' do
        expect(client).to receive(:revoke_roles)

        expect(execute).to be_success
      end
    end

    context 'when the assignee is the only Artifact Admin' do
      before do
        allow(lookup_client).to receive(:lookup).and_return(admins_response([assignee_a.id]))
      end

      it_behaves_like 'blocking the change'

      it 'reads only the Artifact Admins on the namespace' do
        expect(lookup_client).to receive(:lookup).with(hash_including(
          objects: [{ id: namespace_id, ancestor_ids: [] }],
          role_ids: [Authz::ArtifactRegistry::Roles.uuid_for(:artifact_admin)]
        )).and_return(admins_response([assignee_a.id]))

        execute
      end
    end

    context 'when the caller leaves as the only Artifact Admin' do
      let(:revocations) { [{ assignee: current_user, resource_id: namespace_id }] }

      before do
        allow(lookup_client).to receive(:lookup).and_return(admins_response([current_user.id]))
      end

      it_behaves_like 'blocking the change'
    end

    context 'when a bulk revoke removes every Artifact Admin' do
      let(:revocations) do
        [
          { assignee: assignee_a, resource_id: namespace_id },
          { assignee: assignee_b, resource_id: namespace_id }
        ]
      end

      before do
        allow(lookup_client).to receive(:lookup).and_return(admins_response([assignee_a.id, assignee_b.id]))
      end

      it_behaves_like 'blocking the change'
    end

    context 'when another Artifact Admin remains' do
      before do
        allow(lookup_client).to receive(:lookup).and_return(admins_response([assignee_a.id, assignee_b.id]))
      end

      it_behaves_like 'allowing the change'
    end

    context 'when the admins span several pages' do
      before do
        allow(lookup_client).to receive(:lookup)
          .and_return(admins_response([assignee_a.id], next_page_token: 'page-2'), admins_response([assignee_b.id]))
      end

      it_behaves_like 'allowing the change'
    end

    context 'when there are too many Artifact Admins to page through' do
      before do
        allow(lookup_client).to receive(:lookup).and_return(admins_response([assignee_a.id], next_page_token: 'more'))
      end

      it_behaves_like 'allowing the change'

      it 'stops after the page limit' do
        execute

        expect(lookup_client).to have_received(:lookup)
          .exactly(Authz::ArtifactRegistry::NamespaceAdminIdsService::MAX_PAGES).times
      end
    end

    context 'when an Artifact Admin assignment has no user identity' do
      before do
        response = admins_response([assignee_a.id])
        response.relationships << ::Gitlab::Iam::Relationships::V1::Relationship.new(
          subject: ::Gitlab::Iam::Relationships::V1::Subject.new
        )
        allow(lookup_client).to receive(:lookup).and_return(response)
      end

      it_behaves_like 'blocking the change'
    end

    context 'when the only other Artifact Admin left the organization' do
      let_it_be(:former_member) { create(:user) }

      before do
        allow(lookup_client).to receive(:lookup).and_return(admins_response([assignee_a.id, former_member.id]))
      end

      it_behaves_like 'blocking the change'
    end

    context 'when the only other Artifact Admin is blocked' do
      let_it_be(:blocked_admin) { create(:user, :blocked, organization: organization) }

      before do
        allow(lookup_client).to receive(:lookup).and_return(admins_response([assignee_a.id, blocked_admin.id]))
      end

      it_behaves_like 'blocking the change'
    end

    context 'when revoking the last Artifact Admin after they left the organization' do
      let_it_be(:former_member) { create(:user) }

      let(:revocations) { [{ assignee: former_member, resource_id: namespace_id }] }

      before do
        allow(lookup_client).to receive(:lookup).and_return(admins_response([former_member.id]))
      end

      it_behaves_like 'allowing the change'
    end

    context 'when the assignee is not an Artifact Admin' do
      before do
        allow(lookup_client).to receive(:lookup).and_return(admins_response([assignee_b.id]))
      end

      it_behaves_like 'allowing the change'
    end

    # Only an admin or owner can read the namespace admins, and everyone else
    # can delete only their own non-admin key, so the guard steps aside.
    context 'when the caller cannot read the namespace Artifact Admins' do
      before do
        allow(lookup_client).to receive(:lookup).and_raise(
          Authn::IamService::LookupRelationshipsClient::RequestError.new('denied', reason: :permission_denied)
        )
      end

      it_behaves_like 'allowing the change'
    end

    context 'when an organization owner cannot read the namespace Artifact Admins' do
      let_it_be(:owner) { create(:user, :organization_owner, organization: organization) }

      let(:current_user) { owner }

      before do
        allow(lookup_client).to receive(:lookup).and_raise(
          Authn::IamService::LookupRelationshipsClient::RequestError.new('denied', reason: :permission_denied)
        )
      end

      it 'fails closed without revoking anything', :aggregate_failures do
        expect(client).not_to receive(:revoke_roles)

        expect(execute.message).to eq('Could not check the Artifact Admins. Try again.')
      end
    end

    context 'when IAM cannot list the Artifact Admins' do
      before do
        allow(lookup_client).to receive(:lookup).and_raise(
          Authn::IamService::LookupRelationshipsClient::RequestError.new('down', reason: :unavailable)
        )
      end

      it 'fails closed without revoking anything', :aggregate_failures do
        expect(client).not_to receive(:revoke_roles)

        result = execute
        expect(result).to be_error
        expect(result.message).to eq('Could not check the Artifact Admins. Try again.')
      end
    end

    context 'when the revocation targets a repository' do
      let(:revocations) { [{ assignee: assignee_a, resource_id: resource_id }] }

      it 'does not read the admins' do
        expect(lookup_client).not_to receive(:lookup)

        expect(execute).to be_success
      end
    end

    context 'when another role change holds the lease' do
      before do
        allow(lookup_client).to receive(:lookup).and_return(admins_response([assignee_a.id, assignee_b.id]))
        stub_exclusive_lease_taken("authz:artifact_registry:last_admin:#{namespace_id}")
      end

      it 'asks the caller to try again', :aggregate_failures do
        expect(client).not_to receive(:revoke_roles)

        expect(execute.message).to eq('Another role change is in progress. Try again.')
      end
    end
  end
end
