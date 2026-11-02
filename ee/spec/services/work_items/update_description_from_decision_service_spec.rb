# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::UpdateDescriptionFromDecisionService, feature_category: :team_planning do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be_with_reload(:work_item) { create(:work_item, project: project, description: 'Use the old backend') }
  let_it_be(:decision) { create(:work_item_decision, work_item: work_item, title: 'Which backend?') }

  let(:generated) { 'Use PostgreSQL' }
  let(:completion) { instance_double(Gitlab::Llm::AiGateway::Completions::UpdateDescriptionFromDecision) }
  let(:ai_message) { instance_double(Gitlab::Llm::AiMessage, content: generated) }

  subject(:response) { described_class.new(decision: decision, current_user: user).execute }

  before_all do
    create(:work_item_decision_option, decision: decision, content: 'Use PostgreSQL', selected: true)
    create(:work_item_decision_option, decision: decision, content: 'Use Redis')
  end

  before do
    stub_licensed_features(ai_workflows: true)
    allow(Ai::DuoAgentPlatform).to receive(:available?).and_return(true)
    allow(Gitlab::Llm::AiGateway::Completions::UpdateDescriptionFromDecision)
      .to receive(:new).and_return(completion)
    allow(completion).to receive(:execute).and_return({ ai_message: ai_message })
  end

  it 'saves the generated description as the user', :aggregate_failures do
    expect(response).to be_success

    expect(work_item.reload).to have_attributes(description: 'Use PostgreSQL', last_edited_by: user)
    expect(response.payload[:description_version]).to be_a(DescriptionVersion)
  end

  it 'sends the decision to the AI gateway' do
    response

    expect(Gitlab::Llm::AiGateway::Completions::UpdateDescriptionFromDecision).to have_received(:new).with(
      anything,
      nil,
      hash_including(
        description: 'Use the old backend',
        question: 'Which backend?',
        options: ['Use PostgreSQL', 'Use Redis'],
        answer: 'Use PostgreSQL'
      )
    )
  end

  context 'when the output contains quick actions' do
    let(:generated) { "Use PostgreSQL\n/close" }

    it 'does not run them', :aggregate_failures do
      expect(response).to be_success

      expect(work_item.reload).to have_attributes(description: 'Use PostgreSQL', state: 'opened')
    end
  end

  context 'when the output contains a quick action with side effects' do
    let(:generated) { "Use PostgreSQL\n/add_email someone@example.com" }

    it 'does not run it', :aggregate_failures do
      expect { response }.not_to change { IssueEmailParticipant.count }

      expect(response).to be_success
      expect(work_item.reload.description).to eq('Use PostgreSQL')
    end
  end

  context 'when the work item cannot be saved' do
    before do
      allow_next_instance_of(WorkItems::UpdateService) do |service|
        allow(service).to receive(:execute).and_return({ status: :error, message: 'Description is too long' })
      end
    end

    it 'returns the error', :aggregate_failures do
      expect(response).to be_error
      expect(response.message).to eq('Description is too long')
    end
  end

  context 'when the output adds a mention' do
    let(:generated) { "Use PostgreSQL, ask @#{user.username}" }

    it 'saves it without notifying the user', :aggregate_failures do
      expect(response).to be_success
      expect(work_item.reload.description).to eq("Use PostgreSQL, ask `@#{user.username}`")
    end

    context 'when the mention is already in the description' do
      before do
        work_item.update!(description: "Use the old backend, ask @#{user.username}")
      end

      it 'keeps it', :aggregate_failures do
        expect(response).to be_success
        expect(work_item.reload.description).to eq(generated)
      end
    end
  end

  context 'when the output has an @ in a URL or code' do
    let(:generated) do
      "See https://www.npmjs.com/package/@types/node and `@scope/pkg`\n\n```\nnpm i @scope/pkg\n```\n\nask @scope/other"
    end

    it 'only wraps the plain mention', :aggregate_failures do
      expect(response).to be_success
      expect(work_item.reload.description).to eq(
        "See https://www.npmjs.com/package/@types/node and `@scope/pkg`\n\n```\nnpm i @scope/pkg\n```\n\n" \
          "ask `@scope/other`"
      )
    end
  end

  context 'when the output is much shorter than the description' do
    let_it_be_with_reload(:work_item) do
      create(:work_item, project: project, description: 'Use the old backend for all the data we store')
    end

    let_it_be(:decision) { create(:work_item_decision, work_item: work_item, title: 'Which backend?') }

    let(:generated) { '...rest unchanged' }

    it 'keeps the description', :aggregate_failures do
      expect(response).to be_error
      expect(work_item.reload.description).to eq('Use the old backend for all the data we store')
    end
  end

  context 'when the user cannot update the work item' do
    let_it_be(:user) { create(:user, guest_of: project) }

    it 'does not call the AI gateway', :aggregate_failures do
      expect(response).to be_error
      expect(completion).not_to have_received(:execute)
    end
  end

  context 'when the resolver no longer exists' do
    subject(:response) { described_class.new(decision: decision, current_user: nil).execute }

    it 'does not call the AI gateway', :aggregate_failures do
      expect(response).to be_error
      expect(completion).not_to have_received(:execute)
    end
  end

  context 'when Duo Agent Platform is not available' do
    before do
      allow(Ai::DuoAgentPlatform).to receive(:available?).and_return(false)
    end

    it 'does not call the AI gateway', :aggregate_failures do
      expect(response).to be_error
      expect(completion).not_to have_received(:execute)
    end
  end

  context 'when the AI gateway request fails' do
    before do
      allow(Gitlab::Llm::AiGateway::Completions::UpdateDescriptionFromDecision)
        .to receive(:new).and_call_original
      allow_next_instance_of(Gitlab::Llm::AiGateway::Completions::UpdateDescriptionFromDecision) do |completion|
        allow(completion).to receive(:perform_ai_gateway_request!).and_return(nil)
      end
    end

    it 'keeps the description', :aggregate_failures do
      expect(response).to be_error
      expect(work_item.reload.description).to eq('Use the old backend')
    end
  end

  context 'when the AI gateway returns a description' do
    before do
      allow(Gitlab::Llm::AiGateway::Completions::UpdateDescriptionFromDecision)
        .to receive(:new).and_call_original
      allow_next_instance_of(Gitlab::Llm::AiGateway::Completions::UpdateDescriptionFromDecision) do |completion|
        allow(completion).to receive(:perform_ai_gateway_request!).and_return('Use PostgreSQL')
      end
    end

    it 'saves it through the real completion', :aggregate_failures do
      expect(response).to be_success
      expect(work_item.reload.description).to eq('Use PostgreSQL')
    end
  end

  context 'when the AI gateway returns nothing' do
    let(:generated) { '' }

    it 'keeps the description', :aggregate_failures do
      expect(response).to be_error
      expect(work_item.reload.description).to eq('Use the old backend')
    end
  end

  context 'when the completion returns no AI message' do
    where(:completion_result) { [nil, { ai_message: nil }] }

    with_them do
      before do
        allow(completion).to receive(:execute).and_return(completion_result)
      end

      it 'keeps the description', :aggregate_failures do
        expect(response).to be_error
        expect(work_item.reload.description).to eq('Use the old backend')
      end
    end
  end

  context 'when someone edits the work item during the request' do
    def edit_during_request
      calls = 0
      allow(completion).to receive(:execute) do
        calls += 1
        WorkItem.find(work_item.id).update_columns(lock_version: work_item.lock_version + 1) if yield(calls)
        { ai_message: ai_message }
      end
    end

    it 'retries once and saves', :aggregate_failures do
      edit_during_request { |calls| calls == 1 }

      expect(response).to be_success
      expect(completion).to have_received(:execute).twice
      expect(work_item.reload.description).to eq('Use PostgreSQL')
    end

    it 'gives up after the second stale save', :aggregate_failures do
      edit_during_request { true }

      expect(response).to be_error
      expect(completion).to have_received(:execute).twice
      expect(work_item.reload.description).to eq('Use the old backend')
    end
  end
end
