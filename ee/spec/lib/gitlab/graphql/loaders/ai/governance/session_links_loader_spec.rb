# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Graphql::Loaders::Ai::Governance::SessionLinksLoader, feature_category: :compliance_management do
  include GraphqlHelpers

  let_it_be(:project) { create(:project) }
  let_it_be(:workflow) { create(:duo_workflows_workflow, project: project) }
  let_it_be(:other_workflow) { create(:duo_workflows_workflow, project: project) }
  let_it_be(:workflow_without_links) { create(:duo_workflows_workflow, project: project) }

  let_it_be(:merge_request_links) do
    [:created, :source].map do |link_type|
      create(:duo_workflows_workflow_merge_request, workflow: workflow, link_type: link_type,
        merge_request: create(:merge_request, :unique_branches, source_project: project))
    end
  end

  let_it_be(:other_merge_request_link) do
    create(:duo_workflows_workflow_merge_request, workflow: other_workflow,
      merge_request: create(:merge_request, :unique_branches, source_project: project))
  end

  let_it_be(:note_link) { create(:duo_workflows_workflow_note, workflow: workflow) }
  let_it_be(:work_item_link) { create(:duo_workflows_workflow_work_item, workflow: other_workflow) }

  def load_links(kind, *workflow_ids)
    batch_sync { workflow_ids.map { |id| described_class.new(kind, id).find } }
  end

  it 'loads the links of each workflow, ordered by ID' do
    expect(load_links(:merge_request, workflow.id, other_workflow.id, workflow_without_links.id))
      .to eq([merge_request_links.sort_by(&:id), [other_merge_request_link], []])
  end

  it 'loads each kind of link', :aggregate_failures do
    expect(load_links(:note, workflow.id, other_workflow.id)).to eq([[note_link], []])
    expect(load_links(:work_item, workflow.id, other_workflow.id)).to eq([[], [work_item_link]])
  end

  it 'accepts a workflow ID given as a string' do
    expect(load_links(:note, workflow.id.to_s)).to eq([[note_link]])
  end

  it 'runs one query per kind across workflows' do
    workflow_ids = [workflow.id, other_workflow.id, workflow_without_links.id]

    recorder = ActiveRecord::QueryRecorder.new do
      batch_sync do
        described_class::MODELS.keys.flat_map do |kind|
          workflow_ids.map { |id| described_class.new(kind, id).find }
        end
      end
    end

    expect(recorder.count).to eq(described_class::MODELS.size)
  end

  it 'returns no links without a query for a nil workflow ID' do
    recorder = ActiveRecord::QueryRecorder.new do
      expect(load_links(:merge_request, nil)).to eq([[]])
    end

    expect(recorder.count).to eq(0)
  end

  it 'raises for an unknown kind' do
    expect { described_class.new(:pipeline, workflow.id) }.to raise_error(KeyError)
  end
end
