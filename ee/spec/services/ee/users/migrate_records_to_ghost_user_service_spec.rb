# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Users::MigrateRecordsToGhostUserService, feature_category: :user_management do
  let!(:user) { create(:user) }
  let(:service) { described_class.new(user, admin, execution_tracker) }
  let(:execution_tracker) { instance_double(::Gitlab::Utils::ExecutionTracker, over_limit?: false) }

  let_it_be(:admin) { create(:admin) }
  let_it_be(:ghost_user) { create(:user, :ghost) }

  before do
    allow(Users::Internal).to receive(:ghost).and_return(ghost_user)
  end

  context "when migrating a user's associated records to the ghost user" do
    context 'for epics' do
      context 'when deleted user is present as both author and edited_user' do
        include_examples 'migrating records to the ghost user', Epic, [:author, :last_edited_by] do
          let(:created_record) do
            create(:epic, group: create(:group), author: user, last_edited_by: user, last_edited_at: Time.current)
          end
        end
      end

      context 'when deleted user is present only as edited_user' do
        include_examples 'migrating records to the ghost user', Epic, [:last_edited_by] do
          let(:created_record) do
            create(:epic, group: create(:group),
              author: create(:user), last_edited_by: user, last_edited_at: Time.current)
          end
        end
      end
    end

    context 'for vulnerability_feedback author' do
      include_examples 'migrating records to the ghost user', Vulnerabilities::Feedback, [:author] do
        let(:created_record) { create(:vulnerability_feedback, author: user) }
      end
    end

    context 'for vulnerability_feedback comment author' do
      include_examples 'migrating records to the ghost user', Vulnerabilities::Feedback, [:comment_author] do
        let(:created_record) { create(:vulnerability_feedback, comment_author: user) }
      end
    end

    context 'for vulnerability author' do
      include_examples 'migrating records to the ghost user', Vulnerability, [:author] do
        let(:created_record) { create(:vulnerability, author: user) }
      end
    end

    context 'for vulnerability_external_issue_link author' do
      include_examples 'migrating records to the ghost user', Vulnerabilities::ExternalIssueLink, [:author] do
        let(:created_record) { create(:vulnerabilities_external_issue_link, author: user) }
      end
    end

    context 'for resource_iteration_events' do
      let(:always_ghost) { true }

      include_examples 'migrating records to the ghost user', ResourceIterationEvent, [:user] do
        let(:created_record) do
          create(
            :resource_iteration_event,
            issue: create(:issue),
            user: user,
            iteration: create(:iteration)
          )
        end
      end
    end

    context 'for resource_link_events' do
      let(:always_ghost) { true }

      include_examples 'migrating records to the ghost user', ::WorkItems::ResourceLinkEvent, [:user] do
        let(:created_record) do
          create(
            :resource_link_event,
            issue: create(:issue),
            child_work_item: create(:work_item),
            user: user
          )
        end
      end
    end
  end

  context 'on post-migrate cleanups' do
    subject(:operation) { service.execute }

    it 'unmatches the workforce people matched to the user before deleting the user' do
      person = create(:workforce_person, user: user)

      expect(user).to receive(:destroy).and_wrap_original do |original|
        expect(person.reload.user_id).to be_nil

        original.call
      end

      operation
    end

    describe 'audit events' do
      it 'sends the audit event for user migration to ghost' do
        audit_context = {
          name: 'user_records_migrated_to_ghost',
          author: admin,
          scope: user,
          target: user,
          target_details: user.full_path,
          message: 'User records migrated to ghost user',
          additional_details: {
            action: 'migrate_to_ghost',
            author_name: admin.name,
            target_id: user.id,
            target_type: 'User'
          }
        }

        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(audit_context)

        operation
      end

      it 'does not send audit event when user is not destroyed' do
        expect(user).to receive(:destroy).and_return(user)
        expect(user).to receive(:destroyed?).and_return(false)

        expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

        operation
      end
    end

    context 'when the user is the sole approver on a protected environment' do
      let!(:protected_environment) { create(:protected_environment) }
      let!(:approval_rule) do
        create(:protected_environment_approval_rule, protected_environment: protected_environment, user: user)
      end

      it 'reassigns the approval rule and still destroys the user', :aggregate_failures do
        operation

        expect(User.exists?(user.id)).to be(false)

        approval_rule.reload
        expect(approval_rule.user_id).to be_nil
        expect(approval_rule.access_level).to eq(Gitlab::Access::MAINTAINER)
      end

      it 'reassigns the approval rule from inside destroy, not in a separate earlier step' do
        # The reassignment must run as part of destroy's own before_destroy
        # chain, not beforehand in an already-committed transaction - that
        # earlier design reopened the exact race this exists to close (see
        # EE::User's before_destroy callback and its comment).
        expect(::ProtectedEnvironment).to receive(:reassign_sole_user_approver).and_wrap_original do |method, *args|
          expect(user.destroyed?).to be(false)
          method.call(*args)
        end

        operation
      end

      it 'audit logs the approval rule reassignment' do
        allow(::Gitlab::Audit::Auditor).to receive(:audit)

        operation

        expect(::Gitlab::Audit::Auditor).to have_received(:audit).with(
          name: 'protected_environment_approval_rule_reassigned',
          author: admin,
          scope: protected_environment.project,
          target: protected_environment,
          target_details: protected_environment.name,
          message: "Sole approver #{user.username} was permanently deleted; " \
            "approval rule reassigned to require any Maintainer's approval",
          additional_details: {
            action: 'reassign_sole_approver',
            removed_user_id: user.id,
            protected_environment_id: protected_environment.id,
            new_access_level: Gitlab::Access::MAINTAINER
          }
        )
      end

      context 'when other approvers remain on the protected environment' do
        before do
          create(:protected_environment_approval_rule, protected_environment: protected_environment,
            user: create(:user))
        end

        it 'does not audit log a reassignment that never happened' do
          allow(::Gitlab::Audit::Auditor).to receive(:audit)

          operation

          expect(::Gitlab::Audit::Auditor).not_to have_received(:audit).with(hash_including(
            name: 'protected_environment_approval_rule_reassigned'))
        end
      end
    end
  end
end
