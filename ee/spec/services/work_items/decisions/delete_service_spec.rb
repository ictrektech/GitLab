# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Decisions::DeleteService, feature_category: :team_planning do
  let_it_be(:project) { create(:project) }
  let_it_be(:reporter) { create(:user, reporter_of: project) }
  let_it_be(:guest) { create(:user, guest_of: project) }
  # refind: get_widget memoizes per instance, so a shared work item would
  # serve stale availability under the license/flag stubs below
  let_it_be_with_refind(:work_item) { create(:work_item, project: project) }

  let(:decision) { create(:work_item_decision, work_item: work_item) }
  let(:current_user) { reporter }

  subject(:response) { described_class.new(decision: decision, current_user: current_user).execute }

  before do
    stub_licensed_features(ai_workflows: true)
  end

  it 'deletes the decision and returns it' do
    decision

    expect { response }.to change { WorkItems::Decision.count }.by(-1)

    expect(response).to be_success
    expect(response.payload[:decision]).to eq(decision)
    expect(response.payload[:decision]).to be_destroyed
  end

  it 'tracks a destroy event' do
    expect { response }.to trigger_internal_events('work_item_decision_destroy_unresolved').with(
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

  it 'deletes the options with the decision' do
    create_list(:work_item_decision_option, 2, decision: decision)

    expect { response }.to change { WorkItems::DecisionOption.count }.by(-2)
  end

  context 'when the decision is resolved' do
    let(:decision) { create(:work_item_decision, :resolved, work_item: work_item) }

    it 'returns an error and keeps the decision' do
      decision

      expect { response }.not_to change { WorkItems::Decision.count }

      expect(response).to be_error
      expect(response.errors).to include('Resolved decisions cannot be deleted')
    end

    it 'does not track an event' do
      expect { response }.not_to trigger_internal_events('work_item_decision_destroy_unresolved')
    end
  end

  context 'when another request resolved the decision after it was loaded' do
    before do
      WorkItems::Decision.id_in(decision.id).update_all(resolved_at: Time.current, resolved_by_id: reporter.id)
    end

    it 'returns an error and keeps the decision' do
      expect { response }.not_to change { WorkItems::Decision.count }

      expect(response).to be_error
      expect(response.errors).to include('Resolved decisions cannot be deleted')
    end
  end

  it 'locks the decision', :lock_recorder do
    expect { response }.to lock_rows(decision => 'FOR UPDATE')
  end

  context 'when the decision is archived' do
    let(:decision) { create(:work_item_decision, :archived, work_item: work_item) }

    it 'returns an error and keeps the decision' do
      decision

      expect { response }.not_to change { WorkItems::Decision.count }

      expect(response).to be_error
      expect(response.errors).to include('Archived decisions cannot be deleted')
    end
  end

  context 'when user cannot update the work item' do
    let(:current_user) { guest }

    it 'returns an error and keeps the decision' do
      decision

      expect { response }.not_to change { WorkItems::Decision.count }

      expect(response).to be_error
      expect(response.errors).to include('Operation not allowed')
    end

    it 'does not track an event' do
      expect { response }.not_to trigger_internal_events('work_item_decision_destroy_unresolved')
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
