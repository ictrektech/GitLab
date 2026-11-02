# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::AddServiceAccountToProjectService, feature_category: :ai_catalog_curation do
  let_it_be(:current_user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be_with_refind(:project) { create(:project, group: group) }
  let_it_be(:service_account) { create(:service_account, provisioned_by_group: group) }

  subject(:execute) { described_class.new(service_account, project, current_user: current_user).execute }

  describe '#execute' do
    it 'adds the service account to the project as a Developer', :aggregate_failures do
      expect(execute).to be_success

      member = project.member(service_account)
      expect(member.access_level).to eq(Gitlab::Access::DEVELOPER)
      expect(member.created_by).to eq(current_user)
    end

    it 'lets later permission checks in the same request see the new membership', :request_store do
      expect(project.team.member?(service_account)).to be(false)

      execute

      expect(project.team.member?(service_account, Gitlab::Access::DEVELOPER)).to be(true)
    end

    context 'when the service account is already a member with a lower role' do
      before_all do
        project.add_reporter(service_account)
      end

      it 'keeps the existing role' do
        expect(execute).to be_success

        expect(project.member(service_account).access_level).to eq(Gitlab::Access::REPORTER)
      end
    end

    context 'when the lock cannot be obtained' do
      before do
        allow_next_instance_of(Ai::ServiceAccountProjectMemberBulkAddService) do |instance|
          allow(instance).to receive(:execute).and_raise(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
        end
      end

      it 'returns an error' do
        expect(execute).to be_error.and have_attributes(reason: :failed_to_obtain_lock)
      end

      it 'lets later permission checks see a membership added by the lock holder', :request_store do
        expect(project.team.member?(service_account)).to be(false)

        ProjectMember.insert({
          source_id: project.id, source_type: 'Project', user_id: service_account.id,
          access_level: Gitlab::Access::DEVELOPER, notification_level: NotificationSetting.levels[:global],
          member_namespace_id: project.project_namespace_id, type: 'ProjectMember', state: Member::STATE_ACTIVE
        })
        ProjectAuthorization.insert({
          user_id: service_account.id, project_id: project.id, access_level: Gitlab::Access::DEVELOPER, is_unique: true
        })

        execute

        expect(project.team.member?(service_account)).to be(true)
      end
    end
  end
end
