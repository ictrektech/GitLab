# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Gitlab::Search::RecentWorkItems, feature_category: :global_search do
  describe 'group-level work items' do
    let_it_be(:user) { create(:user) }
    let_it_be(:group) { create(:group, :public) }
    let_it_be(:project) { create(:project, namespace: group) }
    let_it_be(:project_work_item) { create(:work_item, project: project, title: 'Project task') }

    let(:parent_type) { :group }
    let(:recent_work_items_service) { described_class.new(user: user) }

    def create_item(content:, parent:)
      create(:work_item, :group_level, namespace: parent, title: content)
    end

    before_all do
      group.add_developer(user)
    end

    before do
      stub_licensed_features(epics: true)
    end

    # Use shared example for basic functionality
    it_behaves_like 'search recent items'

    # Test unique behavior: backwards compatibility with RecentIssues
    describe 'RecentIssues backwards compatibility', :clean_gitlab_redis_shared_state do
      it 'shares Redis key with RecentIssues for project-level work items' do
        recent_issues = ::Gitlab::Search::RecentIssues.new(user: user)
        recent_work_items_service.log_view(project_work_item)

        # Both services should be able to retrieve project-level work items
        expect(recent_issues.search('')).to include(project_work_item)
        expect(recent_work_items_service.search('')).to include(project_work_item)
      end
    end

    # Test unique behavior: mixed project and group-level work items
    describe 'mixed work item levels', :clean_gitlab_redis_shared_state do
      let_it_be(:group_work_item) { create(:work_item, :group_level, namespace: group, title: 'Group task') }

      before do
        recent_work_items_service.log_view(project_work_item)
        recent_work_items_service.log_view(group_work_item)
      end

      it 'returns both project and group-level work items' do
        results = recent_work_items_service.search('')
        expect(results).to contain_exactly(group_work_item, project_work_item)
      end

      it 'searches group-level work items by title' do
        results = recent_work_items_service.search('Group')
        expect(results).to contain_exactly(group_work_item)
      end

      it 'searches project-level work items by title' do
        results = recent_work_items_service.search('Project')
        expect(results).to contain_exactly(project_work_item)
      end
    end

    describe 'synced epic work item with external authorization enabled',
      :clean_gitlab_redis_shared_state, :request_store do
      include ExternalAuthorizationServiceHelpers

      let_it_be(:epic) { create(:epic, :with_synced_work_item, group: group) }
      let_it_be(:epic_work_item) { epic.work_item }
      let_it_be(:other_epics) { create_list(:epic, 2, :with_synced_work_item, group: group) }

      before do
        recent_work_items_service.log_view(epic_work_item)
        enable_external_authorization_service_check
      end

      it 'excludes the synced epic work item from results' do
        expect(recent_work_items_service.search('')).not_to include(epic_work_item)
      end

      it 'does not have N+1 queries when filtering multiple synced epic work items' do
        recent_work_items_service.search('') # warm up
        ::Gitlab::SafeRequestStore.clear!

        control = ActiveRecord::QueryRecorder.new(skip_cached: false) { recent_work_items_service.search('') }

        other_epics.each { |other_epic| recent_work_items_service.log_view(other_epic.work_item) }
        ::Gitlab::SafeRequestStore.clear!

        expect { recent_work_items_service.search('') }.not_to exceed_all_query_limit(control)
      end
    end
  end
end
