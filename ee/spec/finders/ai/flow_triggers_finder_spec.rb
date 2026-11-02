# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::FlowTriggersFinder, feature_category: :duo_agent_platform do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:project) { create(:project, :in_group) }

  let_it_be(:event_trigger) do
    create(:ai_flow_trigger, project: project, description: 'Bravo trigger', config_path: 'configs/review.yml',
      created_at: 3.days.ago, updated_at: 1.day.ago)
  end

  let_it_be(:inactive_trigger) do
    create(:ai_flow_trigger, :inactive, project: project, description: 'alpha trigger',
      event_types: [::Ai::FlowTrigger::EVENT_TYPES[:assign]], created_at: 2.days.ago, updated_at: 3.days.ago)
  end

  let_it_be(:scheduled_trigger) do
    item = create(:ai_catalog_flow, name: 'Weekly risk flow')
    consumer = create(:ai_catalog_item_consumer, :child_item_consumer, project: project, item: item)

    create(:ai_flow_trigger, :autonomous, project: project, ai_catalog_item_consumer: consumer,
      description: 'charlie trigger', created_at: 1.day.ago, updated_at: 2.days.ago)
  end

  let_it_be(:other_project_trigger) { create(:ai_flow_trigger) }

  subject(:triggers) { described_class.new(project, params).execute }

  where(:params, :expected) do
    {}                                                         | %i[scheduled_trigger inactive_trigger event_trigger]
    { ids: [] }                                                | []
    { kind: :scheduled }                                       | %i[scheduled_trigger]
    { kind: :event }                                           | %i[inactive_trigger event_trigger]
    { active: true }                                           | %i[scheduled_trigger event_trigger]
    { active: false }                                          | %i[inactive_trigger]
    { event_type: ::Ai::FlowTrigger::EVENT_TYPES[:assign] }    | %i[inactive_trigger]
    { search: 'BRAVO' }                                        | %i[event_trigger]
    { search: 'review' }                                       | %i[event_trigger]
    { search: 'weekly risk' }                                  | %i[scheduled_trigger]
    { search: '%' }                                            | []
    { sort: :name_asc }                                        | %i[inactive_trigger event_trigger scheduled_trigger]
    { sort: :name_desc }                                       | %i[scheduled_trigger event_trigger inactive_trigger]
    { sort: :created_asc }                                     | %i[event_trigger inactive_trigger scheduled_trigger]
    { sort: :updated_asc }                                     | %i[inactive_trigger scheduled_trigger event_trigger]
    { sort: :updated_desc }                                    | %i[event_trigger scheduled_trigger inactive_trigger]
  end

  with_them do
    it 'returns the matching triggers in order' do
      expect(triggers).to eq(expected.map { |name| public_send(name) })
    end
  end

  context 'when filtering by the merge request event type' do
    let_it_be(:merge_request_project) { create(:project) }

    let_it_be(:merge_request_trigger) do
      create(:ai_flow_trigger, project: merge_request_project,
        event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request]])
    end

    let_it_be(:ready_trigger) do
      create(:ai_flow_trigger, project: merge_request_project,
        event_types: [::Ai::FlowTrigger::EVENT_TYPES[:merge_request_ready]])
    end

    before_all do
      create(:ai_flow_trigger, project: merge_request_project)
    end

    it 'also returns triggers for the folded merge request actions' do
      triggers = described_class.new(
        merge_request_project, event_type: ::Ai::FlowTrigger::EVENT_TYPES[:merge_request]
      ).execute

      expect(triggers).to contain_exactly(merge_request_trigger, ready_trigger)
    end
  end
end
