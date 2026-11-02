# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::ArtifactRegistry::LookupAssigneeRoleAssignmentsService, feature_category: :system_access do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:user, organization: organization) }
  let_it_be(:assignee) { create(:user, organization: organization) }
  let_it_be(:other_user) { create(:user, organization: organization) }

  let(:namespace_id) { Gitlab::Utils.uuid_v7 }
  let(:repository_id) { Gitlab::Utils.uuid_v7 }
  let(:other_repository_id) { Gitlab::Utils.uuid_v7 }
  let(:roles) { [] }
  let(:token) { 'ar-token' }
  let(:admin_role_id) { Authz::ArtifactRegistry::Roles.uuid_for(:artifact_admin) }

  let(:iam_client) { instance_double(Authn::IamService::LookupRelationshipsClient) }
  let(:ar_client) { instance_double(ArtifactRegistry::Client) }
  let(:registry) { ArtifactRegistry::NamespaceMapping::Registry.new(slug: 'acme', status: 'active') }
  let(:mapping) { instance_double(ArtifactRegistry::NamespaceMapping, ar_namespace_id: namespace_id, registry: registry) }

  subject(:execute) do
    described_class.new(
      current_user: current_user,
      organization: organization,
      assignee_ids: [assignee.id],
      roles: roles
    ).execute
  end

  before do
    issuer = instance_double(Authn::TokenExchange::TokenIssuer, token: token)
    allow(Authn::TokenExchange::TokenIssuer).to receive(:new).and_return(issuer)
    allow(Authn::IamService::LookupRelationshipsClient).to receive(:new).and_return(iam_client)

    allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(mapping)
    allow(organization).to receive(:artifact_registry_client).with(current_user: current_user).and_return(ar_client)
  end

  def relationship(user, object_id)
    ::Gitlab::Iam::Relationships::V1::Relationship.new(
      subject: ::Gitlab::Iam::Relationships::V1::Subject.new(
        identity: ::Gitlab::Iam::Relationships::V1::Identity.new(local_id: user.id.to_s)
      ),
      object: ::Gitlab::Iam::Relationships::V1::Object.new(id: object_id),
      kind: :KIND_ASSIGNMENT,
      role: ::Gitlab::Iam::Relationships::V1::Role.new(id: admin_role_id)
    )
  end

  def resources_page(*relationships, next_page_token: '')
    ::Gitlab::Iam::Lookup::V1::LookupResourcesResponse.new(
      relationships: relationships, next_page_token: next_page_token
    )
  end

  def relationships_page(*relationships, next_page_token: '')
    ::Gitlab::Iam::Lookup::V1::LookupRelationshipsResponse.new(
      relationships: relationships, next_page_token: next_page_token
    )
  end

  def repository_page(*ids, next_cursor: nil)
    ArtifactRegistry::Page.new(
      nodes: ids.map { |id| ArtifactRegistry::Repository.new('id' => id) },
      next_cursor: next_cursor
    )
  end

  def object_ids(result)
    result.payload[:role_assignments].map { |r| r.object.id }
  end

  context 'when the caller owns the organization' do
    let_it_be(:current_user) { create(:user, :organization_owner, organization: organization) }

    before do
      allow(iam_client).to receive(:lookup_resources).and_return(
        resources_page(
          relationship(assignee, repository_id),
          relationship(assignee, namespace_id),
          relationship(assignee, organization.uuid)
        )
      )
    end

    it 'reads the assignee through LookupResources and keeps only repository assignments', :aggregate_failures do
      result = execute

      expect(result).to be_success
      expect(object_ids(result)).to eq([repository_id])
      expect(iam_client).to have_received(:lookup_resources).with(
        subject_id: assignee.id.to_s,
        organization_uuid: organization.uuid,
        kinds: [:KIND_ASSIGNMENT],
        role_ids: [],
        page_size: Authz::ArtifactRegistry::LookupRoleAssignmentsService::MAX_PAGE_SIZE,
        page_token: nil,
        token: token
      )
    end

    it 'does not list repositories in Artifact Registry' do
      expect(ar_client).not_to receive(:repositories)

      execute
    end

    it 'reads every page' do
      allow(iam_client).to receive(:lookup_resources).and_return(
        resources_page(relationship(assignee, repository_id), next_page_token: 'page-2'),
        resources_page(relationship(assignee, other_repository_id))
      )

      expect(object_ids(execute)).to match_array([repository_id, other_repository_id])
      expect(iam_client).to have_received(:lookup_resources).with(hash_including(page_token: 'page-2'))
    end

    context 'with a role filter' do
      let(:roles) { [:artifact_admin] }

      it 'passes the role ids to IAM' do
        execute

        expect(iam_client).to have_received(:lookup_resources).with(hash_including(role_ids: [admin_role_id]))
      end
    end

    context 'when IAM has never seen the assignee' do
      before do
        allow(iam_client).to receive(:lookup_resources)
          .and_raise(Authn::IamService::LookupRelationshipsClient::RequestError.new('x', reason: :not_found))
      end

      it 'returns no assignments' do
        result = execute

        expect(result).to be_success
        expect(result.payload[:role_assignments]).to be_empty
      end
    end

    context 'when IAM returns tuples with missing fields' do
      let(:no_subject) do
        ::Gitlab::Iam::Relationships::V1::Relationship.new(
          object: ::Gitlab::Iam::Relationships::V1::Object.new(id: repository_id)
        )
      end

      let(:no_identity) do
        ::Gitlab::Iam::Relationships::V1::Relationship.new(
          subject: ::Gitlab::Iam::Relationships::V1::Subject.new,
          object: ::Gitlab::Iam::Relationships::V1::Object.new(id: other_repository_id)
        )
      end

      let(:no_object) do
        ::Gitlab::Iam::Relationships::V1::Relationship.new(
          subject: ::Gitlab::Iam::Relationships::V1::Subject.new(
            identity: ::Gitlab::Iam::Relationships::V1::Identity.new(local_id: assignee.id.to_s)
          )
        )
      end

      before do
        allow(iam_client).to receive(:lookup_resources).and_return(resources_page(no_object, no_identity, no_subject))
      end

      it 'keeps them and sorts tuples without a subject first', :aggregate_failures do
        role_assignments = execute.payload[:role_assignments]

        expect(role_assignments).to contain_exactly(no_subject, no_identity, no_object)
        expect(role_assignments.last).to eq(no_object)
      end
    end

    context 'when IAM rejects the request' do
      before do
        allow(iam_client).to receive(:lookup_resources)
          .and_raise(Authn::IamService::LookupRelationshipsClient::RequestError.new('x', reason: :invalid_request))
      end

      it 'returns the invalid request error' do
        expect(execute.message).to eq('The role assignment lookup request was invalid.')
      end
    end

    context 'when IAM keeps returning pages past the cap' do
      before do
        allow(iam_client).to receive(:lookup_resources)
          .and_return(resources_page(relationship(assignee, repository_id), next_page_token: 'more'))
      end

      it 'returns an error instead of a partial list' do
        result = execute

        expect(result).to be_error
        expect(result.message).to eq('Too many role assignments to look up by assignee.')
        expect(iam_client).to have_received(:lookup_resources).exactly(described_class::MAX_IAM_PAGES).times
      end
    end
  end

  context 'when the caller does not own the organization' do
    let(:repository_lookup) { hash_including(objects: array_including(hash_including(ancestor_ids: [namespace_id]))) }

    before do
      allow(ar_client).to receive(:repositories)
        .and_return(repository_page(repository_id.upcase, other_repository_id))
      allow(iam_client).to receive(:lookup).and_return(
        relationships_page(
          relationship(assignee, repository_id),
          relationship(other_user, other_repository_id),
          relationship(assignee, other_repository_id)
        )
      )
    end

    it 'reads the namespace repositories through LookupRelationships, naming the namespace as ancestor',
      :aggregate_failures do
      result = execute

      expect(result).to be_success
      expect(ar_client).to have_received(:repositories)
        .with(slug: 'acme', limit: described_class::REPOSITORY_PAGE_SIZE, cursor: nil)
      expect(iam_client).to have_received(:lookup).with(
        objects: [
          { id: repository_id, ancestor_ids: [namespace_id] },
          { id: other_repository_id, ancestor_ids: [namespace_id] }
        ],
        kinds: [:KIND_ASSIGNMENT],
        role_ids: [],
        page_size: Authz::ArtifactRegistry::LookupRoleAssignmentsService::MAX_PAGE_SIZE,
        page_token: nil,
        token: token
      )
    end

    it 'checks the caller administers the namespace before listing repositories', :aggregate_failures do
      execute

      expect(iam_client).to have_received(:lookup).with(
        objects: [{ id: namespace_id }],
        kinds: [:KIND_ASSIGNMENT],
        role_ids: [],
        page_size: 1,
        page_token: nil,
        token: token
      ).ordered
      expect(ar_client).to have_received(:repositories).ordered
    end

    context 'when the caller administers repositories but not the namespace' do
      before do
        allow(iam_client).to receive(:lookup).with(hash_including(objects: [{ id: namespace_id }]))
          .and_raise(Authn::IamService::LookupRelationshipsClient::RequestError.new('x', reason: :permission_denied))
      end

      it 'returns the not authorized error instead of a partial list' do
        expect(ar_client).not_to receive(:repositories)

        result = execute

        expect(result).to be_error
        expect(result.message).to eq('You are not authorized to read these role assignments.')
      end
    end

    it 'keeps only the assignees and never uses the owner-only lookup', :aggregate_failures do
      expect(iam_client).not_to receive(:lookup_resources)

      result = execute

      expect(object_ids(result)).to match_array([repository_id, other_repository_id])
      expect(result.payload[:role_assignments].map { |r| r.subject.identity.local_id }.uniq)
        .to eq([assignee.id.to_s])
    end

    it 'reads every repository page' do
      allow(ar_client).to receive(:repositories).with(hash_including(cursor: nil))
        .and_return(repository_page(repository_id, next_cursor: 'c2'))
      allow(ar_client).to receive(:repositories).with(hash_including(cursor: 'c2'))
        .and_return(repository_page(other_repository_id))

      execute

      expect(iam_client).to have_received(:lookup)
        .with(hash_including(objects: match_array([
          { id: repository_id, ancestor_ids: [namespace_id] },
          { id: other_repository_id, ancestor_ids: [namespace_id] }
        ])))
    end

    it 'skips repositories without an id' do
      allow(ar_client).to receive(:repositories)
        .and_return(ArtifactRegistry::Page.new(nodes: [ArtifactRegistry::Repository.new({}),
          ArtifactRegistry::Repository.new('id' => repository_id)]))

      execute

      expect(iam_client).to have_received(:lookup)
        .with(hash_including(objects: [{ id: repository_id, ancestor_ids: [namespace_id] }]))
    end

    it 'drops tuples without a subject identity' do
      allow(iam_client).to receive(:lookup).and_return(
        relationships_page(
          ::Gitlab::Iam::Relationships::V1::Relationship.new(
            object: ::Gitlab::Iam::Relationships::V1::Object.new(id: repository_id)
          ),
          ::Gitlab::Iam::Relationships::V1::Relationship.new(
            subject: ::Gitlab::Iam::Relationships::V1::Subject.new,
            object: ::Gitlab::Iam::Relationships::V1::Object.new(id: repository_id)
          ),
          relationship(assignee, other_repository_id)
        )
      )

      expect(object_ids(execute)).to eq([other_repository_id])
    end

    context 'when IAM fails' do
      using RSpec::Parameterized::TableSyntax

      where(:reason, :message) do
        :not_found | 'The requested resources could not be found.'
        :internal  | 'The role assignment lookup could not be completed.'
      end

      with_them do
        before do
          allow(iam_client).to receive(:lookup).with(repository_lookup)
            .and_raise(Authn::IamService::LookupRelationshipsClient::RequestError.new('x', reason: reason))
        end

        it 'returns the matching error' do
          expect(execute.message).to eq(message)
        end
      end
    end

    context 'when the namespace has no slug' do
      let(:registry) { ArtifactRegistry::NamespaceMapping::Registry.new(slug: nil, status: 'active') }

      it 'returns an error' do
        expect(execute.message).to eq('The Artifact Registry repositories could not be listed.')
      end
    end

    context 'when the namespace has no repositories' do
      before do
        allow(ar_client).to receive(:repositories).and_return(repository_page)
      end

      it 'returns no assignments after only the namespace check', :aggregate_failures do
        expect(execute.payload[:role_assignments]).to be_empty
        expect(iam_client).to have_received(:lookup).once
      end
    end

    context 'when the namespace has more repositories than the cap' do
      before do
        stub_const("#{described_class}::MAX_REPOSITORIES", 1)
      end

      it 'returns an error after only the namespace check', :aggregate_failures do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('more than 1 repositories')
        expect(iam_client).to have_received(:lookup).once
      end
    end

    context 'when Artifact Registry keeps returning pages past the cap' do
      before do
        stub_const("#{described_class}::MAX_REPOSITORIES", 2)
        stub_const("#{described_class}::REPOSITORY_PAGE_SIZE", 1)
        allow(ar_client).to receive(:repositories).and_return(repository_page(next_cursor: 'more'))
      end

      it 'stops and returns an error' do
        result = execute

        expect(result).to be_error
        expect(ar_client).to have_received(:repositories).exactly(3).times
      end
    end

    context 'when the caller cannot see the namespace' do
      before do
        allow(ar_client).to receive(:repositories).and_return(nil)
      end

      it 'returns the not authorized error' do
        expect(execute.message).to eq('You are not authorized to read these role assignments.')
      end
    end

    context 'when IAM denies the repository lookup' do
      before do
        allow(iam_client).to receive(:lookup).with(repository_lookup)
          .and_raise(Authn::IamService::LookupRelationshipsClient::RequestError.new('x', reason: :permission_denied))
      end

      it 'returns the not authorized error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to eq('You are not authorized to read these role assignments.')
      end
    end

    context 'when Artifact Registry fails' do
      before do
        allow(ar_client).to receive(:repositories).and_raise(ArtifactRegistry::Client::UnavailableError)
      end

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to eq('The Artifact Registry repositories could not be listed.')
      end
    end

    context 'when the namespace slug could not be resolved' do
      let(:registry) do
        ArtifactRegistry::NamespaceMapping::ResolutionFailure.new(
          error_class: 'ArtifactRegistry::Client::UnavailableError', message: 'down'
        )
      end

      it 'returns an error' do
        expect(execute.message).to eq('The Artifact Registry repositories could not be listed.')
      end
    end
  end

  context 'when the organization has no Artifact Registry namespace' do
    let(:mapping) { nil }

    it 'returns no assignments without calling out' do
      expect(iam_client).not_to receive(:lookup)
      expect(iam_client).not_to receive(:lookup_resources)

      result = execute

      expect(result).to be_success
      expect(result.payload[:role_assignments]).to be_empty
    end
  end

  context 'when there is no current user' do
    it 'returns an error' do
      result = described_class.new(current_user: nil, organization: organization, assignee_ids: [assignee.id]).execute

      expect(result.message).to eq('You must be signed in to read role assignments.')
    end
  end

  context 'when there is no organization' do
    it 'returns an error' do
      result = described_class.new(current_user: current_user, organization: nil, assignee_ids: [assignee.id]).execute

      expect(result.message).to eq('Organization could not be determined.')
    end
  end

  context 'with no assignee ids' do
    it 'returns no assignments without calling out' do
      expect(iam_client).not_to receive(:lookup)
      expect(iam_client).not_to receive(:lookup_resources)

      result = described_class.new(current_user: current_user, organization: organization, assignee_ids: []).execute

      expect(result).to be_success
      expect(result.payload[:role_assignments]).to be_empty
    end
  end

  context 'when the caller is not a member of the organization' do
    let_it_be(:current_user) { create(:user) }

    it 'returns the generic not found error' do
      expect(execute.message).to eq('The requested resources could not be found.')
    end
  end

  context 'with an unknown role' do
    let(:roles) { [:artifact_super_admin] }

    it 'returns a validation error' do
      expect(execute.message).to eq('Unknown Artifact Registry roles: artifact_super_admin.')
    end
  end
end
