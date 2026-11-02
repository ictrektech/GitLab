# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::CodeReview::StoreFindingsService, feature_category: :dap_code_review do
  let_it_be(:merge_request) { create(:merge_request) }
  let_it_be(:project) { merge_request.project }
  let_it_be(:review) { create(:review, merge_request: merge_request, project: project) }
  let_it_be(:note) { create(:diff_note_on_merge_request, noteable: merge_request, project: project, review: review) }
  let_it_be_with_reload(:workflow) do
    create(:duo_workflows_workflow, project: project, flow_metadata_json: { flow_id: 'deep_code_review' }.to_json)
  end

  let(:severity) { 'major' }
  let(:category) { 'missing-test' }
  let(:confidence) { 7 }
  let(:review_id) { review.id }
  let(:review_workflow) { workflow }
  let(:draft_note) { DraftNote.new(merge_request: merge_request, note: note.note, position: note.position) }
  let(:comments_by_draft_note) do
    { draft_note => comment(severity: severity, category: category, confidence: confidence) }
  end

  subject(:execute) { store_findings }

  def store_findings
    described_class.new(
      merge_request: merge_request,
      review_id: review_id,
      comments_by_draft_note: comments_by_draft_note,
      workflow: review_workflow
    ).execute
  end

  def comment(severity:, category:, confidence:, for_note: note)
    Gitlab::Duo::CodeReview::FindingsParser::Comment.new(
      { 'file' => for_note.position.new_path, 'new_line' => for_note.position.new_line,
        'severity' => severity, 'category' => category, 'confidence' => confidence },
      for_note.note,
      nil
    )
  end

  def draft_for(for_note)
    DraftNote.new(merge_request: merge_request, note: for_note.note, position: for_note.position)
  end

  it 'stores the classification of each published note' do
    expect { execute }.to change { Ai::DuoWorkflows::CodeReview::Finding.count }.by(1)

    expect(Ai::DuoWorkflows::CodeReview::Finding.last).to have_attributes(
      note_id: note.id,
      project_id: project.id,
      merge_request_id: merge_request.id,
      workflow_id: workflow.id,
      severity: 'major',
      depth: 'deep',
      category: 'missing-test',
      confidence: 7
    )
  end

  it 'labels a review by the standard flow as standard' do
    workflow.update!(flow_metadata_json: { flow_id: 'code_review' }.to_json)

    execute

    expect(Ai::DuoWorkflows::CodeReview::Finding.last).to be_depth_standard
  end

  it 'skips a note whose body does not match its draft' do
    draft_note.note = 'A different body'

    expect { execute }.not_to change { Ai::DuoWorkflows::CodeReview::Finding.count }
  end

  context 'when the review has findings on different lines' do
    let_it_be(:other_note) do
      create(:diff_note_on_merge_request, noteable: merge_request, project: project, review: review, line_number: 9)
    end

    let(:comments_by_draft_note) do
      {
        draft_note => comment(severity: 'major', category: 'bug', confidence: 7),
        draft_for(other_note) => comment(severity: 'minor', category: 'naming', confidence: 5, for_note: other_note)
      }
    end

    it 'stores each note with its own classification' do
      execute

      expect(Ai::DuoWorkflows::CodeReview::Finding.pluck(:note_id, :severity, :category)).to contain_exactly(
        [note.id, 'major', 'bug'],
        [other_note.id, 'minor', 'naming']
      )
    end
  end

  context 'when two drafts have the same position and body' do
    let(:comments_by_draft_note) do
      {
        draft_note => comment(severity: 'major', category: 'bug', confidence: 7),
        draft_for(note) => comment(severity: 'minor', category: 'naming', confidence: 5)
      }
    end

    it 'keeps the first classification' do
      execute

      expect(Ai::DuoWorkflows::CodeReview::Finding.sole).to have_attributes(severity: 'major', category: 'bug')
    end
  end

  it 'does not store a finding twice' do
    store_findings

    expect { store_findings }.not_to change { Ai::DuoWorkflows::CodeReview::Finding.count }
  end

  context 'when the workflow did not record a code review flow' do
    let(:review_workflow) { create(:duo_workflows_workflow, project: project) }

    it 'stores nothing' do
      expect { execute }.not_to change { Ai::DuoWorkflows::CodeReview::Finding.count }
    end
  end

  context 'when the review also has a summary note without a diff position' do
    before do
      create(:note, noteable: merge_request, project: project, review: review)
    end

    it 'stores only the diff note' do
      expect { execute }.to change { Ai::DuoWorkflows::CodeReview::Finding.count }.by(1)
      expect(Ai::DuoWorkflows::CodeReview::Finding.last.note_id).to eq(note.id)
    end
  end

  context 'when the flow metadata is not a JSON object' do
    before do
      workflow.update!(flow_metadata_json: '[]')
    end

    it 'stores nothing' do
      expect { execute }.not_to change { Ai::DuoWorkflows::CodeReview::Finding.count }
    end
  end

  context 'when there is no workflow' do
    let(:review_workflow) { nil }

    it 'stores nothing' do
      expect { execute }.not_to change { Ai::DuoWorkflows::CodeReview::Finding.count }
    end
  end

  context 'when there is no review' do
    let(:review_id) { nil }

    it 'stores nothing' do
      expect { execute }.not_to change { Ai::DuoWorkflows::CodeReview::Finding.count }
    end
  end

  context 'when the finding has an unknown severity' do
    let(:severity) { 'blocker' }

    it 'stores nothing' do
      expect { execute }.not_to change { Ai::DuoWorkflows::CodeReview::Finding.count }
    end
  end

  context 'when the finding has no category' do
    let(:category) { nil }

    it 'stores nothing' do
      expect { execute }.not_to change { Ai::DuoWorkflows::CodeReview::Finding.count }
    end
  end

  context 'when a standard flow review posts XML comments' do
    let(:comments_by_draft_note) do
      xml_comment = Gitlab::Llm::AiGateway::Completions::ReviewMergeRequest::ResponseBodyParser::Comment.new(
        { 'file' => note.position.new_path, 'new_line' => note.position.new_line.to_s },
        note.note,
        nil
      )

      { draft_note => xml_comment }
    end

    before do
      workflow.update!(flow_metadata_json: { flow_id: 'code_review' }.to_json)
    end

    it 'stores nothing because XML comments carry no classification' do
      expect { execute }.not_to change { Ai::DuoWorkflows::CodeReview::Finding.count }
    end
  end

  context 'when the finding has an out-of-range confidence' do
    let(:confidence) { 11 }

    it 'stores the finding without a confidence' do
      execute

      expect(Ai::DuoWorkflows::CodeReview::Finding.last.confidence).to be_nil
    end
  end

  context 'when storing fails' do
    before do
      allow(Ai::DuoWorkflows::CodeReview::Finding).to receive(:insert_all).and_raise(ActiveRecord::StatementInvalid)
    end

    it 'tracks the error without raising' do
      expect(Gitlab::ErrorTracking).to receive(:track_exception)
        .with(an_instance_of(ActiveRecord::StatementInvalid), merge_request_id: merge_request.id, review_id: review.id)

      expect { execute }.not_to raise_error
    end
  end
end
