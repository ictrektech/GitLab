# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DependencyManagement::SecurityUpdate::TracksAutoRemediationMrEvent,
  feature_category: :dependency_management do
  let_it_be(:project) { create(:project) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

  let(:worker_class) do
    Class.new do
      def self.name
        'TracksAutoRemediationMrEventTestWorker'
      end

      include ApplicationWorker
      include DependencyManagement::SecurityUpdate::TracksAutoRemediationMrEvent

      const_set(:EVENT_NAME, 'merge_dependency_management_auto_remediation_mr')
    end
  end

  let(:event) { MergeRequests::MergedEvent.new(data: { merge_request_id: merge_request.id }) }

  context 'when the including worker does not define remediation_state_for' do
    it 'tracks the event and leaves the remediation rows alone' do
      worker = worker_class.new

      expect(worker).to receive(:track_internal_event)
        .with('merge_dependency_management_auto_remediation_mr', hash_including(project: project))
      expect(DependencyManagement::Remediation).not_to receive(:transition_for_merge_request)

      worker.handle_event(event)
    end
  end
end
