# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ServiceAccountProjectMemberBulkAddService, feature_category: :ai_catalog_curation do
  include ExclusiveLeaseHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:project1) { create(:project) }
  let_it_be(:project2) { create(:project) }
  let_it_be(:service_account1) { create(:user, :service_account) }
  let_it_be(:service_account2) { create(:user, :service_account) }

  let(:memberships) do
    [
      { project: project1, service_account: service_account1 },
      { project: project2, service_account: service_account1 },
      { project: project1, service_account: service_account2 }
    ]
  end

  subject(:execute) { described_class.new(memberships, current_user: current_user).execute }

  describe '#execute' do
    it 'adds each service account as a developer of its project' do
      expect { execute }.to change { ProjectMember.count }.by(3)

      expect(ProjectMember.for_users([service_account1, service_account2]).pluck(:source_id, :user_id))
        .to contain_exactly(
          [project1.id, service_account1.id],
          [project2.id, service_account1.id],
          [project1.id, service_account2.id]
        )
      expect(ProjectMember.find_by(source: project1, user: service_account1)).to have_attributes(
        access_level: Gitlab::Access::DEVELOPER,
        created_by_id: current_user.id,
        member_namespace_id: project1.project_namespace_id
      )
    end

    it 'adds a developer project authorization for each membership' do
      execute

      expect(ProjectAuthorization.for_user([service_account1, service_account2]).pluck(:project_id, :user_id,
        :access_level)).to contain_exactly(
          [project1.id, service_account1.id, Gitlab::Access::DEVELOPER],
          [project2.id, service_account1.id, Gitlab::Access::DEVELOPER],
          [project1.id, service_account2.id, Gitlab::Access::DEVELOPER]
        )
    end

    it 'checks existing memberships on the primary' do
      expect(::Gitlab::Database::LoadBalancing::SessionMap.current(ProjectMember.load_balancer))
        .to receive(:use_primary).at_least(:once).and_call_original

      execute
    end

    it 'returns the added memberships' do
      expect(execute).to be_success
      expect(execute.payload[:added]).to match_array(memberships)
    end

    context 'when a service account is already a member of the project' do
      before do
        create(:project_member, :reporter, source: project1, user: service_account1)
      end

      it 'skips that membership without changing its access level' do
        expect { execute }.to change { ProjectMember.count }.by(2)

        expect(ProjectMember.find_by(source: project1, user: service_account1).access_level)
          .to eq(Gitlab::Access::REPORTER)
      end

      it 'does not return the skipped membership' do
        expect(execute.payload[:added]).to contain_exactly(
          { project: project2, service_account: service_account1 },
          { project: project1, service_account: service_account2 }
        )
      end
    end

    context 'when inserting the project authorizations fails' do
      before do
        allow(ProjectAuthorization).to receive(:insert_all).and_raise(ActiveRecord::StatementInvalid)
      end

      it 'does not keep the inserted members' do
        expect { execute }.to raise_error(ActiveRecord::StatementInvalid).and not_change { ProjectMember.count }
      end
    end

    context 'when every service account is already a member of its project' do
      before do
        memberships.each do |membership|
          create(:project_member, :developer, source: membership[:project], user: membership[:service_account])
        end
      end

      it 'does not insert anything' do
        expect(ProjectMember).not_to receive(:insert_all)
        expect(ProjectAuthorization).not_to receive(:insert_all)

        expect(execute.payload[:added]).to be_empty
      end
    end

    context 'when another job holds the lock for a service account' do
      before do
        stub_const("#{described_class}::LOCK_RETRIES", 0)
        stub_exclusive_lease_taken(
          "ai:service_account_project_member_bulk_add:#{service_account1.id}", timeout: 1.minute
        )
      end

      it 'raises without adding members for that service account' do
        expect { execute }.to raise_error(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)

        expect(ProjectMember.for_users(service_account1)).to be_empty
      end
    end

    context 'when the same membership is passed more than once' do
      let(:memberships) do
        [
          { project: project1, service_account: service_account1 },
          { project: project1, service_account: service_account1 }
        ]
      end

      it 'adds it once' do
        expect { execute }.to change { ProjectMember.count }.by(1)
      end
    end

    context 'when memberships span more than one batch' do
      before do
        stub_const("#{described_class}::BATCH_SIZE", 2)
      end

      it 'adds all of them' do
        expect { execute }.to change { ProjectMember.count }.by(3)
      end
    end

    context 'without a current user' do
      subject(:execute) { described_class.new(memberships).execute }

      it 'adds the members without a creator' do
        execute

        expect(ProjectMember.find_by(source: project1, user: service_account1).created_by_id).to be_nil
      end
    end

    context 'when there are no memberships' do
      let(:memberships) { [] }

      it 'adds nothing' do
        expect { execute }.not_to change { ProjectMember.count }
        expect(execute.payload[:added]).to be_empty
      end
    end
  end
end
