# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequests::ProcessAutoMergeFromEventWorker, feature_category: :code_review_workflow do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, merge_user: user) }
  let(:merge_request_id) { merge_request.id }

  let(:data) { { current_user_id: user.id, merge_request_id: merge_request_id, approved_at: Time.current.iso8601 } }

  it_behaves_like 'process auto merge from event worker' do
    let(:event) { ::MergeRequests::DiscussionsResolvedEvent.new(data: data) }
  end

  it_behaves_like 'process auto merge from event worker' do
    let(:event) { ::MergeRequests::DraftStateChangeEvent.new(data: data) }
  end

  it_behaves_like 'process auto merge from event worker' do
    let(:data) { { merge_request_id: merge_request_id, project_id: project.id } }
    let(:event) { ::MergeRequests::PipelineCreationCompletedEvent.new(data: data) }

    before do
      merge_request.update!(auto_merge_enabled: true)
    end
  end

  describe 'PipelineCreationCompletedEvent subscription' do
    let_it_be_with_reload(:auto_merge_request) do
      create(:merge_request, :merge_when_checks_pass,
        source_project: project, source_branch: 'auto-merge', merge_user: user)
    end

    let(:pipeline_id) { nil }
    let(:event) do
      ::MergeRequests::PipelineCreationCompletedEvent.new(
        data: { merge_request_id: auto_merge_request.id, project_id: project.id, pipeline_id: pipeline_id }.compact
      )
    end

    it_behaves_like 'subscribes to event'

    it 'checks for the merge request on the primary' do
      lb_session = ::Gitlab::Database::LoadBalancing::SessionMap.current(MergeRequest.load_balancer)
      allow(::Gitlab::Database::LoadBalancing::SessionMap).to receive(:current).and_call_original
      allow(::Gitlab::Database::LoadBalancing::SessionMap)
        .to receive(:current).with(MergeRequest.load_balancer).and_return(lb_session)
      expect(lb_session).to receive(:use_primary).and_call_original

      ::Gitlab::EventStore.publish(event)
    end

    context 'when a pipeline was created' do
      let(:pipeline_id) { non_existing_record_id }

      it_behaves_like 'ignores the published event'
    end

    context 'when the merge request is closed' do
      before do
        auto_merge_request.update_column(:state_id, MergeRequest.available_states[:closed])
      end

      it_behaves_like 'ignores the published event'
    end

    context 'when auto-merge is not enabled' do
      before do
        auto_merge_request.update_column(:auto_merge_enabled, false)
      end

      it_behaves_like 'ignores the published event'

      context 'when auto_merge_process_pipeline_creation_guard is disabled' do
        before do
          stub_feature_flags(auto_merge_process_pipeline_creation_guard: false)
        end

        it_behaves_like 'subscribes to event'
      end
    end
  end
end
