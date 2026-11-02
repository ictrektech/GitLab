# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::ArtifactRegistry::NamespaceAdminIdsService, feature_category: :system_access do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:current_user) { create(:user, organization: organization) }
  let_it_be(:admin) { create(:user, organization: organization) }
  let_it_be(:blocked_admin) { create(:user, :blocked, organization: organization) }
  let_it_be(:non_member) { create(:user) }

  let(:namespace_id) { Gitlab::Utils.uuid_v7 }

  subject(:execute) do
    described_class.new(current_user: current_user, organization: organization, namespace_id: namespace_id).execute
  end

  def assignment(local_id)
    identity = local_id && ::Gitlab::Iam::Relationships::V1::Identity.new(local_id: local_id.to_s)

    ::Gitlab::Iam::Relationships::V1::Relationship.new(
      subject: ::Gitlab::Iam::Relationships::V1::Subject.new(identity: identity)
    )
  end

  def page(local_ids, next_page_token: '')
    ServiceResponse.success(
      payload: { role_assignments: local_ids.map { |id| assignment(id) }, next_page_token: next_page_token }
    )
  end

  # One lookup service per page, answering in order.
  def stub_lookup(*responses)
    services = responses.map do |response|
      instance_double(::Authz::ArtifactRegistry::LookupRoleAssignmentsService, execute: response)
    end
    allow(::Authz::ArtifactRegistry::LookupRoleAssignmentsService).to receive(:new).and_return(*services)
  end

  it 'reads the Artifact Admins of the namespace only' do
    expect(::Authz::ArtifactRegistry::LookupRoleAssignmentsService).to receive(:new).with(
      current_user: current_user,
      organization: organization,
      objects: [{ resource_id: namespace_id, ancestor_ids: [] }],
      roles: [:artifact_admin],
      page_size: described_class::PAGE_SIZE,
      page_after: nil
    ).and_return(instance_double(::Authz::ArtifactRegistry::LookupRoleAssignmentsService, execute: page([admin.id])))

    expect(execute).to be_success
    expect(execute.payload).to eq(admin_ids: Set[admin.id])
  end

  it 'keeps only active organization members with a user identity' do
    stub_lookup(page([admin.id, blocked_admin.id, non_member.id, nil, '']))

    expect(execute.payload[:admin_ids]).to eq(Set[admin.id])
  end

  it 'reads every page' do
    stub_lookup(page([admin.id], next_page_token: 'next'), page([current_user.id]))

    expect(execute.payload[:admin_ids]).to eq(Set[admin.id, current_user.id])
  end

  it 'answers many past the page limit' do
    stub_lookup(*Array.new(described_class::MAX_PAGES) { page([admin.id], next_page_token: 'next') })

    expect(execute).to be_success
    expect(execute.payload).to eq(many: true)
  end

  it 'fails with :unknown when IAM fails' do
    stub_lookup(ServiceResponse.error(message: 'unavailable'))

    expect(execute).to be_error
    expect(execute.reason).to eq(:unknown)
  end

  context 'when IAM denies the read' do
    before do
      stub_lookup(ServiceResponse.error(message: 'denied', reason: :permission_denied))
    end

    it { is_expected.to have_attributes(error?: true, reason: :not_readable) }

    context 'when there is no current user' do
      let(:current_user) { nil }

      it { is_expected.to have_attributes(error?: true, reason: :not_readable) }
    end

    context 'when the caller owns the organization' do
      let_it_be(:owner) { create(:user) }
      let(:current_user) { owner }

      before_all do
        create(:organization_user, :owner, organization: organization, user: owner)
      end

      it { is_expected.to have_attributes(error?: true, reason: :unknown) }
    end
  end
end
