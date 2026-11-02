# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::AnalyzersStatus::ProcessDeletedEventsWorker, feature_category: :security_asset_inventories, type: :job do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }

  let(:event) do
    ::Projects::ProjectDeletedEvent.new(data: {
      project_id: project.id,
      namespace_id: group.id,
      root_namespace_id: group.id
    })
  end

  it_behaves_like 'worker with data consistency', described_class, data_consistency: :sticky
  it_behaves_like 'subscribes to event'

  subject(:use_event) { consume_event(subscriber: described_class, event: event) }

  context 'when the project exists' do
    it 'deletes the project statuses and schedules the namespace recalculation', :aggregate_failures do
      expect(::Security::AnalyzerProjectStatus).to receive_message_chain(:by_projects, :delete_all)
      expect(Security::AnalyzerNamespaceStatuses::RecalculateWorker)
        .to receive(:perform_in).with(
          Security::AnalyzerNamespaceStatuses::RecalculateWorker::RECALCULATE_DELAY, group.id
        )
      expect(Security::AnalyzerNamespaceStatuses::RecalculateService).not_to receive(:execute)

      use_event
    end
  end

  context 'when the project does not exist' do
    before do
      allow(Project).to receive(:find_by_id).and_return(nil)
      allow(Group).to receive(:find_by_id).and_return(nil)
    end

    it 'does not schedule the namespace recalculation', :aggregate_failures do
      expect(::Security::AnalyzerProjectStatus).not_to receive(:by_projects)
      expect(Security::AnalyzerNamespaceStatuses::RecalculateWorker).not_to receive(:perform_in)

      use_event
    end
  end
end
