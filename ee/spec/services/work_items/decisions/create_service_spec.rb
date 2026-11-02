# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Decisions::CreateService, feature_category: :team_planning do
  let_it_be(:project) { create(:project) }
  let_it_be(:reporter) { create(:user, reporter_of: project) }
  let_it_be(:guest) { create(:user, guest_of: project) }
  # refind: get_widget memoizes on the instance, so license/flag contexts
  # need a fresh work item rather than a shared memoized one
  let_it_be_with_refind(:work_item) { create(:work_item, project: project) }

  let(:current_user) { reporter }
  let(:params) do
    {
      question: 'Which storage backend should we use?',
      options: [{ content: 'Use PostgreSQL', recommended: true }, { content: 'Use Redis' }]
    }
  end

  subject(:response) do
    described_class.new(work_item: work_item, current_user: current_user, params: params).execute
  end

  before do
    stub_licensed_features(ai_workflows: true)
  end

  it 'creates the decision with its options' do
    expect { response }.to change { work_item.decisions.count }.by(1)

    expect(response).to be_success

    decision = response.payload[:decision]
    expect(decision).to have_attributes(
      title: 'Which storage backend should we use?',
      author: current_user,
      namespace: work_item.namespace
    )
    expect(decision.options.map(&:content)).to contain_exactly('Use PostgreSQL', 'Use Redis')
  end

  it 'does not record a system note for an open decision' do
    expect { response }.not_to change { work_item.notes.system.count }
  end

  it 'does not track an event for an open decision' do
    expect { response }.not_to trigger_internal_events('work_item_decision_create')
  end

  context 'with a source link' do
    let(:params) { { question: 'Question', source_link: 'https://example.com/thread' } }

    it 'persists the source link' do
      expect(response).to be_success
      expect(response.payload[:decision].source_link).to eq('https://example.com/thread')
    end
  end

  context 'with a workflow' do
    let_it_be(:workflow) { create(:duo_workflows_workflow, project: project, user: reporter) }

    let(:params) { { question: 'Question', workflow: workflow } }

    it 'links the decision to the workflow' do
      expect(response).to be_success
      expect(response.payload[:decision].workflow).to eq(workflow)
    end
  end

  context 'when more options than the limit are given' do
    let(:params) do
      {
        question: 'Question',
        options: Array.new(WorkItems::Decision::MAX_OPTIONS_PER_DECISION + 1) { |i| { content: "Option #{i}" } }
      }
    end

    it 'returns an error without creating anything' do
      expect { response }.not_to change { WorkItems::Decision.count }

      expect(response).to be_error
      expect(response.errors.to_sentence).to match(/cannot have more than/)
    end
  end

  context 'with resolution params' do
    let(:params) do
      {
        question: 'Which storage backend should we use?',
        resolution: { decision: 'Use PostgreSQL for the storage backend', rationale: 'Settled in the design sync' }
      }
    end

    it 'tracks a decision create event' do
      expect { response }.to trigger_internal_events('work_item_decision_create').with(
        category: ::Gitlab::WorkItems::Instrumentation::TrackingService.name,
        user: current_user,
        project: project,
        namespace: project.project_namespace,
        additional_properties: {
          label: 'Issue',
          property: 'Reporter',
          source: 'internal',
          work_item_id: work_item.id,
          decision_id: a_kind_of(Integer)
        }
      )
    end

    it 'creates the decision resolved by the current user, recording the decision as the selected option' do
      expect { response }.to change { WorkItems::DecisionOption.count }.by(1)

      expect(response).to be_success

      decision = response.payload[:decision]
      expect(decision).to have_attributes(
        title: 'Which storage backend should we use?',
        resolved_by: current_user,
        resolution_rationale: 'Settled in the design sync'
      )
      expect(decision.resolved_at).to eq(decision.created_at)
      expect(decision.options.map { |option| [option.content, option.selected] })
        .to contain_exactly(['Use PostgreSQL for the storage backend', true])
    end

    it 'records a system note authored by the actor', :aggregate_failures do
      expect { response }.to change { work_item.notes.system.count }.by(1)

      note = work_item.notes.system.sole
      expect(note.author).to eq(current_user)
      expect(note.system_note_metadata.action).to eq('decision_recorded')
      expect(note.note).to start_with('recorded a decision [Use PostgreSQL for the storage backend](')
    end

    context 'when the system note cannot be recorded' do
      before do
        allow_next_instance_of(SystemNotes::DecisionsService) do |service|
          allow(service).to receive(:create_note).and_raise(StandardError, 'note failed')
        end
      end

      it 'still creates the resolved decision' do
        expect { response }.to change { work_item.decisions.count }.by(1)

        expect(response).to be_success
        expect(response.payload[:decision].resolved_at).to be_present
      end
    end

    context 'with blank optional inputs' do
      let(:params) do
        { question: '', source_link: '', resolution: { decision: 'Use PostgreSQL' } }
      end

      it 'normalizes blanks to nil' do
        expect(response).to be_success
        expect(response.payload[:decision]).to have_attributes(title: nil, source_link: nil)
      end
    end

    context 'without a question' do
      let(:params) do
        { resolution: { decision: 'Use PostgreSQL for the storage backend' } }
      end

      it 'creates the decision with a nil title' do
        expect(response).to be_success
        expect(response.payload[:decision].title).to be_nil
      end
    end

    context 'when the decision content is missing' do
      let(:params) do
        { question: 'Question', resolution: { rationale: 'Settled' } }
      end

      it 'returns an error without creating anything' do
        expect { response }.not_to change { WorkItems::Decision.count }

        expect(response).to be_error
        expect(response.errors.to_sentence).to match(/Content can't be blank/)
      end
    end

    context 'when resolved_by_id names another user with access' do
      let_it_be(:resolver_user) { create(:user, reporter_of: project) }

      let(:params) do
        { question: 'Question', resolution: { decision: 'Go with Redis', resolved_by_id: resolver_user.id } }
      end

      it 'records that user as the resolver while the note is authored by the actor', :aggregate_failures do
        expect(response).to be_success
        expect(response.payload[:decision].resolved_by).to eq(resolver_user)
        expect(work_item.notes.system.sole.author).to eq(current_user)
      end
    end

    context 'when resolved_by_id names a user without access' do
      let_it_be(:outsider) { create(:user) }

      let(:params) do
        { question: 'Question', resolution: { decision: 'Go with Redis', resolved_by_id: outsider.id } }
      end

      it 'returns an error without creating anything' do
        expect { response }.not_to change { WorkItems::Decision.count }

        expect(response).to be_error
        expect(response.errors).to include('Resolver must have access to the work item')
      end
    end

    context 'when resolved_by_id does not exist' do
      let(:params) do
        { question: 'Question', resolution: { decision: 'Go with Redis', resolved_by_id: non_existing_record_id } }
      end

      it 'returns an error without creating anything' do
        expect { response }.not_to change { WorkItems::Decision.count }

        expect(response).to be_error
        expect(response.errors).to include('Resolver must have access to the work item')
      end
    end

    context 'when options are also given' do
      let(:params) do
        {
          question: 'Question',
          resolution: { decision: 'Go with Redis', rationale: 'Settled' },
          options: [{ content: 'Use PostgreSQL' }]
        }
      end

      it 'returns an error without creating anything' do
        expect { response }.not_to change { WorkItems::Decision.count }

        expect(response).to be_error
        expect(response.errors).to include('Options are not supported when creating a resolved decision')
      end
    end
  end

  context 'when an open decision has no question' do
    let(:params) { { options: [{ content: 'Use PostgreSQL' }] } }

    it 'returns an error without creating anything' do
      expect { response }.not_to change { WorkItems::Decision.count }

      expect(response).to be_error
      expect(response.errors.to_sentence).to match(/Question can't be blank/)
    end
  end

  context 'when an option is invalid' do
    let(:params) { { question: 'Question', options: [{ content: '' }] } }

    it 'returns an error and rolls back the decision' do
      expect { response }.not_to change { WorkItems::Decision.count }

      expect(response).to be_error
      expect(response.errors.to_sentence).to match(/Content can't be blank/)
    end
  end

  context 'when user cannot update the work item' do
    let(:current_user) { guest }

    it 'returns an error' do
      expect(response).to be_error
      expect(response.errors).to include('Operation not allowed')
    end

    it 'does not track an event' do
      expect { response }.not_to trigger_internal_events('work_item_decision_create')
    end
  end

  context 'when ai_workflows is not licensed' do
    before do
      stub_licensed_features(ai_workflows: false)
    end

    it 'returns an error' do
      expect(response).to be_error
      expect(response.errors).to include('Operation not allowed')
    end
  end

  context 'when the work item type does not have the widget' do
    let_it_be(:incident_work_item) { create(:work_item, :incident, project: project) }

    let(:work_item) { incident_work_item }

    it 'returns an error' do
      expect(response).to be_error
      expect(response.errors).to include('Operation not allowed')
    end
  end

  context 'when decision_log is disabled' do
    before do
      stub_feature_flags(decision_log: false)
    end

    it 'returns an error' do
      expect(response).to be_error
      expect(response.errors).to include('Operation not allowed')
    end
  end
end
