# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ability, feature_category: :system_access do
  describe '.filter_allowed', :request_store do
    context 'with group level work items' do
      let_it_be(:user) { create(:user) }
      let_it_be(:guest_group) { create(:group, :private, guests: user) }
      let_it_be(:other_group) { create(:group, :private) }

      let_it_be(:readable_work_item) { create(:work_item, :group_level, namespace: guest_group) }
      let_it_be(:confidential_work_item) { create(:work_item, :group_level, :confidential, namespace: guest_group) }
      let_it_be(:other_group_work_item) { create(:work_item, :group_level, namespace: other_group) }

      let(:groups) { [guest_group, other_group] }

      before do
        stub_licensed_features(epics: true)
      end

      def readable_work_items
        described_class.filter_allowed(user, :read_work_item, WorkItem.where(namespace: groups).to_a)
      end

      it 'returns the same subjects as checking each one' do
        expected = WorkItem.where(namespace: groups).select do |work_item|
          described_class.allowed?(user, :read_work_item, work_item)
        end
        RequestStore.clear!

        expect(readable_work_items).to match_array(expected)
        expect(expected).to contain_exactly(readable_work_item)
      end

      it 'does not query per subject' do
        control = ActiveRecord::QueryRecorder.new { readable_work_items }

        RequestStore.clear!
        create_list(:work_item, 2, :group_level, namespace: guest_group)
        new_group = create(:group, :private, guests: user)
        create_list(:work_item, 2, :group_level, namespace: new_group)
        groups << new_group

        expect { readable_work_items }.not_to exceed_query_limit(control)
      end

      context 'with project level work items in the same list' do
        let_it_be(:guest_group_project) { create(:project, :private, group: guest_group) }
        let_it_be(:other_group_project) { create(:project, :private, group: other_group) }
        let_it_be(:project_work_item) { create(:work_item, project: guest_group_project) }
        let_it_be(:other_project_work_item) { create(:work_item, project: other_group_project) }

        let(:work_items) do
          WorkItem.where(namespace: groups)
            .or(WorkItem.where(project: [guest_group_project, other_group_project])).to_a
        end

        it 'returns the same subjects as checking each one' do
          expected = work_items.select { |work_item| described_class.allowed?(user, :read_work_item, work_item) }
          RequestStore.clear!

          expect(described_class.filter_allowed(user, :read_work_item, work_items)).to match_array(expected)
          expect(expected).to contain_exactly(readable_work_item, project_work_item)
        end
      end

      context 'when the user is blocked' do
        let_it_be(:user) { create(:user, :blocked) }

        before_all do
          guest_group.add_guest(user)
        end

        it 'returns no work items' do
          expect(readable_work_items).to be_empty
        end
      end
    end
  end

  describe '.filter_allowed with project level issues', :request_store do
    let_it_be(:user) { create(:user) }
    let_it_be(:guest_issue) { create(:issue, project: create(:project, :private, guests: user)) }
    let_it_be(:public_issue) { create(:issue, project: create(:project, :public, group: create(:group, :public))) }

    # In FOSS, checks for a short list read less, so the preload can cost a few more queries there.
    it 'does not query more than checking each one for a short list' do
      # Callers load issues with their projects, like Banzai's IssueParser does.
      load_issues = -> do
        Issue.where(id: [guest_issue, public_issue]).preload(project: [:namespace, :project_feature, :route]).to_a
      end

      allow(IssuePolicy).to receive(:preload_for_batch_checks)
      control = ActiveRecord::QueryRecorder.new { described_class.filter_allowed(user, :read_issue, load_issues.call) }

      RequestStore.clear!
      allow(IssuePolicy).to receive(:preload_for_batch_checks).and_call_original

      expect { described_class.filter_allowed(user, :read_issue, load_issues.call) }.not_to exceed_query_limit(control)
    end
  end

  describe '.issues_readable_by_user' do
    context 'with IP restrictions' do
      let_it_be(:group) { create(:group) }
      let_it_be(:project) { create(:project, group: group) }
      let_it_be(:user) { create(:user, developer_of: group) }

      let_it_be(:issues) { create_list(:issue, 2, project: project) }

      before_all do
        create(:ip_restriction, group: group, range: '192.168.0.0/24')
      end

      before do
        stub_licensed_features(group_ip_restriction: true)
      end

      it 'returns issues when IP is within the configured range' do
        allow(Gitlab::IpAddressState).to receive(:current).and_return('192.168.0.2')

        expect(described_class.issues_readable_by_user(issues, user)).to match_array(issues)
      end

      it 'excludes issues when IP is outside the configured range' do
        allow(Gitlab::IpAddressState).to receive(:current).and_return('10.0.1.1')

        expect(described_class.issues_readable_by_user(issues, user)).to be_empty
      end
    end
  end
end
