# frozen_string_literal: true

require 'spec_helper'

RSpec.describe NotificationRecipients::BuildService, feature_category: :team_planning do
  let(:service) { described_class }
  let(:assignee) { create(:user) }
  let(:project) { create(:project, :public) }
  let(:other_projects) { create_list(:project, 5, :public) }

  describe '.notifiable_users' do
    let_it_be(:group) { create(:group, :public) }
    let_it_be(:subgroup) { create(:group, :public, parent: group) }
    let_it_be(:group_project) { create(:project, :public, group: subgroup) }

    def notifiable_users(users)
      service.notifiable_users(User.id_in(users).to_a, :watch, project: group_project)
    end

    def create_users(count)
      create_list(:user, count).each do |user|
        create(:notification_setting, source: group_project, user: user, level: :global)
        create(:notification_setting, source: group, user: user, level: :watch)
        create(:notification_setting, source: nil, user: user, level: :participating)
      end
    end

    it 'avoids N+1 queries on notification settings', :request_store do
      users = create_users(2)
      control = ActiveRecord::QueryRecorder.new { notifiable_users(users) }

      users += create_users(3)

      expect { notifiable_users(users) }.not_to exceed_query_limit(control)
    end

    it 'uses the project, then the closest group, then the global notification setting' do
      project_user, group_user, global_user, excluded_user = create_list(:user, 4)

      create(:notification_setting, source: group_project, user: project_user, level: :watch)
      create(:notification_setting, source: group, user: project_user, level: :disabled)
      create(:notification_setting, source: group_project, user: group_user, level: :global)
      create(:notification_setting, source: subgroup, user: group_user, level: :watch)
      create(:notification_setting, source: group, user: group_user, level: :disabled)
      create(:notification_setting, source: nil, user: global_user, level: :watch)
      create(:notification_setting, source: group, user: excluded_user, level: :disabled)
      create(:notification_setting, source: nil, user: excluded_user, level: :watch)

      expect(notifiable_users([project_user, group_user, global_user, excluded_user]))
        .to contain_exactly(project_user, group_user, global_user)
    end

    it 'does not leave the scoped notification settings loaded' do
      user = create(:user)

      service.notifiable_users([user], :watch, project: group_project)

      expect(user.association(:notification_settings)).not_to be_loaded
    end
  end

  describe '#build_new_note_recipients' do
    let(:issue) { create(:issue, project: project, assignees: [assignee]) }
    let(:note) { create(:note_on_issue, noteable: issue, project_id: issue.project_id) }

    shared_examples 'no N+1 queries' do
      it 'avoids N+1 queries', :request_store do
        # existing N+1 due to multiple users having to be looked up in the project_authorizations table
        threshold = project.private? ? 1 : 0

        create_user

        control = ActiveRecord::QueryRecorder.new do
          service.build_new_note_recipients(note)
        end

        create_user

        expect { service.build_new_note_recipients(note) }.not_to exceed_query_limit(control).with_threshold(threshold)
      end
    end

    context 'when there are multiple watchers' do
      def create_user
        watcher = create(:user)
        create(:notification_setting, source: project, user: watcher, level: :watch)

        other_projects.each do |other_project|
          create(:notification_setting, source: other_project, user: watcher, level: :watch)
        end
      end

      include_examples 'no N+1 queries'
    end

    context 'when there are multiple subscribers' do
      def create_user
        subscriber = create(:user)
        issue.subscriptions.create!(user: subscriber, project: project, subscribed: true)
      end

      include_examples 'no N+1 queries'

      context 'when the project is private' do
        before do
          project.update!(visibility_level: Gitlab::VisibilityLevel::PRIVATE)
        end

        include_examples 'no N+1 queries'
      end
    end
  end

  describe '#build_new_review_recipients' do
    let(:merge_request) { create(:merge_request, source_project: project, target_project: project) }
    let(:review) { create(:review, merge_request: merge_request, project: project, author: merge_request.author) }
    let(:notes) { create_list(:note_on_merge_request, 3, review: review, noteable: review.merge_request, project: review.project) }

    shared_examples 'no N+1 queries' do
      it 'avoids N+1 queries', :request_store do
        # existing N+1 due to multiple users having to be looked up in the project_authorizations table
        threshold = project.private? ? 1 : 0

        create_user

        control = ActiveRecord::QueryRecorder.new do
          service.build_new_review_recipients(review)
        end

        create_user

        expect do
          service.build_new_review_recipients(review)
        end.not_to exceed_query_limit(control).with_threshold(threshold)
      end
    end

    context 'when there are multiple watchers' do
      def create_user
        watcher = create(:user)
        create(:notification_setting, source: project, user: watcher, level: :watch)

        other_projects.each do |other_project|
          create(:notification_setting, source: other_project, user: watcher, level: :watch)
        end
      end

      include_examples 'no N+1 queries'
    end

    context 'when there are multiple subscribers' do
      def create_user
        subscriber = create(:user)
        merge_request.subscriptions.create!(user: subscriber, project: project, subscribed: true)
      end

      include_examples 'no N+1 queries'

      context 'when the project is private' do
        before do
          project.update!(visibility_level: Gitlab::VisibilityLevel::PRIVATE)
        end

        include_examples 'no N+1 queries'
      end
    end
  end

  describe '#build_requested_review_recipients' do
    let(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

    before do
      merge_request.reviewers.push(assignee)
    end

    shared_examples 'no N+1 queries' do
      it 'avoids N+1 queries', :request_store do
        create_user

        service.build_requested_review_recipients(note)

        control = ActiveRecord::QueryRecorder.new do
          service.build_requested_review_recipients(note)
        end

        create_user

        expect { service.build_requested_review_recipients(note) }.not_to exceed_query_limit(control)
      end
    end
  end
end
