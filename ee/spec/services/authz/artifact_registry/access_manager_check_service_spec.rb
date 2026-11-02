# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authz::ArtifactRegistry::AccessManagerCheckService, feature_category: :system_access do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:namespace_mapping) { create(:artifact_registry_namespace_mapping, organization: organization) }
  let_it_be(:member) { create(:user) }
  let_it_be(:non_member) { create(:user) }

  let(:current_user) { member }
  let(:lookup_client) { instance_double(Authn::IamService::LookupRelationshipsClient) }
  let(:held_role) { :artifact_admin }

  subject(:execute) { described_class.new(current_user: current_user, organization: organization).execute }

  before_all do
    create(:organization_user, organization: organization, user: member)
  end

  before do
    allow(Authn::IamDataAccessService).to receive(:configured?).and_return(true)

    issuer = instance_double(Authn::TokenExchange::TokenIssuer, token: 'ar-token')
    allow(Authn::TokenExchange::TokenIssuer).to receive(:new).and_return(issuer)

    allow(Authn::IamService::LookupRelationshipsClient).to receive(:new).and_return(lookup_client)
    allow(lookup_client).to receive(:read) { read_response(held_role) }
  end

  def read_response(role)
    relationships = Array(role).map do |name|
      ::Gitlab::Iam::Relationships::V1::Relationship.new(
        role: ::Gitlab::Iam::Relationships::V1::Role.new(id: Authz::ArtifactRegistry::Roles.uuid_for(name))
      )
    end

    ::Gitlab::Iam::Lookup::V1::ReadRelationshipsResponse.new(relationships: relationships)
  end

  context 'when the member holds Artifact Admin on the registry namespace' do
    it 'reads only their own grant on the namespace', :aggregate_failures do
      expect(lookup_client).to receive(:read).with(
        subject_id: member.id,
        organization_uuid: organization.uuid,
        objects: [namespace_mapping.ar_namespace_id],
        kinds: [:KIND_ASSIGNMENT],
        token: 'ar-token'
      ).and_return(read_response(:artifact_admin))

      expect(execute).to be(true)
    end

    it 'reads with the short read deadline' do
      execute

      expect(Authn::IamService::LookupRelationshipsClient).to have_received(:new)
        .with(timeout: described_class::READ_TIMEOUT_SECONDS)
    end
  end

  context 'when the user is an organization owner' do
    # A fresh organization, since the shared one memoizes its owner ids across examples.
    let_it_be(:organization) { create(:organization) }
    let_it_be(:namespace_mapping) { create(:artifact_registry_namespace_mapping, organization: organization) }
    let_it_be(:owner) { create(:user) }
    let(:current_user) { owner }

    before_all do
      create(:organization_user, :owner, organization: organization, user: owner)
    end

    it 'answers true without calling IAM', :aggregate_failures do
      expect(execute).to be(true)
      expect(lookup_client).not_to have_received(:read)
    end
  end

  context 'when asked more than once in a request', :request_store do
    it 'calls IAM once' do
      2.times { described_class.new(current_user: current_user, organization: organization).execute }

      expect(lookup_client).to have_received(:read).once
    end

    it 'caches a false answer too' do
      allow(lookup_client).to receive(:read) { read_response(:artifact_manager) }

      2.times { described_class.new(current_user: current_user, organization: organization).execute }

      expect(lookup_client).to have_received(:read).once
    end
  end

  context 'when IAM data access is not configured' do
    before do
      allow(Authn::IamDataAccessService).to receive(:configured?).and_return(false)
    end

    it 'answers false without minting a token or calling IAM', :aggregate_failures do
      expect(execute).to be(false)
      expect(Authn::TokenExchange::TokenIssuer).not_to have_received(:new)
      expect(lookup_client).not_to have_received(:read)
    end
  end

  context 'when the member holds a lower role on the registry namespace' do
    let(:held_role) { :artifact_manager }

    it { is_expected.to be(false) }
  end

  context 'when the member holds no role on the registry namespace' do
    let(:held_role) { [] }

    it { is_expected.to be(false) }
  end

  context 'when IAM returns a relationship with no role' do
    before do
      allow(lookup_client).to receive(:read).and_return(
        ::Gitlab::Iam::Lookup::V1::ReadRelationshipsResponse.new(
          relationships: [::Gitlab::Iam::Relationships::V1::Relationship.new]
        )
      )
    end

    it 'answers false without raising or tracking an error', :aggregate_failures do
      allow(Gitlab::ErrorTracking).to receive(:track_exception)

      expect(execute).to be(false)
      expect(Gitlab::ErrorTracking).not_to have_received(:track_exception)
    end
  end

  context 'when the Artifact Admin role id cannot be resolved' do
    before do
      allow(Authz::ArtifactRegistry::Roles).to receive(:uuid_for).with(:artifact_admin).and_return(nil)
      allow(lookup_client).to receive(:read).and_return(
        ::Gitlab::Iam::Lookup::V1::ReadRelationshipsResponse.new(
          relationships: [::Gitlab::Iam::Relationships::V1::Relationship.new]
        )
      )
    end

    it 'answers false without calling IAM', :aggregate_failures do
      expect(execute).to be(false)
      expect(lookup_client).not_to have_received(:read)
    end
  end

  context 'when the user is not a member of the organization' do
    let(:current_user) { non_member }

    it 'answers false without calling IAM', :aggregate_failures do
      expect(lookup_client).not_to receive(:read)

      expect(execute).to be(false)
    end
  end

  context 'when there is no user' do
    let(:current_user) { nil }

    it { is_expected.to be(false) }
  end

  context 'when IAM cannot answer' do
    before do
      allow(lookup_client).to receive(:read).and_raise(
        Authn::IamService::LookupRelationshipsClient::RequestError.new('down', reason: :unavailable)
      )
    end

    it { is_expected.to be(false) }
  end

  context 'when the IAM token cannot be minted' do
    before do
      allow(Authn::TokenExchange::TokenIssuer).to receive(:new).and_raise(Gitlab::AbstractMethodError)
      allow(Gitlab::ErrorTracking).to receive(:track_exception)
    end

    it 'answers false and tracks the error', :aggregate_failures do
      expect(execute).to be(false)
      expect(Gitlab::ErrorTracking).to have_received(:track_exception).with(an_instance_of(Gitlab::AbstractMethodError))
    end
  end

  context 'when the organization has no Artifact Registry namespace' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:namespace_mapping) { nil }

    before_all do
      create(:organization_user, organization: organization, user: member)
    end

    it 'answers false without calling IAM', :aggregate_failures do
      expect(lookup_client).not_to receive(:read)

      expect(execute).to be(false)
    end
  end
end
