# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::ProcessAutoMergeFromEventWorker, feature_category: :code_review_workflow do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, merge_user: user) }
  let(:merge_request_id) { merge_request.id }

  let(:data) { { current_user_id: user.id, merge_request_id: merge_request_id, approved_at: Time.current.iso8601 } }

  it_behaves_like 'process auto merge from event worker' do
    let(:event) { MergeRequests::ApprovedEvent.new(data: data) }
  end

  it_behaves_like 'process auto merge from event worker' do
    let(:event) { ::MergeRequests::UnblockedStateEvent.new(data: data) }
  end

  it_behaves_like 'process auto merge from event worker' do
    let(:event) { ::MergeRequests::ExternalStatusCheckPassedEvent.new(data: data) }
  end

  it_behaves_like 'process auto merge from event worker' do
    let(:event) { ::MergeRequests::OverrideRequestedChangesStateEvent.new(data: data) }
  end

  it_behaves_like 'process auto merge from event worker' do
    let(:event) { MergeRequests::AutoMerge::TitleDescriptionUpdateEvent.new(data: data) }
  end

  describe 'ViolationsUpdatedEvent subscription' do
    let_it_be_with_reload(:auto_merge_request) do
      create(:merge_request, :merge_when_checks_pass,
        source_project: project, source_branch: 'auto-merge', merge_user: user)
    end

    let(:event) do
      ::MergeRequests::ViolationsUpdatedEvent.new(
        data: { merge_request_id: auto_merge_request.id, project_id: project.id }
      )
    end

    it_behaves_like 'subscribes to event'

    context 'when auto-merge is not enabled' do
      before do
        auto_merge_request.update_column(:auto_merge_enabled, false)
      end

      it_behaves_like 'ignores the published event'

      context 'when auto_merge_process_violations_guard is disabled' do
        before do
          stub_feature_flags(auto_merge_process_violations_guard: false)
        end

        it_behaves_like 'subscribes to event'
      end
    end
  end
end
