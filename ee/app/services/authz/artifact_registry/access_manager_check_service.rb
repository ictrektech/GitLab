# frozen_string_literal: true

module Authz
  module ArtifactRegistry
    # Answers "can this user grant Artifact Registry roles?". Callers use this, not a policy ability,
    # because the Artifact Admin half calls IAM. Repository-level admins don't count.
    class AccessManagerCheckService < BaseService
      # This runs in Puma on page loads, so it gets a shorter deadline than writes.
      READ_TIMEOUT_SECONDS = 5

      def initialize(current_user:, organization:)
        @current_user = current_user
        @organization = organization
      end

      def execute
        return false unless current_user && organization
        return true if Ability.allowed?(current_user, :create_artifact_registry_role_assignment, organization)
        return false unless ::Authn::IamDataAccessService.configured?
        return false unless artifact_registry_namespace_id && caller_in_organization?

        # One IAM call per user and organization per request, however many callers ask.
        ::Gitlab::SafeRequestStore.fetch([self.class.name, current_user.id, organization.id]) { namespace_admin? }
      end

      private

      def namespace_admin?
        admin_role_id = Roles.uuid_for(:artifact_admin)
        # A missing id would match an assignment with no role (nil == nil).
        return false unless admin_role_id

        lookup_client.read(
          subject_id: current_user.id,
          organization_uuid: organization.uuid,
          objects: [artifact_registry_namespace_id],
          kinds: [LookupRoleAssignmentsService::ASSIGNMENT_KIND],
          token: token
        ).relationships.any? { |relationship| relationship.role&.id == admin_role_id }
      rescue ::Authn::IamService::LookupRelationshipsClient::RequestError
        # The client already reported the failure to error tracking.
        false
      rescue StandardError, ::Gitlab::AbstractMethodError => e # This gates UI, so a token failure must not 500.
        Gitlab::ErrorTracking.track_exception(e)
        false
      end

      def lookup_client
        ::Authn::IamService::LookupRelationshipsClient.new(timeout: READ_TIMEOUT_SECONDS)
      end
    end
  end
end
