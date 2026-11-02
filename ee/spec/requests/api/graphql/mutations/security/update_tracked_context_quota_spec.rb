# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Security::UpdateTrackedContextQuota, feature_category: :vulnerability_management do
  include GraphqlHelpers

  let_it_be(:organization) { create(:organization) }
  let_it_be(:owner) { create(:organization_user, :owner, organization: organization).user }

  let(:quota) { 10 }
  let(:params) { { organization_id: organization.to_global_id.to_s, quota: quota } }
  let(:mutation) { graphql_mutation(:security_update_tracked_context_quota, params) }

  before do
    stub_feature_flags(vulnerabilities_across_contexts: organization)
  end

  def mutation_response
    graphql_mutation_response(:security_update_tracked_context_quota)
  end

  it { expect(described_class).to require_graphql_authorizations(:update_organization) }

  it_behaves_like 'authorizing granular token permissions for GraphQL', :update_organization do
    let(:user) { owner }
    let(:boundary_object) { :instance }
    let(:mutation) { graphql_mutation(:security_update_tracked_context_quota, params, 'errors') }
    let(:request) { post_graphql_mutation(mutation, token: { personal_access_token: pat }) }
  end

  context 'when the user can administer the organization' do
    it 'updates the quota and returns the quota info', :aggregate_failures do
      post_graphql_mutation(mutation, current_user: owner)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['quotaInfo']).to include(
        'limit' => 10,
        'explicitlySet' => true
      )
      expect(
        ::Organizations::OrganizationSetting.for(organization.id).security_tracked_context_quota
      ).to eq(10)
    end

    context 'for audit events' do
      before do
        stub_licensed_features(admin_audit_log: true)
      end

      it 'records the change from the default with instance scope' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
          hash_including(
            name: 'security_tracked_context_quota_updated',
            author: owner,
            scope: instance_of(::Gitlab::Audit::InstanceScope),
            target: organization,
            message: "Changed the tracked security context quota for organization '#{organization.name}' " \
              "from the default to 10"
          )
        ).and_call_original

        expect { post_graphql_mutation(mutation, current_user: owner) }.to change { AuditEventReader.count }.by(1)
      end

      context 'when a quota was already set' do
        before do
          ::Organizations::OrganizationSetting.for(organization.id).update!(security_tracked_context_quota: 5)
        end

        it 'records the previous quota' do
          expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
            hash_including(
              message: "Changed the tracked security context quota for organization '#{organization.name}' " \
                "from 5 to 10"
            )
          ).and_call_original

          post_graphql_mutation(mutation, current_user: owner)
        end
      end

      context 'when the quota does not change' do
        before do
          ::Organizations::OrganizationSetting.for(organization.id).update!(security_tracked_context_quota: quota)
        end

        it 'does not record an audit event' do
          expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

          post_graphql_mutation(mutation, current_user: owner)
        end
      end

      context 'when the quota is invalid' do
        let(:quota) { 0 }

        it 'does not record an audit event' do
          expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

          post_graphql_mutation(mutation, current_user: owner)
        end
      end
    end

    context 'when the quota is invalid' do
      let(:quota) { 0 }

      it 'returns a validation error and does not update the setting', :aggregate_failures do
        post_graphql_mutation(mutation, current_user: owner)

        expect(response).to have_gitlab_http_status(:success)
        expect(mutation_response['errors']).to be_present
        expect(mutation_response['quotaInfo']).to be_nil
        expect(
          ::Organizations::OrganizationSetting.for(organization.id).security_tracked_context_quota
        ).to be_nil
      end
    end
  end

  context 'when the user is an organization member but not an owner' do
    let_it_be(:member) { create(:organization_user, organization: organization).user }

    it_behaves_like 'a mutation that returns a top-level access error' do
      let(:current_user) { member }
    end
  end

  context 'when the user is not a member of the organization' do
    let_it_be(:non_member) { create(:user) }

    it_behaves_like 'a mutation that returns a top-level access error' do
      let(:current_user) { non_member }
    end
  end

  context 'when the organization does not exist' do
    let(:params) { { organization_id: 'gid://gitlab/Organizations::Organization/0', quota: quota } }

    it_behaves_like 'a mutation that returns a top-level access error' do
      let(:current_user) { owner }
    end
  end

  context 'when Vulnerabilities Across Contexts is disabled for the organization' do
    before do
      stub_feature_flags(vulnerabilities_across_contexts: false)
    end

    it 'returns a top-level error and does not update the setting', :aggregate_failures do
      post_graphql_mutation(mutation, current_user: owner)

      expect(response).to have_gitlab_http_status(:success)
      expect(graphql_errors).to include(
        a_hash_including('message' => 'Vulnerabilities Across Contexts is not enabled for this organization.')
      )
      expect(
        ::Organizations::OrganizationSetting.for(organization.id).security_tracked_context_quota
      ).to be_nil
    end
  end
end
