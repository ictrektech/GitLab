# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Decisions::CreateFromDuoQuestionService, feature_category: :team_planning do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, reporter_of: project) }
  let_it_be(:service_account) { create(:user, :service_account, reporter_of: project) }
  let_it_be(:work_item) { create(:work_item, project: project) }
  let_it_be(:workflow) do
    create(:duo_workflows_workflow, project: project, user: user, service_account: service_account,
      workflow_definition: 'workplan/v1')
  end

  let(:options) do
    [
      { id: 'okta', label: 'Okta', description: 'Hosted identity.', recommended: true },
      { id: 'entra', label: 'Entra ID' }
    ]
  end

  let(:payload) { { type: 'closed', question: 'Which identity provider should we use?', options: options } }
  let(:body) { "@#{user.username} Which provider?\n\n```json:duo-question\n#{payload.to_json}\n```\n" }
  let(:author) { service_account }
  let(:note) { create(:note, noteable: work_item, project: project, author: author, note: body) }

  subject(:execute) do
    described_class.new(note: note, workflow: workflow, current_user: author).execute
  end

  before do
    stub_licensed_features(ai_workflows: true)
  end

  it 'creates an open decision from the question', :aggregate_failures do
    expect { execute }.to change { work_item.decisions.count }.by(1)

    decision = execute.payload[:decision]
    expect(decision).to have_attributes(
      title: 'Which identity provider should we use?',
      description: s_('WorkItemDecisionLog|GitLab Duo raised this question during review of the work item.'),
      discussion_id: note.discussion_id,
      workflow: workflow,
      author: service_account,
      resolved_at: nil
    )
    expect(decision.options.map { |option| option.slice(:content, :description, :recommended, :selected) })
      .to eq([
        { 'content' => 'Okta', 'description' => 'Hosted identity.', 'recommended' => true, 'selected' => false },
        { 'content' => 'Entra ID', 'description' => nil, 'recommended' => false, 'selected' => false }
      ])
  end

  context 'when the question is longer than a decision title allows' do
    let(:payload) { { type: 'closed', question: 'a' * 300, options: options } }

    it 'truncates the title' do
      expect(execute.payload[:decision].title.length).to eq(WorkItems::Decision::TITLE_LENGTH_MAX)
    end
  end

  context 'when the question offers more options than a decision holds' do
    let(:options) { Array.new(7) { |i| { id: "option-#{i}", label: "Option #{i}" } } }

    it 'keeps the first options that fit' do
      expect(execute.payload[:decision].options.map(&:content)).to eq(Array.new(5) { |i| "Option #{i}" })
    end
  end

  context 'when the question is open' do
    let(:payload) { { type: 'open', question: 'How many seats do we need?' } }

    it 'records only the question' do
      decision = execute.payload[:decision]

      expect(decision.title).to eq('How many seats do we need?')
      expect(decision.options).to be_empty
    end
  end

  context 'when the payload carries no question' do
    let(:body) { "Which provider?\n\n<!-- duo:options [\"Okta\", \"Entra ID\"] duo:recommended 1 -->\n" }

    it 'takes the title from the prose around the payload' do
      decision = execute.payload[:decision]

      expect(decision.title).to eq('Which provider?')
      expect(decision.options.map(&:content)).to eq(['Okta', 'Entra ID'])
    end
  end

  shared_examples 'does not record a decision' do
    it 'returns nil without creating a decision' do
      expect { expect(execute).to be_nil }.not_to change { WorkItems::Decision.count }
    end
  end

  context 'when the workflow is not a workplan flow' do
    let_it_be(:workflow) do
      create(:duo_workflows_workflow, project: project, user: user, service_account: service_account)
    end

    it_behaves_like 'does not record a decision'
  end

  context 'when the note carries no question' do
    let(:body) { 'An ordinary comment' }

    it_behaves_like 'does not record a decision'
  end

  context 'when the note is not on a work item' do
    let_it_be(:merge_request) { create(:merge_request, source_project: project) }

    let(:note) { create(:note, noteable: merge_request, project: project, author: author, note: body) }

    it_behaves_like 'does not record a decision'
  end

  context 'when decision_log is disabled' do
    before do
      stub_feature_flags(decision_log: false)
    end

    it_behaves_like 'does not record a decision'
  end

  context 'when the note is not posted by the workflow service account' do
    let(:author) { user }

    it_behaves_like 'does not record a decision'
  end

  context 'when ai_workflows is not licensed' do
    before do
      stub_licensed_features(ai_workflows: false)
    end

    it_behaves_like 'does not record a decision'
  end

  context 'when the work item type does not have the decision log' do
    let_it_be(:work_item) { create(:work_item, :incident, project: project) }

    it_behaves_like 'does not record a decision'
  end
end
