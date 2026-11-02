# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SystemNotes::DecisionsService, feature_category: :team_planning do
  let_it_be(:project) { create(:project) }
  let_it_be(:work_item) { create(:work_item, project: project) }
  let_it_be(:author) { create(:user) }
  let_it_be_with_reload(:decision) do
    create(:work_item_decision, :resolved, work_item: work_item, resolved_by: author,
      title: 'Which storage backend should we use?')
  end

  let(:noteable) { work_item }
  let(:service) { described_class.new(noteable: work_item, container: project, author: author) }
  let(:decision_url) do
    "#{Gitlab::Routing.url_helpers.project_work_item_url(project, work_item.iid)}" \
      "?show=decision-log#decision_#{decision.id}"
  end

  describe '#decision_recorded' do
    subject(:system_note) { service.decision_recorded(decision) }

    context 'with one selected option' do
      before do
        create(:work_item_decision_option, :selected, decision: decision, content: 'Use PostgreSQL')
        create(:work_item_decision_option, decision: decision, content: 'Use Redis')
      end

      it_behaves_like 'a system note' do
        let(:action) { 'decision_recorded' }
      end

      it 'links the selected option content to the decision card' do
        expect(system_note.note).to eq("recorded a decision [Use PostgreSQL](#{decision_url})")
      end
    end

    context 'with several selected options' do
      before do
        create(:work_item_decision_option, :selected, decision: decision, content: 'Use PostgreSQL')
        create(:work_item_decision_option, decision: decision, content: 'Use SQLite')
        create(:work_item_decision_option, :selected, decision: decision, content: 'Add a Redis cache')
      end

      it 'joins the selected option content with commas, in option order' do
        expect(system_note.note).to eq("recorded a decision [Use PostgreSQL, Add a Redis cache](#{decision_url})")
      end
    end

    context 'when no option is selected' do
      before do
        create(:work_item_decision_option, decision: decision, content: 'Use SQLite')
      end

      it 'links the title instead' do
        expect(system_note.note).to eq("recorded a decision [Which storage backend should we use?](#{decision_url})")
      end
    end

    context 'when the decision text contains characters that would break the link' do
      before do
        create(:work_item_decision_option, :selected, decision: decision,
          content: "Don't use [Redis] & co <v16>\n  with   pgbouncer")
      end

      it 'escapes markdown punctuation and collapses whitespace, leaving the text readable' do
        expect(system_note.note)
          .to eq("recorded a decision [Don't use \\[Redis\\] \\& co \\<v16\\> with pgbouncer](#{decision_url})")
      end
    end

    context 'when the decision text contains emphasis markers' do
      before do
        create(:work_item_decision_option, :selected, decision: decision, content: '2*3*4 = 24')
      end

      it 'escapes them so the text renders literally' do
        expect(system_note.note).to eq("recorded a decision [2\\*3\\*4 \\= 24](#{decision_url})")
      end
    end

    context 'when the decision text contains backslashes' do
      before do
        create(:work_item_decision_option, :selected, decision: decision, content: 'Use C:\\ or a\\[b')
      end

      it 'escapes them so they cannot neutralise the bracket escapes' do
        expect(system_note.note)
          .to eq("recorded a decision [Use C:\\\\ or a\\\\\\[b](#{decision_url})")
      end
    end

    context 'when building the note raises' do
      before do
        allow(Gitlab::UrlBuilder).to receive(:build).and_raise(StandardError, 'note failed')
      end

      it 'tracks the exception instead of raising', :aggregate_failures do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(an_instance_of(StandardError), decision_id: decision.id)

        expect { system_note }.not_to change { Note.count }
        expect(system_note).to be_nil
      end
    end

    context 'with a group-level work item' do
      let_it_be(:group) { create(:group) }
      let_it_be(:work_item) { create(:work_item, :group_level, namespace: group) }
      let_it_be(:decision) do
        create(:work_item_decision, :resolved, work_item: work_item, resolved_by: author)
      end

      let(:service) { described_class.new(noteable: work_item, container: group, author: author) }
      let(:decision_url) do
        "#{Gitlab::Routing.url_helpers.group_work_item_url(group, work_item.iid)}" \
          "?show=decision-log#decision_#{decision.id}"
      end

      before do
        create(:work_item_decision_option, :selected, decision: decision, content: 'Use PostgreSQL')
      end

      it_behaves_like 'a system note', exclude_project: true do
        let(:action) { 'decision_recorded' }
      end

      it 'links to the group work item' do
        expect(system_note.note).to eq("recorded a decision [Use PostgreSQL](#{decision_url})")
        expect(system_note.namespace).to eq(group)
      end
    end
  end
end
