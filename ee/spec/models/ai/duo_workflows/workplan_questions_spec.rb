# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::WorkplanQuestions, feature_category: :duo_agent_platform do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, group: group) }
  let_it_be(:service_account) { create(:user, :service_account) }
  let_it_be(:developer) { create(:user, developer_of: project) }
  let_it_be(:guest) { create(:user, guest_of: project) }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:work_item) { create(:work_item, project: project) }
  let_it_be(:workflow) do
    create(:duo_workflows_workflow, :input_required, work_item: work_item, project: project,
      workflow_definition: 'workplan/v1')
  end

  let(:current_user) { developer }

  subject(:workplan_questions) { described_class.new(work_item, current_user) }

  # `confidential` is the attribute NotePolicy reads; `internal` is a copy Note syncs on create.
  def flow_note(
    text, in_reply_to: nil, type: :discussion_note_on_work_item, run: workflow, question: true, confidential: false)
    body = question ? question_body(text) : text
    note = create(type, noteable: work_item, project: project, author: service_account, note: body,
      in_reply_to: in_reply_to, confidential: confidential)
    create(:duo_workflows_workflow_note, workflow: run, note: note)
    note
  end

  def question_body(text)
    payload = { type: 'closed', question: text, options: [{ id: 'okta', label: 'Okta' }] }

    "#{text}\n\n```json:duo-question\n#{payload.to_json}\n```"
  end

  # Mirrors Notes::CreateService: a reply to a flat note first turns it into a discussion.
  def reply(question, author:, text: 'answer')
    discussion = question.to_discussion
    discussion.convert_to_discussion!.first_note.save! if discussion.can_convert_to_discussion?

    create(:note, in_reply_to: question.reload.to_discussion, noteable: work_item, project: project, author: author,
      note: text)
  end

  def resolve(question)
    Note.find(question.id).discussion.resolve!(developer)
  end

  # [answered, total]
  def counts
    list = workplan_questions.questions

    [list.count(&:answered), list.size]
  end

  describe '#any_flow_ran?' do
    it { is_expected.to be_any_flow_ran }

    context 'when the only flow on the work item is not a workplan run' do
      let_it_be(:work_item) { create(:work_item, project: project) }

      before_all do
        create(:duo_workflows_workflow, :input_required, work_item: work_item, project: project,
          workflow_definition: 'chat')
      end

      it { is_expected.not_to be_any_flow_ran }
    end
  end

  context 'when the flow asked nothing' do
    it 'returns no questions' do
      expect(workplan_questions.questions).to be_empty
    end
  end

  describe 'what each question carries' do
    it 'names the note and the thread, oldest first', :aggregate_failures do
      first = flow_note('Which auth provider?')
      resolve(first)
      second = flow_note('Which region?')

      questions = workplan_questions.questions

      expect(questions.map(&:note)).to eq([first, second])
      expect(questions.map { |question| question.note.discussion_id })
        .to eq([first.discussion_id, second.discussion_id])
      expect(questions.map(&:answered)).to eq([true, false])
    end
  end

  describe '#open_count' do
    it 'counts only the questions whose thread is not resolved' do
      resolve(flow_note('Which auth provider?'))
      reply(flow_note('Which region?'), author: developer)
      flow_note('Which cloud?')

      expect(workplan_questions.open_count).to eq(2)
    end

    it 'is zero when the flow asked nothing' do
      expect(workplan_questions.open_count).to eq(0)
    end
  end

  context 'when the flow asks in an internal note' do
    before do
      flow_note('Which auth provider?', confidential: true)
      flow_note('Which region?')
    end

    it 'counts it for a reader who can see internal notes' do
      expect(counts).to eq([0, 2])
    end

    context 'when the reader cannot see internal notes' do
      let(:current_user) { guest }

      it 'counts only the questions they can open' do
        expect(counts).to eq([0, 1])
      end
    end
  end

  context 'when every question thread is resolved' do
    it 'counts them all as answered' do
      resolve(flow_note('Which auth provider?'))
      resolve(flow_note('Which region?'))

      expect(counts).to eq([2, 2])
    end
  end

  context 'when only some question threads are resolved' do
    it 'counts only those as answered' do
      resolve(flow_note('Which auth provider?'))
      flow_note('Which region?')

      expect(counts).to eq([1, 2])
    end
  end

  context 'when a question has replies but its thread is not resolved' do
    it 'leaves the question unanswered' do
      question = flow_note('Which auth provider?')
      reply(question, author: developer, text: 'Okta')
      reply(question, author: developer, text: 'Actually, SAML')

      expect(counts).to eq([0, 1])
    end
  end

  context 'when a Guest replies without resolving the thread' do
    it 'leaves the question unanswered' do
      reply(flow_note('Which auth provider?'), author: guest)

      expect(counts).to eq([0, 1])
    end
  end

  context 'when a non-member replies without resolving the thread' do
    it 'leaves the question unanswered' do
      reply(flow_note('Which auth provider?'), author: non_member)

      expect(counts).to eq([0, 1])
    end
  end

  context 'when a question has replies and its thread is resolved' do
    it 'counts the question once as answered' do
      question = flow_note('Which auth provider?')
      reply(question, author: developer, text: 'Okta')
      reply(question, author: guest, text: 'Actually, SAML')
      resolve(question)

      expect(counts).to eq([1, 1])
    end
  end

  context 'when a resolved thread is unresolved again' do
    it 'leaves the question unanswered' do
      question = flow_note('Which auth provider?')
      resolve(question)
      Note.find(question.id).discussion.unresolve!

      expect(counts).to eq([0, 1])
    end
  end

  context 'when the flow comments without asking' do
    it 'counts the comment, which carries nothing to set it apart from an ask' do
      flow_note('Analyzing the work item, one moment.', question: false)

      expect(counts).to eq([0, 1])
    end

    it 'counts it as answered once its thread is resolved' do
      resolve(flow_note('Here is the plan so far.', question: false))

      expect(counts).to eq([1, 1])
    end

    it 'counts it alongside the questions' do
      flow_note('Analyzing the work item, one moment.', question: false)
      resolve(flow_note('Which auth provider?'))

      expect(counts).to eq([1, 2])
    end

    it 'counts a thread it opened with a comment once' do
      comment = flow_note('Here is the plan so far.', question: false)
      flow_note('Which auth provider?', in_reply_to: comment)

      expect(counts).to eq([0, 1])
    end
  end

  context 'when the flow posts again in its own thread' do
    it 'counts the thread once and leaves it unanswered until resolved' do
      question = flow_note('Which auth provider?')
      flow_note('Any of Okta, SAML or OIDC works.', in_reply_to: question, question: false)

      expect(counts).to eq([0, 1])
    end

    it 'counts a question it reposts in that thread once' do
      question = flow_note('Which auth provider?')
      flow_note('Which auth provider?', in_reply_to: question)

      expect(counts).to eq([0, 1])
    end

    it 'counts the thread as answered once every note in it is resolved' do
      question = flow_note('Which auth provider?')
      reply(question, author: developer)
      flow_note('Thanks, proceeding with Okta.', in_reply_to: question, question: false)
      resolve(question)

      expect(counts).to eq([1, 1])
    end
  end

  context 'when the question is a flat note rather than a discussion note' do
    it 'leaves it unanswered, as a flat note cannot be resolved' do
      flow_note('Which auth provider?', type: :note_on_work_item)

      expect(counts).to eq([0, 1])
    end

    it 'counts it as answered once a reply turns it into a resolved thread' do
      question = flow_note('Which auth provider?', type: :note_on_work_item)
      reply(question, author: developer)
      resolve(question)

      expect(counts).to eq([1, 1])
    end
  end

  context 'when an earlier run was cancelled with its questions still open' do
    let_it_be(:cancelled_workflow) do
      create(:duo_workflows_workflow, :stopped, work_item: work_item, project: project,
        workflow_definition: 'workplan/v1')
    end

    it 'counts the questions of both runs' do
      flow_note('Which auth provider?', run: cancelled_workflow)
      flow_note('Which region?')

      expect(counts).to eq([0, 2])
    end

    it 'counts the resolved earlier question as answered' do
      resolve(flow_note('Which auth provider?', run: cancelled_workflow))
      flow_note('Which region?')

      expect(counts).to eq([1, 2])
    end

    it 'leaves the earlier thread unanswered when the new run posts in it' do
      question = flow_note('Which auth provider?', run: cancelled_workflow)
      flow_note('Still need this one.', in_reply_to: question, question: false)

      expect(counts).to eq([0, 1])
    end
  end

  context 'when a flow other than workplan posted on the work item' do
    let_it_be(:chat_workflow) do
      create(:duo_workflows_workflow, :input_required, work_item: work_item, project: project,
        workflow_definition: 'chat')
    end

    it 'ignores its notes' do
      flow_note('Which auth provider?', run: chat_workflow)

      expect(counts).to eq([0, 0])
    end
  end
end
