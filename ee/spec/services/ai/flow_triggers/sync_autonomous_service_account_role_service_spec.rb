# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggers::SyncAutonomousServiceAccountRoleService, feature_category: :dap_triggers do
  let_it_be(:group) { create(:group) }
  let_it_be_with_reload(:project) { create(:project, group: group) }
  let_it_be(:flow_account) { create(:service_account, provisioned_by_group: group, developer_of: project) }
  let_it_be(:dedicated_account) { create(:service_account, provisioned_by_group: group, developer_of: project) }
  let_it_be(:maintainer) { create(:user, maintainer_of: project) }

  let_it_be(:parent_item_consumer) do
    create(:ai_catalog_item_consumer, :parent_item_consumer, group: group, service_account: flow_account)
  end

  let_it_be(:item_consumer) do
    create(:ai_catalog_item_consumer, :for_flow,
      project: project, item: parent_item_consumer.item, parent_item_consumer: parent_item_consumer)
  end

  # No actor: this is how a scheduled run calls it.
  let(:current_user) { nil }
  let(:service_account_id) { dedicated_account.id }

  subject(:execute) do
    described_class.new(
      project: project,
      item_consumer: item_consumer,
      service_account_id: service_account_id,
      current_user: current_user
    ).execute
  end

  def dedicated_level
    project.project_members.reset
    project.member(dedicated_account)&.access_level
  end

  describe '#execute' do
    it 'looks the member up by user rather than by id' do
      project.member(dedicated_account).update!(access_level: Gitlab::Access::REPORTER)
      project.project_members.load

      result = execute

      expect(result).to be_success
      expect(result.payload).to include(
        changed: false,
        access_level: Gitlab::Access::DEVELOPER,
        current_access_level: Gitlab::Access::REPORTER
      )
    end

    it 'reports no change when the roles already match' do
      expect(execute).to be_success
      expect(execute.payload[:changed]).to be(false)
    end

    it 'follows the flow account and reports the new role' do
      project.member(flow_account).update!(access_level: Gitlab::Access::REPORTER)

      result = execute

      expect(result).to be_success
      expect(result.payload).to eq(
        { changed: true,
          access_level: Gitlab::Access::REPORTER,
          current_access_level: Gitlab::Access::REPORTER,
          effective_access_level: Gitlab::Access::REPORTER }
      )
      expect(dedicated_level).to eq(Gitlab::Access::REPORTER)
    end

    context 'when the account also holds an ancestor group role' do
      it 'reports effective access after a successful re-level' do
        group.add_member(dedicated_account, Gitlab::Access::GUEST)
        project.member(flow_account).update!(access_level: Gitlab::Access::REPORTER)

        expect(execute.payload).to include(
          changed: true,
          access_level: Gitlab::Access::REPORTER,
          current_access_level: Gitlab::Access::REPORTER,
          effective_access_level: Gitlab::Access::REPORTER
        )
      end

      it 'reports it when the row already matches and nothing is written' do
        group.add_member(dedicated_account, Gitlab::Access::MAINTAINER)

        expect(execute.payload).to include(
          changed: false,
          access_level: Gitlab::Access::DEVELOPER,
          current_access_level: Gitlab::Access::DEVELOPER,
          effective_access_level: Gitlab::Access::MAINTAINER
        )
      end
    end

    context 'when a shared group grants the account higher access' do
      let_it_be(:shared_group) { create(:group) }

      before do
        shared_group.add_member(dedicated_account, Gitlab::Access::MAINTAINER)
        create(:project_group_link, project: project, group: shared_group,
          group_access: Gitlab::Access::MAINTAINER)
      end

      it 'reports the access the share grants' do
        expect(execute.payload).to include(
          changed: false,
          access_level: Gitlab::Access::DEVELOPER,
          current_access_level: Gitlab::Access::DEVELOPER,
          effective_access_level: Gitlab::Access::MAINTAINER
        )
      end
    end

    describe 'acting without an actor' do
      it 'applies a demotion' do
        project.member(flow_account).update!(access_level: Gitlab::Access::REPORTER)

        expect(execute.payload[:changed]).to be(true)
        expect(dedicated_level).to eq(Gitlab::Access::REPORTER)
      end

      it 'skips a promotion' do
        project.member(flow_account).update!(access_level: Gitlab::Access::MAINTAINER)

        expect(execute.payload[:changed]).to be(false)
        expect(dedicated_level).to eq(Gitlab::Access::DEVELOPER)
      end

      it 'skips a move to a role outside the hierarchy' do
        project.member(flow_account).update!(access_level: Gitlab::Access::PLANNER)

        expect(execute.payload[:changed]).to be(false)
        expect(dedicated_level).to eq(Gitlab::Access::DEVELOPER)
      end

      it 'does not re-add a membership the account lost' do
        project.member(dedicated_account).destroy!

        expect(execute).to be_success
        expect(execute.payload[:changed]).to be(false)
        expect(dedicated_level).to be_nil
      end
    end

    context 'with an actor' do
      let(:current_user) { create(:user, maintainer_of: project) }

      it 'restores a membership the account lost' do
        project.member(dedicated_account).destroy!

        expect(execute).to be_success
        expect(dedicated_level).to eq(Gitlab::Access::DEVELOPER)
      end

      it 'applies a promotion the actor may assign' do
        project.member(flow_account).update!(access_level: Gitlab::Access::MAINTAINER)

        expect(execute.payload[:changed]).to be(true)
        expect(dedicated_level).to eq(Gitlab::Access::MAINTAINER)
      end
    end

    it 'asks for a synchronous authorization recalculation when it writes' do
      project.member(flow_account).update!(access_level: Gitlab::Access::REPORTER)

      expect(project.team).to receive(:add_member).with(
        dedicated_account,
        Gitlab::Access::REPORTER,
        current_user: nil,
        immediately_sync_authorizations: true
      ).and_call_original

      execute
    end

    context 'when there is no role to mirror' do
      before do
        project.member(flow_account).destroy!
      end

      it 'reports no change rather than failing' do
        expect(execute).to be_success
        expect(execute.payload[:changed]).to be(false)
        expect(dedicated_level).to eq(Gitlab::Access::DEVELOPER)
      end

      # A nil target is what says "the flow holds nothing", and the payload
      # still reports what the account has so a run can refuse on it.
      it 'reports a nil target, and what the account still holds' do
        expect(execute.payload).to eq(
          { changed: false,
            access_level: nil,
            current_access_level: Gitlab::Access::DEVELOPER,
            effective_access_level: Gitlab::Access::DEVELOPER }
        )
      end

      context 'and the dedicated account holds nothing either' do
        before do
          project.member(dedicated_account).destroy!
        end

        it 'reports no access to compare' do
          expect(execute.payload[:current_access_level]).to be_nil
        end
      end
    end

    context 'when the flow account holds Owner' do
      before do
        project.member(flow_account).update!(access_level: Gitlab::Access::OWNER)
      end

      it 'refuses to mirror it' do
        expect(execute).to be_success
        expect(execute.payload[:changed]).to be(false)
        expect(dedicated_level).to eq(Gitlab::Access::DEVELOPER)
      end
    end

    context 'with an actor who cannot assign the role' do
      let(:current_user) { create(:user, maintainer_of: project) }

      before do
        project.member(flow_account).update!(access_level: Gitlab::Access::PLANNER)
      end

      it 'leaves the membership alone' do
        expect(execute).to be_success
        expect(execute.payload[:changed]).to be(false)
        expect(dedicated_level).to eq(Gitlab::Access::DEVELOPER)
      end
    end

    context 'when the membership write fails' do
      let(:member) { project.member(dedicated_account) }

      before do
        project.member(flow_account).update!(access_level: Gitlab::Access::REPORTER)

        errored = member
        errored.errors.add(:base, 'membership refused')

        allow(project.team).to receive(:add_member).and_return(errored)
      end

      it 'logs the failure once, with the project and account' do
        expect(Gitlab::AppLogger).to receive(:error).with(
          message: 'Failed to sync the autonomous service account role',
          Labkit::Fields::GL_PROJECT_ID => project.id,
          service_account_id: dedicated_account.id,
          error_message: 'membership refused'
        )

        execute
      end

      # The caller uses these to tell a refused demotion, which must stop a run,
      # from a refused promotion, which only under-privileges it.
      it 'returns both levels so the caller can tell the direction' do
        allow(Gitlab::AppLogger).to receive(:error)

        result = execute

        expect(result).to be_error
        expect(result.payload).to eq(
          { changed: false,
            access_level: Gitlab::Access::REPORTER,
            current_access_level: Gitlab::Access::DEVELOPER,
            effective_access_level: Gitlab::Access::DEVELOPER }
        )
      end

      context 'and the member path returns nothing at all' do
        before do
          allow(project.team).to receive(:add_member).and_return(nil)
        end

        it 'falls back to a generic message' do
          allow(Gitlab::AppLogger).to receive(:error)

          expect(execute).to be_error
          expect(execute.message).to eq('Failed to sync the service account role')
        end
      end

      context 'and the account has no membership to report' do
        # An actor, so a missing membership is a re-add rather than a skip.
        let(:current_user) { maintainer }

        before do
          project.member(dedicated_account).destroy!

          refused = ProjectMember.new
          refused.errors.add(:base, 'seat limit reached')
          allow(project.team).to receive(:add_member).and_return(refused)
        end

        it 'reports no current access level' do
          allow(Gitlab::AppLogger).to receive(:error)

          result = execute

          expect(result).to be_error
          expect(result.payload[:current_access_level]).to be_nil
        end
      end
    end

    describe 'absent or unusable input' do
      context 'without an item consumer' do
        let(:item_consumer) { nil }

        it 'reports no role to mirror and writes nothing' do
          expect(execute).to be_success
          expect(execute.payload).to include(changed: false, access_level: nil)
          expect(dedicated_level).to eq(Gitlab::Access::DEVELOPER)
        end
      end

      context 'when the service account no longer exists' do
        let(:service_account_id) { non_existing_record_id }

        it 'reports no effective access' do
          expect(execute).to be_success
          expect(execute.payload[:effective_access_level]).to be_nil
        end

        it 'does not look up a member for an account that is not there' do
          project.project_members.load

          expect(execute).to be_success
        end
      end

      context 'when the flow account role is outside the assignable range' do
        before do
          allow(item_consumer).to receive(:active_service_account_access_level)
            .and_return(Gitlab::Access::MINIMAL_ACCESS)
        end

        it 'refuses to mirror it' do
          expect(execute.payload[:changed]).to be(false)
          expect(dedicated_level).to eq(Gitlab::Access::DEVELOPER)
        end
      end
    end
  end
end
