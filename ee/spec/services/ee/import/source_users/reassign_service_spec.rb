# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::SourceUsers::ReassignService, feature_category: :importers do
  let_it_be(:group) { create(:group) }
  let_it_be_with_reload(:import_source_user) { create(:import_source_user, namespace: group) }
  let_it_be(:current_user) { create(:user) }
  let_it_be(:assignee_user) { create(:user) }
  let_it_be(:service_account) { create(:service_account, provisioned_by_group: group) }
  let_it_be(:another_service_account) { create(:service_account, provisioned_by_group: create(:group)) }

  subject(:service) { described_class.new(import_source_user, assignee_user, current_user: current_user) }

  describe '#execute' do
    before_all do
      group.add_owner(current_user)
    end

    shared_examples 'an error response' do |desc, error:|
      it "returns #{desc} error", :aggregate_failures do
        expect(Notify).not_to receive(:import_source_user_reassign)

        result = service.execute

        expect(result).to be_error
        expect(result.message).to eq(error)
      end
    end

    shared_examples 'success response' do
      it 'returns success', :aggregate_failures do
        expect(Notify).to receive_message_chain(:import_source_user_reassign, :deliver_later)

        result = service.execute

        expect(result).to be_success
        expect(result.payload.reload).to eq(import_source_user)
        expect(result.payload.reassign_to_user).to eq(assignee_user)
        expect(result.payload.reassigned_by_user).to eq(current_user)
        expect(result.payload.awaiting_approval?).to be(true)
      end
    end

    shared_examples 'a success response that bypasses user confirmation' do
      it 'returns success', :aggregate_failures do
        expect(Import::ReassignPlaceholderUserRecordsWorker).to receive(:perform_async).with(import_source_user.id,
          'confirmation_skipped' => true)

        result = service.execute

        expect(result).to be_success
        expect(result.payload.reload).to eq(import_source_user)
        expect(result.payload.reassign_to_user).to eq(assignee_user)
        expect(result.payload.reassigned_by_user).to eq(current_user)
        expect(result.payload.reassignment_in_progress?).to be(true)
      end
    end

    context 'for SSO enforcement requirements' do
      before do
        stub_licensed_features(group_saml: true)
      end

      context 'when SSO enforcement is enabled for namespace' do
        let_it_be(:saml_provider) { create(:saml_provider, group: group, enforced_sso: true) }

        context 'when assignee user account does not meet SSO enforcement requirements' do
          it_behaves_like 'an error response', 'invalid_assignee',
            error: 'You can assign only users with linked SAML and SCIM identities. ' \
              'Ensure the user has signed into GitLab through your SAML SSO provider and has an ' \
              'active SCIM identity for this group.'

          context 'when assignee user account with linked SAML, but SCIM identity is inactive' do
            let_it_be(:group_saml_identity) do
              create(:group_saml_identity, saml_provider: saml_provider, user: assignee_user)
            end

            let_it_be(:group_scim_identity) do
              create(:group_scim_identity, active: false, group: group, user: assignee_user)
            end

            it_behaves_like 'an error response', 'invalid_assignee',
              error: 'You can assign only users with linked SAML and SCIM identities. ' \
                'Ensure the user has signed into GitLab through your SAML SSO provider and has an ' \
                'active SCIM identity for this group.'
          end
        end

        context 'when assignee user account meets SSO enforcement requirements' do
          let_it_be(:group_saml_identity) do
            create(:group_saml_identity, saml_provider: saml_provider, user: assignee_user)
          end

          it_behaves_like 'success response'
        end
      end

      context 'when SSO enforcement is not enabled for namespace' do
        let!(:saml_provider) { create(:saml_provider, group: group, enforced_sso: false) }

        context 'when assignee user account does not meet SSO enforcement requirements' do
          it_behaves_like 'success response'
        end
      end
    end

    context 'for enterprise users check' do
      before do
        # Needed for managed_by_group?
        stub_licensed_features(domain_verification: true)
        allow(::Gitlab).to receive(:com?).and_return(true)
      end

      context 'when there are enterprise users' do
        let_it_be(:enterprise_user) { create(:user, enterprise_group: group) }

        context 'when the user is part of the enterprise group' do
          let_it_be(:assignee_user) { enterprise_user }

          it_behaves_like 'success response'
        end

        context 'when the user is an enterprise users for another group' do
          let_it_be(:other_group) { create(:group) }
          let_it_be(:assignee_user) { create(:user, enterprise_group: other_group) }

          it_behaves_like 'an error response',
            error: "You can assign only enterprise users in the top-level group you're importing to."
        end

        context 'when the user is not part of an enterprise group' do
          it_behaves_like 'an error response',
            error: "You can assign only enterprise users in the top-level group you're importing to."
        end

        context 'when the assignee is a non-enterprise user and the group has members' do
          let_it_be_with_reload(:group) { create(:group) }
          let_it_be_with_reload(:import_source_user) { create(:import_source_user, namespace: group) }
          let_it_be(:subgroup) { create(:group, parent: group) }
          let_it_be(:project) { create(:project, group: group) }
          let_it_be(:invited_group) { create(:group) }
          let_it_be(:project_invited_group) { create(:group) }

          before_all do
            group.add_owner(current_user)
            create(:user, enterprise_group: group)
            create(:group_group_link, shared_group: subgroup, shared_with_group: invited_group)
            create(:project_group_link, project: project, group: project_invited_group)
          end

          context 'when the group has opted in to non-enterprise placeholder reassignment' do
            shared_examples 'a members-only error response' do
              it_behaves_like 'an error response',
                error: "You can assign only enterprise users or existing members of the top-level group " \
                  "you're importing to, its subgroups, or its projects."
            end

            before do
              group.namespace_settings.update!(allow_non_enterprise_placeholder_reassignment: true)
            end

            context 'when the assignee is a direct member of the group' do
              let(:assignee_user) { create(:user, developer_of: group) }

              it_behaves_like 'success response'
            end

            context 'when the assignee is a member of a subgroup' do
              let(:assignee_user) { create(:user, developer_of: subgroup) }

              it_behaves_like 'success response'
            end

            context 'when the assignee is a member of a project in the group' do
              let(:assignee_user) { create(:user, developer_of: project) }

              it_behaves_like 'success response'
            end

            context 'when the assignee is a member of a group invited to a subgroup' do
              let(:assignee_user) { create(:user, developer_of: invited_group) }

              it_behaves_like 'success response'
            end

            context 'when the assignee is a member of a group invited to a project in the group' do
              let(:assignee_user) { create(:user, developer_of: project_invited_group) }

              it_behaves_like 'success response'
            end

            context 'when the assignee is a member of a group invited as a Guest' do
              let_it_be(:guest_invited_group) { create(:group) }
              let(:assignee_user) { create(:user, developer_of: guest_invited_group) }

              before do
                create(:group_group_link, :guest, shared_group: group, shared_with_group: guest_invited_group)
              end

              it_behaves_like 'success response'
            end

            context 'when the assignee is a member of a group invited with Minimal Access' do
              let_it_be(:minimal_access_invited_group) { create(:group) }
              let(:assignee_user) { create(:user, developer_of: minimal_access_invited_group) }

              before do
                stub_licensed_features(domain_verification: true, minimal_access_role: true)
                create(:group_group_link, shared_group: group, shared_with_group: minimal_access_invited_group,
                  group_access: Gitlab::Access::MINIMAL_ACCESS)
              end

              it_behaves_like 'a members-only error response'
            end

            context 'when the assignee has only requested access to the group' do
              let(:assignee_user) { create(:group_member, :access_request, :developer, source: group).user }

              it_behaves_like 'a members-only error response'
            end

            context 'when the assignee is an awaiting member of the group' do
              let(:assignee_user) { create(:group_member, :awaiting, :developer, source: group).user }

              it_behaves_like 'a members-only error response'
            end

            context 'when the assignee has Minimal Access to the group' do
              let(:assignee_user) { create(:group_member, :minimal_access, source: group).user }

              it_behaves_like 'a members-only error response'
            end

            context 'when the assignee is not a member of the group hierarchy' do
              it_behaves_like 'a members-only error response'

              it 'counts the memberships, then checks membership with a single query' do
                recorder = ActiveRecord::QueryRecorder.new { service.send(:valid_non_enterprise_member_assignee?) }

                expect(recorder.log.count { |sql| sql.include?('"members"') }).to eq(2)
              end

              it 'projects only the member id', :aggregate_failures do
                recorder = ActiveRecord::QueryRecorder.new { service.send(:valid_non_enterprise_member_assignee?) }
                members_query = recorder.log.reverse.find { |sql| sql.include?('"members"') }

                expect(members_query).to include('SELECT "members"."id" FROM "members"')
                expect(members_query).not_to include('"members"."access_level"')
              end
            end

            context 'when the setting_allow_non_enterprise_placeholder_reassignment feature flag is disabled' do
              let(:assignee_user) { create(:user, developer_of: group) }

              before do
                stub_feature_flags(setting_allow_non_enterprise_placeholder_reassignment: false)
              end

              it_behaves_like 'an error response',
                error: "You can assign only enterprise users in the top-level group you're importing to."
            end
          end

          context 'when the group has not opted in to non-enterprise placeholder reassignment' do
            let(:assignee_user) { create(:user, developer_of: group) }

            it_behaves_like 'an error response',
              error: "You can assign only enterprise users in the top-level group you're importing to."
          end
        end
      end

      context 'when there are no enterprise users' do
        it_behaves_like 'success response'
      end
    end

    context 'when enterprise bypass placeholder confirmation is allowed' do
      before do
        allow_next_instance_of(Import::UserMapping::EnterpriseBypassAuthorizer, group, assignee_user,
          current_user) do |authorizer|
          allow(authorizer).to receive(:allowed?).and_return(true)
        end
      end

      it_behaves_like 'a success response that bypasses user confirmation'
    end

    describe 'service account reassignment' do
      context 'when assignee user is a service account that belongs to the group' do
        let(:assignee_user) { service_account }

        it_behaves_like 'a success response that bypasses user confirmation'
      end

      context 'when assignee user is a service account that does not belong to the group' do
        let(:assignee_user) { another_service_account }

        it_behaves_like 'an error response',
          error: "Service account does not belong to top level group."
      end
    end
  end
end
