# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Decisions::UpdateService, feature_category: :team_planning do
  let_it_be(:project) { create(:project) }
  let_it_be(:reporter) { create(:user, reporter_of: project) }
  let_it_be(:guest) { create(:user, guest_of: project) }
  let_it_be(:work_item) { create(:work_item, project: project) }
  let_it_be(:resolving_note) { create(:note, noteable: work_item, project: project) }

  let_it_be(:original_discussion_id) { SecureRandom.hex(20) }
  let_it_be_with_reload(:decision) do
    create(
      :work_item_decision,
      work_item: work_item,
      description: 'Original context',
      discussion_id: original_discussion_id,
      source_link: 'https://example.com/original'
    )
  end

  let(:current_user) { reporter }
  let(:discussion_id) { SecureRandom.hex(20) }
  let(:params) do
    {
      question: 'Which cache should we use?',
      description: 'The current cache is slow',
      discussion_id: discussion_id,
      source_link: 'https://docs.google.com/document/d/abc123'
    }
  end

  subject(:response) do
    described_class.new(decision: decision, current_user: current_user, params: params).execute
  end

  before do
    stub_licensed_features(ai_workflows: true)
  end

  it 'updates the decision' do
    expect(response).to be_success

    expect(decision.reload).to have_attributes(
      title: 'Which cache should we use?',
      description: 'The current cache is slow',
      discussion_id: discussion_id,
      source_link: 'https://docs.google.com/document/d/abc123'
    )
  end

  it 'tracks an update event' do
    expect { response }.to trigger_internal_events('work_item_decision_update').with(
      category: ::Gitlab::WorkItems::Instrumentation::TrackingService.name,
      user: current_user,
      project: project,
      namespace: project.project_namespace,
      additional_properties: {
        label: 'Issue',
        property: 'Reporter',
        source: 'internal',
        work_item_id: work_item.id,
        decision_id: decision.id
      }
    )
  end

  it 'locks the decision', :lock_recorder do
    expect { response }.to lock_rows(decision => 'FOR UPDATE')
  end

  context 'when the decision is resolved' do
    let_it_be(:resolver) { create(:user, reporter_of: project) }
    let_it_be_with_reload(:decision) do
      create(:work_item_decision, :resolved, work_item: work_item, resolution_rationale: 'Original rationale')
    end

    let(:params) do
      {
        question: 'Which cache should we use?',
        resolution_rationale: 'Redis is already in the stack',
        resolved_by_id: resolver.id,
        resolving_note_id: resolving_note.id
      }
    end

    it 'updates the resolution without touching resolved_at' do
      expect { response }.not_to change { decision.reload.resolved_at }

      expect(response).to be_success
      expect(decision).to have_attributes(
        title: 'Which cache should we use?',
        resolution_rationale: 'Redis is already in the stack',
        resolved_by: resolver,
        resolving_note: resolving_note
      )
    end

    context 'when resolved_by_id names a user without access' do
      let_it_be(:outsider) { create(:user) }

      let(:params) { { resolved_by_id: outsider.id } }

      it 'returns an error and does not update the decision' do
        expect { response }.not_to change { decision.reload.resolved_by_id }

        expect(response).to be_error
        expect(response.errors).to include('Resolver must have access to the work item')
      end
    end

    context 'when resolved_by_id does not exist' do
      let(:params) { { resolved_by_id: non_existing_record_id } }

      it 'returns an error' do
        expect(response).to be_error
        expect(response.errors).to include('Resolver must have access to the work item')
      end
    end

    context 'when the resolving note belongs to another noteable' do
      let_it_be(:other_note) { create(:note) }

      let(:params) { { resolving_note_id: other_note.id } }

      it 'returns an error and does not update the decision' do
        expect { response }.not_to change { decision.reload.resolving_note_id }.from(nil)

        expect(response).to be_error
        expect(response.errors).to include('Note cannot resolve this decision')
      end
    end

    context 'when the resolving note is a system note' do
      let_it_be(:system_note) { create(:note, :system, noteable: work_item, project: project) }

      let(:params) { { resolving_note_id: system_note.id } }

      it 'returns an error' do
        expect(response).to be_error
        expect(response.errors).to include('Note cannot resolve this decision')
      end
    end

    context 'when the resolving note does not exist' do
      let(:params) { { resolving_note_id: non_existing_record_id } }

      it 'returns an error' do
        expect(response).to be_error
        expect(response.errors).to include('Note cannot resolve this decision')
      end
    end

    context 'when the user cannot read the resolving note' do
      let_it_be(:authored_work_item) { create(:work_item, project: project, author: guest) }
      let_it_be(:internal_note) { create(:note, :confidential, noteable: authored_work_item, project: project) }
      let_it_be_with_reload(:decision) { create(:work_item_decision, :resolved, work_item: authored_work_item) }

      let(:current_user) { guest }
      let(:params) { { resolving_note_id: internal_note.id } }

      it 'returns an error and does not update the decision' do
        expect { response }.not_to change { decision.reload.resolving_note_id }.from(nil)

        expect(response).to be_error
        expect(response.errors).to include('Note cannot resolve this decision')
      end
    end
  end

  context 'when a question is provided' do
    let(:params) { { question: 'Which cache should we use?' } }

    it 'updates the title' do
      expect(response).to be_success
      expect(decision.reload.title).to eq('Which cache should we use?')
    end
  end

  context 'when the decision is archived' do
    let_it_be_with_reload(:decision) { create(:work_item_decision, :archived, work_item: work_item) }

    let(:params) { { question: 'Which cache should we use?' } }

    it 'returns an error without writing to the decision' do
      expect { response }.not_to change { decision.reload.updated_at }

      expect(response).to be_error
      expect(response.errors).to include('Archived decisions cannot be updated')
    end

    it 'does not track an event' do
      expect { response }.not_to trigger_internal_events('work_item_decision_update')
    end
  end

  context 'when options are provided' do
    let_it_be_with_reload(:decision) { create(:work_item_decision, :resolved, work_item: work_item) }
    let_it_be_with_reload(:selected_option) do
      create(:work_item_decision_option, :selected, decision: decision, content: 'Use PostgreSQL')
    end

    let_it_be_with_reload(:other_option) do
      create(:work_item_decision_option, decision: decision, content: 'Use Redis')
    end

    let(:params) do
      {
        options: [
          { id: selected_option.id, selected: false },
          { id: other_option.id, content: 'Use Valkey', description: 'Redis-compatible', selected: true }
        ]
      }
    end

    it 'updates the given options' do
      expect { response }.to change { other_option.reload.updated_at }

      expect(response).to be_success
      expect(selected_option.reload).to have_attributes(content: 'Use PostgreSQL', selected: false)
      expect(other_option).to have_attributes(content: 'Use Valkey', description: 'Redis-compatible', selected: true)
    end

    it 'does not write to the decision' do
      expect { response }.not_to change { decision.reload.slice(:updated_at, :resolved_at) }
    end

    context 'when a decision attribute is provided as well' do
      let(:params) { super().merge(question: 'Which cache should we use?') }

      it 'updates both' do
        expect(response).to be_success
        expect(decision.reload.title).to eq('Which cache should we use?')
        expect(other_option.reload.selected).to be(true)
      end

      context 'when an option is invalid' do
        let(:params) do
          {
            question: 'Which cache should we use?',
            options: [{ id: other_option.id, content: 'a' * (WorkItems::DecisionOption::CONTENT_LENGTH_MAX + 1) }]
          }
        end

        it 'returns the model error and rolls back the decision' do
          expect(response).to be_error
          expect(response.errors).to include(
            "Content is too long (maximum is #{WorkItems::DecisionOption::CONTENT_LENGTH_MAX} characters)"
          )
          expect(decision.reload.title).to eq('Which storage backend should we use?')
        end
      end
    end

    context 'when deselecting the last selected option' do
      let(:params) { { options: [{ id: selected_option.id, selected: false }] } }

      it 'returns an error and does not update the option' do
        expect(response).to be_error
        expect(response.errors).to include('Resolution rationale is required when rejecting all options')
        expect(selected_option.reload.selected).to be(true)
      end

      context 'with a rationale in the same call' do
        let(:params) { super().merge(resolution_rationale: 'None of these work') }

        it 'deselects the option and saves the rationale' do
          expect(response).to be_success
          expect(selected_option.reload.selected).to be(false)
          expect(decision.reload.resolution_rationale).to eq('None of these work')
        end
      end

      context 'when the decision already has a rationale' do
        before do
          decision.update_column(:resolution_rationale, 'None of these work')
        end

        it 'deselects the option' do
          expect(response).to be_success
          expect(selected_option.reload.selected).to be(false)
        end
      end

      context 'when another request deselected an option after it was loaded' do
        before do
          other_option.update_column(:selected, true)
          decision.options.to_a
          WorkItems::DecisionOption.id_in(other_option.id).update_all(selected: false)
        end

        it 'returns an error and does not update the option' do
          expect(response).to be_error
          expect(response.errors).to include('Resolution rationale is required when rejecting all options')
          expect(selected_option.reload.selected).to be(true)
        end
      end
    end

    context 'when the decision is open' do
      let_it_be_with_reload(:decision) { create(:work_item_decision, work_item: work_item) }
      let_it_be_with_reload(:option) { create(:work_item_decision_option, decision: decision) }

      let(:params) { { options: [{ id: option.id, content: 'Use Valkey', description: 'Redis-compatible' }] } }

      it 'updates the option' do
        expect(response).to be_success
        expect(option.reload).to have_attributes(content: 'Use Valkey', description: 'Redis-compatible')
      end

      context 'when selecting an option' do
        let(:params) { { options: [{ id: option.id, selected: true }] } }

        it 'returns an error and does not update the option' do
          expect(response).to be_error
          expect(response.errors).to include('Selected options can only be updated on resolved decisions')
          expect(option.reload.selected).to be(false)
        end
      end
    end

    context 'when an option belongs to another decision' do
      let_it_be(:other_decision_option) { create(:work_item_decision_option) }

      let(:params) { { options: [{ id: other_decision_option.id, content: 'Use Valkey' }] } }

      it 'returns an error and does not update the option' do
        expect(response).to be_error
        expect(response.errors).to include('Options must belong to the decision')
        expect(other_decision_option.reload.content).to eq('Use PostgreSQL')
      end
    end

    context 'when an option has no attribute to update' do
      let(:params) { { options: [{ id: other_option.id }] } }

      it 'returns an error' do
        expect(response).to be_error
        expect(response.errors).to include('Options must include an attribute to update')
      end
    end

    context 'when an option is repeated' do
      let(:params) { { options: [{ id: other_option.id, content: 'A' }, { id: other_option.id, content: 'B' }] } }

      it 'returns an error' do
        expect(response).to be_error
        expect(response.errors).to include('Options must be unique')
      end
    end

    context 'when an option attribute is blank' do
      using RSpec::Parameterized::TableSyntax

      where(:attribute, :value) do
        :content     | ''
        :description | nil
        :selected    | nil
      end

      with_them do
        let(:params) { { options: [{ id: other_option.id, attribute => value }] } }

        it 'returns an error and does not update the option' do
          expect { response }.not_to change { other_option.reload.updated_at }

          expect(response).to be_error
          expect(response.errors).to include("Option #{attribute} can't be blank")
        end
      end
    end

    context 'when the list is empty' do
      let(:params) { { options: [] } }

      it 'returns an error' do
        expect(response).to be_error
        expect(response.errors).to include('No attributes to update')
      end
    end
  end

  context 'when selected option content is provided' do
    let_it_be_with_reload(:decision) { create(:work_item_decision, :resolved, work_item: work_item) }
    let_it_be_with_reload(:selected_option) do
      create(:work_item_decision_option, :selected, decision: decision, content: 'Use PostgreSQL')
    end

    let_it_be_with_reload(:other_option) do
      create(:work_item_decision_option, decision: decision, content: 'Use Redis')
    end

    let(:params) { { selected_option_content: 'Use PostgreSQL 17' } }

    shared_examples 'a written-in option at the options limit' do
      context 'when the decision is at the options limit' do
        before do
          stub_const('WorkItems::Decision::MAX_OPTIONS_PER_DECISION', 2)
          stub_const('WorkItems::Decision::MAX_OPTIONS_WITH_WRITE_IN', 3)
        end

        it 'adds the option past the limit' do
          expect { response }.to change { decision.options.count }.from(2).to(3)

          expect(response).to be_success
        end
      end

      context 'when the decision is one past the options limit' do
        before do
          stub_const('WorkItems::Decision::MAX_OPTIONS_PER_DECISION', 1)
          stub_const('WorkItems::Decision::MAX_OPTIONS_WITH_WRITE_IN', 2)
        end

        it 'returns the model error and does not change the options' do
          expect { response }
            .not_to change { decision.options.reload.map { |option| option.slice(:content, :selected) } }

          expect(response).to be_error
          expect(response.errors).to include('Decision cannot have more than 2 options')
        end
      end
    end

    it 'updates the content of the selected option' do
      expect { response }.not_to change { decision.options.count }

      expect(response).to be_success
      expect(selected_option.reload).to have_attributes(content: 'Use PostgreSQL 17', selected: true)
      expect(other_option.reload).to have_attributes(content: 'Use Redis', selected: false)
    end

    context 'when the decision is one past the options limit' do
      before do
        stub_const('WorkItems::Decision::MAX_OPTIONS_PER_DECISION', 1)
        stub_const('WorkItems::Decision::MAX_OPTIONS_WITH_WRITE_IN', 2)
      end

      it 'still updates the content of the selected option in place' do
        expect { response }.not_to change { decision.options.count }

        expect(response).to be_success
        expect(selected_option.reload).to have_attributes(content: 'Use PostgreSQL 17', selected: true)
      end
    end

    context 'when several options are selected' do
      before do
        other_option.update_column(:selected, true)
      end

      let(:collapsed_options) do
        [
          { 'content' => 'Use PostgreSQL', 'selected' => false },
          { 'content' => 'Use Redis', 'selected' => false },
          { 'content' => 'Use PostgreSQL 17', 'selected' => true }
        ]
      end

      it 'deselects them and adds the content as the only selected option' do
        expect { response }.to change { decision.options.count }.by(1)

        expect(response).to be_success
        expect(decision.options.reload.map { |option| option.slice(:content, :selected) })
          .to match_array(collapsed_options)
      end

      it 'returns the decision with its current options' do
        expect(response.payload[:decision].options.map { |option| option.slice(:content, :selected) })
          .to match_array(collapsed_options)
      end

      it 'does not write to the decision' do
        expect { response }.not_to change { decision.reload.slice(:updated_at, :resolved_at, :resolved_by_id) }
      end

      it 'updates the added option in place on the next edit' do
        response

        expect do
          described_class.new(
            decision: decision.reload, current_user: current_user, params: { selected_option_content: 'Use MySQL' }
          ).execute
        end.not_to change { decision.options.count }

        expect(decision.options.reload.find(&:selected)).to have_attributes(content: 'Use MySQL')
      end

      context 'when another request wrote in a decision after it was loaded' do
        let!(:written_in_option) do
          decision.options.to_a
          WorkItems::Decision.find(decision.id).write_in_option!('Use MySQL')
        end

        it 'updates the written-in option in place' do
          expect { response }.not_to change { decision.options.count }

          expect(response).to be_success
          expect(written_in_option.reload).to have_attributes(content: 'Use PostgreSQL 17', selected: true)
          expect(decision.options.reload.select(&:selected)).to eq([written_in_option])
        end
      end

      it_behaves_like 'a written-in option at the options limit'
    end

    context 'when no option is selected' do
      before do
        selected_option.update_column(:selected, false)
      end

      it 'adds the content as the only selected option' do
        expect { response }.to change { decision.options.count }.by(1)

        expect(response).to be_success
        expect(decision.options.reload.map { |option| option.slice(:content, :selected) }).to match_array([
          { 'content' => 'Use PostgreSQL', 'selected' => false },
          { 'content' => 'Use Redis', 'selected' => false },
          { 'content' => 'Use PostgreSQL 17', 'selected' => true }
        ])
      end

      it_behaves_like 'a written-in option at the options limit'
    end

    context 'when options are provided as well' do
      let(:params) { super().merge(options: [{ id: other_option.id, content: 'Use Valkey' }]) }

      it 'returns an error and does not update the options' do
        expect(response).to be_error
        expect(response.errors).to include('Options and selected option content cannot be updated together')
        expect(other_option.reload.content).to eq('Use Redis')
      end
    end

    context 'when the content is too long' do
      let(:params) { { selected_option_content: 'a' * (WorkItems::DecisionOption::CONTENT_LENGTH_MAX + 1) } }

      it 'returns the model error' do
        expect(response).to be_error
        expect(response.errors).to include(
          "Content is too long (maximum is #{WorkItems::DecisionOption::CONTENT_LENGTH_MAX} characters)"
        )
      end
    end
  end

  context 'when a resolution attribute is provided for an open decision' do
    using RSpec::Parameterized::TableSyntax

    where(:attribute, :value) do
      :resolution_rationale    | 'Redis is already in the stack'
      :resolved_by_id          | lazy { reporter.id }
      :resolving_note_id       | lazy { resolving_note.id }
      :selected_option_content | 'Use PostgreSQL'
    end

    with_them do
      let(:params) { { attribute => value } }

      it 'returns an error and does not update the decision' do
        expect { response }.not_to change { decision.reload.updated_at }

        expect(response).to be_error
        expect(response.errors).to include(
          "#{attribute.to_s.humanize} can only be updated on resolved decisions"
        )
      end
    end
  end

  context 'when several resolution attributes are provided for an open decision' do
    let(:params) { { resolution_rationale: 'Redis is already in the stack', resolved_by_id: reporter.id } }

    it 'names every resolution attribute' do
      expect(response).to be_error
      expect(response.errors).to include(
        'Resolution rationale and Resolved by can only be updated on resolved decisions'
      )
    end
  end

  context 'when only some attributes are provided' do
    let(:params) { { question: 'Which cache should we use?' } }

    it 'leaves the other attributes untouched' do
      expect(response).to be_success

      expect(decision.reload).to have_attributes(
        title: 'Which cache should we use?',
        description: 'Original context',
        discussion_id: original_discussion_id,
        source_link: 'https://example.com/original'
      )
    end
  end

  context 'when params include attributes outside the allowlist' do
    let(:params) { { question: 'Which cache should we use?', resolved_at: Time.current } }

    it 'applies the allowed attributes and never writes the others' do
      expect { response }.not_to change { decision.reload.resolved_at }.from(nil)

      expect(response).to be_success
      expect(decision).to have_attributes(
        title: 'Which cache should we use?',
        description: 'Original context'
      )
    end
  end

  context 'when no updatable attribute is provided' do
    using RSpec::Parameterized::TableSyntax

    where(:params) do
      [
        [{}],
        [{ resolved_at: Time.current }]
      ]
    end

    with_them do
      it 'returns an error without writing to the decision' do
        expect { response }.not_to change { decision.reload.updated_at }

        expect(response).to be_error
        expect(response.errors).to include('No attributes to update')
      end
    end
  end

  context 'when a provided attribute is blank' do
    using RSpec::Parameterized::TableSyntax

    where(:attribute, :value) do
      :question                | nil
      :question                | ''
      :question                | '   '
      :description             | nil
      :description             | ''
      :resolution_rationale    | "\n"
      :discussion_id           | nil
      :source_link             | ''
      :resolved_by_id          | nil
      :resolving_note_id       | ''
      :selected_option_content | ' '
    end

    with_them do
      let(:params) { { attribute => value } }

      it 'returns an error and does not update the decision' do
        expect(response).to be_error
        expect(response.errors).to include("#{attribute.to_s.humanize} can't be blank")
        expect(decision.reload).to have_attributes(title: 'Which storage backend should we use?')
      end
    end
  end

  context 'when several provided attributes are blank' do
    let(:params) { { question: '', description: nil } }

    it 'names every blank attribute' do
      expect(response).to be_error
      expect(response.errors).to include("Question and Description can't be blank")
    end
  end

  context 'when the source link is not a valid URL' do
    let(:params) { { source_link: 'not a url' } }

    it 'returns the model error and does not update the decision' do
      expect(response).to be_error
      expect(response.errors).to include('Source link is blocked: Only allowed schemes are http, https')
      expect(decision.reload.source_link).to eq('https://example.com/original')
    end

    it 'does not track an event' do
      expect { response }.not_to trigger_internal_events('work_item_decision_update')
    end
  end

  context 'when the question is too long' do
    let(:params) { { question: 'a' * (WorkItems::Decision::TITLE_LENGTH_MAX + 1) } }

    it 'returns the model error' do
      expect(response).to be_error
      expect(response.errors).to include(
        "Question is too long (maximum is #{WorkItems::Decision::TITLE_LENGTH_MAX} characters)"
      )
    end
  end

  context 'when user cannot update the work item' do
    let(:current_user) { guest }

    it 'returns an error' do
      expect(response).to be_error
      expect(response.errors).to include('Operation not allowed')
    end

    it 'does not track an event' do
      expect { response }.not_to trigger_internal_events('work_item_decision_update')
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

    let(:decision) { create(:work_item_decision, work_item: incident_work_item) }

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
