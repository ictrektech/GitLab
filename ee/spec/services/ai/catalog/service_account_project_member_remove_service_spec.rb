# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::ServiceAccountProjectMemberRemoveService, feature_category: :ai_catalog_curation do
  let_it_be(:current_user) { create(:user) }
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:needed_project) { create(:project, group: group) }
  let_it_be(:project_consumer) { create(:ai_catalog_item_consumer, :child_item_consumer, project: needed_project) }
  let_it_be(:service_account) { project_consumer.parent_item_consumer.service_account }

  let(:memberships) { ProjectMember.in_projects([project.id, needed_project.id]).with_user(service_account) }

  subject(:execute) do
    described_class.new(memberships, current_user: current_user, skip_authorization: true).execute
  end

  before_all do
    [project, needed_project].each { |p| p.add_developer(service_account) }
  end

  describe '#execute' do
    it 'removes memberships that are no longer needed and keeps the needed ones', :aggregate_failures do
      expect(execute).to be_success

      expect(project.member(service_account)).to be_nil
      expect(needed_project.member(service_account)).to be_present
    end

    it 'passes the options to Members::DestroyService' do
      expect(Members::DestroyService).to receive(:new)
        .with(an_instance_of(ProjectMember), current_user: current_user, skip_authorization: true)
        .and_call_original

      execute
    end

    context 'when a membership cannot be removed' do
      before do
        allow_next_instance_of(Members::DestroyService) do |instance|
          allow(instance).to receive(:execute) do
            instance.send(:member).errors.add(:base, 'Deletion failed')
          end
        end
      end

      it 'tracks the error' do
        expect(Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception).with(
          described_class::MemberDeletionError.new('Could not delete member: Deletion failed'),
          { project_id: project.id, service_account_id: service_account.id }
        )

        execute
      end
    end
  end
end
