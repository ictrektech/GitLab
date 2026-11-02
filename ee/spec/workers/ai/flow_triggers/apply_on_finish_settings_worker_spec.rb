# frozen_string_literal: true

require 'spec_helper'

# Sidekiq runs every job inside a request store, where the identity link lives.
RSpec.describe Ai::FlowTriggers::ApplyOnFinishSettingsWorker, :request_store, feature_category: :dap_triggers do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, :repository, group: subgroup) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:service_account) { create(:composite_identity_service_account_for_project, project: project) }
  let_it_be_with_reload(:work_item) { create(:work_item, :task, project: project) }

  let(:status_on_finish) { 'In progress' }
  let(:ready_merge_requests_on_finish) { false }
  let(:status_rule) { { 'field' => 'status.name', 'operator' => 'in', 'value' => ['To do'] } }
  let(:extra_rules) { [] }
  let(:filter) do
    {
      'work_item' => {
        'rules' => [
          { 'field' => 'action', 'operator' => 'in', 'value' => ['status_changed'] },
          status_rule,
          *extra_rules
        ]
      }
    }
  end

  let(:trigger_active) { true }
  let(:trigger) do
    create(:ai_flow_trigger, project: project, event_types: [::Ai::FlowTrigger::EVENT_TYPES[:work_item]],
      filter: filter, status_on_finish: status_on_finish, active: trigger_active,
      ready_merge_requests_on_finish: ready_merge_requests_on_finish)
  end

  let(:workflow_trait) { :finished }
  let(:workflow_service_account) { service_account }
  let(:trigger_event_type) { :work_item }
  let(:workflow) do
    create(:duo_workflows_workflow, workflow_trait, project: project, user: user, issue_id: work_item.id,
      service_account: workflow_service_account, trigger_flow_trigger: trigger,
      trigger_event_type: trigger_event_type)
  end

  let(:event) { ::Ai::DuoWorkflows::WorkflowFinishedCloudEvent.build(workflow: workflow) }

  before do
    stub_licensed_features(work_item_status: true)
  end

  def status_name
    work_item.reload.status_with_fallback&.name
  end

  def handle_event
    described_class.new.handle_event(event)
  end

  it_behaves_like 'subscribes to event'

  it 'defers only on database-wide health signals' do
    expect(described_class.database_health_check_attrs).to include(
      gitlab_schema: :gitlab_main_org, tables: [], indicators: Gitlab::Database::HealthStatus::GLOBAL_INDICATORS)
  end

  context 'when the session was not started by a trigger' do
    let(:workflow) { create(:duo_workflows_workflow, :finished, project: project, user: user) }

    it_behaves_like 'ignores the published event'
  end

  describe 'the dap_software_factory flag' do
    context 'when it is enabled for the top-level group' do
      before do
        stub_feature_flags(dap_software_factory: group)
      end

      it 'dispatches the event' do
        expect(described_class.dispatch?(event)).to be(true)
      end

      it 'moves the work item' do
        expect { handle_event }.to change { status_name }.to('In progress')
      end
    end

    context 'when it is enabled for the project only' do
      before do
        stub_feature_flags(dap_software_factory: project)
      end

      it 'dispatches the event' do
        expect(described_class.dispatch?(event)).to be(true)
      end

      it 'moves the work item' do
        expect { handle_event }.to change { status_name }.to('In progress')
      end
    end

    context 'when it is disabled' do
      before do
        stub_feature_flags(dap_software_factory: false)
      end

      it_behaves_like 'ignores the published event'

      it 'does not update the work item when the job runs' do
        expect { handle_event }.not_to change { status_name }
      end
    end
  end

  it 'moves the work item to the status of the trigger' do
    expect { handle_event }.to change { status_name }.from('To do').to('In progress')
  end

  it 'publishes the status change as an event caused by the session' do
    published = []
    allow(::Gitlab::EventStore).to receive(:publish).and_wrap_original do |original, published_event|
      published << published_event
      original.call(published_event)
    end

    handle_event

    status_event = published.find { |e| e.is_a?(::WorkItems::StatusChangedEvent) }
    expect(status_event.data).to include(
      gitlab_composite_actor_id: service_account.id,
      gitlab_duo_workflow_id: workflow.id
    )
  end

  it 'does not keep the session identity linked after the writes' do
    handle_event

    expect(::Gitlab::Auth::Identity.currently_linked).to be_nil
  end

  it 'restores a composite identity Set that was in the request store before the job' do
    ::RequestStore.store[::Gitlab::Auth::Identity::COMPOSITE_IDENTITY_USERS_KEY] = Set.new

    handle_event

    expect(::Gitlab::Auth::Identity.currently_linked).to be_nil
  end

  it 'logs the service account, the user, the session, and the trigger' do
    worker = described_class.new
    allow(worker.logger).to receive(:info)

    worker.handle_event(event)

    expect(worker.logger).to have_received(:info).with(hash_including(
      'message' => 'On-finish status set', 'duo_workflow_id' => workflow.id, 'flow_trigger_id' => trigger.id,
      'service_account_id' => service_account.id, 'gl_user_id' => user.id
    ))
  end

  shared_examples 'changes nothing' do
    it 'does not update the work item or merge requests' do
      expect(::WorkItems::UpdateService).not_to receive(:new)
      expect(::MergeRequests::UpdateService).not_to receive(:new)

      handle_event
    end
  end

  shared_examples 'skips the settings' do |reason|
    it_behaves_like 'changes nothing'

    it "logs the reason: #{reason}" do
      worker = described_class.new
      allow(worker.logger).to receive(:info)

      worker.handle_event(event)

      expect(worker.logger).to have_received(:info)
        .with(hash_including('message' => "On-finish settings skipped: #{reason}"))
    end
  end

  context 'when the session no longer exists' do
    before do
      event
      workflow.destroy!
    end

    it_behaves_like 'changes nothing'

    it 'does not dispatch the event' do
      expect(described_class.dispatch?(event)).to be(false)
    end
  end

  context 'when the job runs for a session that a trigger did not start' do
    let(:workflow) { create(:duo_workflows_workflow, :finished, project: project, user: user, issue_id: work_item.id) }

    it_behaves_like 'changes nothing'
  end

  context 'when the session did not finish' do
    let(:workflow_trait) { :running }

    it_behaves_like 'changes nothing'
  end

  context 'when the trigger has no on-finish settings' do
    let(:status_on_finish) { nil }

    it_behaves_like 'changes nothing'
  end

  context 'when the trigger is inactive' do
    let(:trigger_active) { false }

    it_behaves_like 'skips the settings', 'the trigger is inactive'
  end

  context 'when a mention started the session' do
    let(:trigger_event_type) { :mention }

    it_behaves_like 'skips the settings', 'a work item event did not start the session'
  end

  context 'when the session has no work item' do
    let(:workflow) do
      create(:duo_workflows_workflow, :finished, project: project, user: user,
        service_account: service_account, trigger_flow_trigger: trigger, trigger_event_type: :work_item)
    end

    it_behaves_like 'skips the settings', 'the session has no work item'
  end

  context 'when the session service account does not enforce composite identity' do
    let(:workflow_service_account) { create(:service_account, developer_of: project) }

    it_behaves_like 'skips the settings', 'the session has no composite identity'
  end

  context 'when the session has no service account' do
    let(:workflow_service_account) { nil }

    it_behaves_like 'skips the settings', 'the session has no composite identity'
  end

  describe 'flow trigger chaining' do
    # The trigger workers check the flag on the top-level group, so the worker must check the same actor.
    context 'when it is enabled for the top-level group' do
      before do
        stub_feature_flags(ai_flow_trigger_chaining: group)
      end

      it 'moves the work item' do
        expect { handle_event }.to change { status_name }.to('In progress')
      end
    end

    context 'when it is enabled only for the subgroup' do
      before do
        stub_feature_flags(ai_flow_trigger_chaining: subgroup)
      end

      it_behaves_like 'skips the settings', 'flow trigger chaining is disabled'
    end

    context 'when it is enabled only for the project' do
      before do
        stub_feature_flags(ai_flow_trigger_chaining: project)
      end

      it_behaves_like 'skips the settings', 'flow trigger chaining is disabled'
    end

    context 'when it is disabled' do
      before do
        stub_feature_flags(ai_flow_trigger_chaining: false)
      end

      it_behaves_like 'skips the settings', 'flow trigger chaining is disabled'
    end
  end

  describe 'the session that started the chain' do
    using RSpec::Parameterized::TableSyntax

    chain_root_reason =
      'the session chain did not start from a human mention, assignment, work item event, or a chat session'

    let(:ready_merge_requests_on_finish) { true }
    let(:root_event_type) { :work_item }
    let(:root_trigger_source) { :human }
    let(:root_user) { user }
    let(:sessions_between) { 1 }
    let(:root) do
      create(:duo_workflows_workflow, :finished, project: project, user: root_user,
        trigger_source: root_trigger_source, trigger_event_type: root_event_type)
    end

    let(:parent) do
      sessions_between.times.reduce(root) do |parent_workflow, _|
        create(:duo_workflows_workflow, :finished, project: project, user: user, trigger_source: :flow,
          parent_workflow: parent_workflow)
      end
    end

    let(:workflow) do
      create(:duo_workflows_workflow, :finished, project: project, user: user, issue_id: work_item.id,
        service_account: service_account, trigger_flow_trigger: trigger, trigger_event_type: :work_item,
        trigger_source: :flow, parent_workflow: parent)
    end

    let!(:created_merge_request) do
      create(:merge_request, :draft_merge_request, source_project: project, target_project: project).tap do |mr|
        create(:duo_workflows_workflow_merge_request, workflow: workflow, merge_request: mr, link_type: :created)
      end
    end

    context 'when a human event started the chain' do
      where(:root_event_type) { %i[mention assign work_item] }

      with_them do
        it 'applies the settings' do
          expect { handle_event }.to change { status_name }.to('In progress')
          expect(created_merge_request.reload).not_to be_draft
        end
      end
    end

    context 'when a merge conflict started the chain' do
      let(:root_event_type) { :merge_request_code_conflict }

      it_behaves_like 'skips the settings', chain_root_reason
    end

    context 'with a first session that a human event did not start' do
      where(:case_name, :root_event_type, :root_trigger_source, :root_user) do
        'a pipeline event'                 | :pipeline_hooks  | :human  | ref(:user)
        'an automatic reviewer assignment' | :assign_reviewer | :human  | ref(:user)
        'no trigger'                       | nil              | :human  | ref(:user)
        'a system source'                  | :work_item       | :system | ref(:user)
        'a non-human user'                 | :work_item       | :human  | ref(:service_account)
      end

      with_them do
        it_behaves_like 'skips the settings', chain_root_reason
      end
    end

    context 'with the workflow definition of the first session' do
      let(:root) do
        create(:duo_workflows_workflow, :finished, project: project, user: root_user,
          workflow_definition: root_definition, trigger_source: root_trigger_source,
          trigger_event_type: root_event_type)
      end

      # A `/flow:` command in the chat starts the flow as a child of the chat session.
      context 'when a human user started the chain from a chat session' do
        where(:root_definition) { %w[chat duo_planner/v1] }

        with_them do
          let(:root_event_type) { nil }

          it 'applies the settings' do
            expect { handle_event }.to change { status_name }.to('In progress')
            expect(created_merge_request.reload).not_to be_draft
          end
        end
      end

      context 'when the first session is not a chat session that a human user started' do
        where(:case_name, :root_definition, :root_event_type, :root_trigger_source, :root_user) do
          'a code review'          | 'code_review/v1' | nil                          | :human  | ref(:user)
          'a chat, system event'   | 'chat'           | :merge_request_code_conflict | :human  | ref(:user)
          'a chat, system source'  | 'chat'           | nil                          | :system | ref(:user)
          'a chat, non-human user' | 'chat'           | nil                          | :human  | ref(:service_account)
        end

        with_them do
          it_behaves_like 'skips the settings', chain_root_reason
        end
      end
    end

    context 'when the chain is longer than the walk' do
      let(:sessions_between) { ::Ai::FlowTriggers::CallerContext::MAX_TRIGGER_DEPTH }

      it_behaves_like 'skips the settings', chain_root_reason
    end

    context 'when the parent session was deleted' do
      let(:sessions_between) { 0 }

      before do
        workflow
        root.delete
      end

      it_behaves_like 'skips the settings', chain_root_reason
    end
  end

  describe 'the trigger filter' do
    # A rule on a field that the data lacks compares against nil, so a negative operator passes.
    it 'is re-checked with a value for every allowed work item field' do
      data = nil
      allow(::Ai::FlowTriggers::FilterEvaluator).to receive(:new).and_wrap_original do |original, **kwargs|
        data = kwargs[:data]
        original.call(**kwargs)
      end

      handle_event

      ::Ai::FlowTrigger::ALLOWED_FILTER_FIELDS['work_item'].each_key do |field|
        expect(data.dig(*field.split('.'))).not_to be_nil, "the filter re-check data has no value for #{field}"
      end
    end

    context 'when the work item no longer matches it' do
      let(:status_rule) { { 'field' => 'status.name', 'operator' => 'in', 'value' => ['Done'] } }

      it_behaves_like 'skips the settings', 'the work item no longer matches the trigger filter'
    end

    context 'when the work item type has no status' do
      let_it_be(:incident) { create(:work_item, :incident, project: project) }

      let(:workflow) do
        create(:duo_workflows_workflow, :finished, project: project, user: user, issue_id: incident.id,
          service_account: service_account, trigger_flow_trigger: trigger, trigger_event_type: :work_item)
      end

      it_behaves_like 'skips the settings', 'the work item no longer matches the trigger filter'
    end

    context 'with a work_item_type_id rule for the type of the work item' do
      let(:extra_rules) do
        [{ 'field' => 'work_item_type_id', 'operator' => 'in', 'value' => [work_item.work_item_type_id] }]
      end

      it 'moves the work item' do
        expect { handle_event }.to change { status_name }.to('In progress')
      end
    end

    context 'with a work_item_type_id rule for another type' do
      let(:issue_type_id) { ::WorkItems::TypesFramework::Provider.new(project).find_by_base_type(:issue).id }
      let(:extra_rules) { [{ 'field' => 'work_item_type_id', 'operator' => 'in', 'value' => [issue_type_id] }] }

      it_behaves_like 'skips the settings', 'the work item no longer matches the trigger filter'
    end

    context 'with a software_factory_enabled rule' do
      let(:extra_rules) { [{ 'field' => 'software_factory_enabled', 'operator' => 'in', 'value' => [true] }] }

      context 'when the work item has the marker' do
        before do
          create(:work_item_agent_plan, work_item: work_item, ai_planning_enabled: true)
        end

        it 'moves the work item' do
          expect { handle_event }.to change { status_name }.to('In progress')
        end
      end

      context 'when the work item has no agent plan' do
        it_behaves_like 'skips the settings', 'the work item no longer matches the trigger filter'
      end
    end

    context 'with a negative operator that still matches' do
      let(:extra_rules) { [{ 'field' => 'status.name', 'operator' => 'ne', 'value' => 'Done' }] }

      it 'moves the work item' do
        expect { handle_event }.to change { status_name }.to('In progress')
      end
    end

    context 'with a match-any group of status rules' do
      let(:extra_rules) do
        [
          {
            'type' => 'group',
            'match' => 'any',
            'rules' => [
              { 'field' => 'status.name', 'operator' => 'eq', 'value' => 'Done' },
              { 'field' => 'status.name', 'operator' => 'eq', 'value' => 'To do' }
            ]
          }
        ]
      end

      it 'moves the work item' do
        expect { handle_event }.to change { status_name }.to('In progress')
      end
    end
  end

  describe 'authorization' do
    let(:ready_merge_requests_on_finish) { true }
    let!(:created_merge_request) do
      create(:merge_request, :draft_merge_request, source_project: project, target_project: project).tap do |mr|
        create(:duo_workflows_workflow_merge_request, workflow: workflow, merge_request: mr, link_type: :created)
      end
    end

    shared_examples 'writes nothing' do
      it 'keeps the status and the draft' do
        expect { handle_event }.not_to change { status_name }
        expect(created_merge_request.reload).to be_draft
      end
    end

    context 'when the service account has no access to the project' do
      let(:workflow_service_account) { create(:user, :service_account, composite_identity_enforced: true) }

      it_behaves_like 'writes nothing'
    end

    context 'when the user who started the session has no access to the project' do
      let(:workflow) do
        create(:duo_workflows_workflow, :finished, project: project, user: create(:user),
          issue_id: work_item.id, service_account: service_account, trigger_flow_trigger: trigger,
          trigger_event_type: :work_item)
      end

      it_behaves_like 'writes nothing'
    end

    context 'when the service account may not set the status' do
      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?)
          .with(service_account, :set_work_item_metadata, work_item).and_return(false)
      end

      it 'keeps the status and logs the reason' do
        worker = described_class.new
        allow(worker.logger).to receive(:info)

        expect { worker.handle_event(event) }.not_to change { status_name }
        expect(worker.logger).to have_received(:info)
          .with(hash_including('message' => 'On-finish status not set: not allowed'))
      end
    end
  end

  context 'when the status name is not in the lifecycle' do
    let(:status_on_finish) { 'No such status' }

    it 'does not change the status' do
      expect { handle_event }.not_to change { status_name }
    end
  end

  context 'when the work item cannot be re-read after the update' do
    before do
      allow(::WorkItem).to receive(:find_by_id).and_call_original
      allow(::WorkItem).to receive(:find_by_id).with(work_item.id).and_return(nil)
    end

    it 'logs that the status is not set' do
      worker = described_class.new
      allow(worker.logger).to receive(:info)

      worker.handle_event(event)

      expect(worker.logger).to have_received(:info)
        .with(hash_including('message' => 'On-finish status not set', 'current_status' => nil))
    end
  end

  context 'with ready_merge_requests_on_finish' do
    let(:ready_merge_requests_on_finish) { true }

    let!(:created_merge_request) { draft_merge_request('created', link_type: :created) }
    let!(:source_merge_request) { draft_merge_request('source', link_type: :source) }
    let!(:unlinked_merge_request) { draft_merge_request('unlinked') }
    let!(:closed_merge_request) { draft_merge_request('closed', link_type: :created, state: :closed) }

    def draft_merge_request(source_branch, link_type: nil, state: :opened)
      create(:merge_request, :draft_merge_request, state, source_project: project, target_project: project,
        source_branch: source_branch).tap do |mr|
        if link_type
          create(:duo_workflows_workflow_merge_request, workflow: workflow, merge_request: mr, link_type: link_type)
        end
      end
    end

    it 'marks only the open merge requests that the session created as ready' do
      handle_event

      expect(created_merge_request.reload).not_to be_draft
      expect(source_merge_request.reload).to be_draft
      expect(unlinked_merge_request.reload).to be_draft
      expect(closed_merge_request.reload).to be_draft
    end

    it 'also sets the status' do
      expect { handle_event }.to change { status_name }.to('In progress')
    end

    context 'when the service account may not mark a created merge request as ready' do
      before do
        allow(Ability).to receive(:allowed?).and_call_original
        allow(Ability).to receive(:allowed?)
          .with(service_account, :update_merge_request, created_merge_request).and_return(false)
      end

      it 'keeps the merge request a Draft and the status' do
        expect { handle_event }.not_to change { status_name }
        expect(created_merge_request.reload).to be_draft
      end
    end

    context 'when auto-merge is set on a created merge request' do
      let!(:created_merge_request) do
        create(:merge_request, :draft_merge_request, :merge_when_checks_pass, source_project: project,
          target_project: project, source_branch: 'auto-merge').tap do |mr|
          create(:duo_workflows_workflow_merge_request, workflow: workflow, merge_request: mr, link_type: :created)
        end
      end

      it 'keeps the merge request a Draft and the status' do
        worker = described_class.new
        allow(worker.logger).to receive(:info)

        expect { worker.handle_event(event) }.not_to change { status_name }
        expect(created_merge_request.reload).to be_draft
        expect(worker.logger).to have_received(:info).with(hash_including(
          'message' => 'On-finish merge request not marked as ready: auto-merge is set',
          'merge_request_id' => created_merge_request.id
        ))
      end
    end

    context 'when a created merge request is not saved' do
      before do
        allow_next_instance_of(::MergeRequests::UpdateService) do |service|
          allow(service).to receive(:execute) do |merge_request|
            merge_request.tap { |mr| mr.errors.add(:base, 'Save failed') }
          end
        end
      end

      it 'keeps the status and logs the errors' do
        worker = described_class.new
        allow(worker.logger).to receive(:info)

        expect { worker.handle_event(event) }.not_to change { status_name }
        expect(worker.logger).to have_received(:info).with(hash_including(
          'message' => 'On-finish merge request not marked as ready',
          'merge_request_id' => created_merge_request.id, 'errors' => 'Save failed'
        ))
      end
    end

    context 'without status_on_finish' do
      let(:status_on_finish) { nil }

      it 'marks the merge request as ready and keeps the status' do
        expect { handle_event }.not_to change { status_name }
        expect(created_merge_request.reload).not_to be_draft
      end
    end

    context 'when marking a merge request as ready fails once' do
      it 'raises, keeps the status, and completes on retry' do
        call_count = 0
        allow(::MergeRequests::UpdateService).to receive(:new).and_wrap_original do |original, *args, **kwargs|
          call_count += 1
          raise StandardError, 'transient' if call_count == 1

          original.call(*args, **kwargs)
        end

        expect { handle_event }.to raise_error(StandardError, 'transient')
        expect(status_name).to eq('To do')

        handle_event

        expect(created_merge_request.reload).not_to be_draft
        expect(status_name).to eq('In progress')
      end
    end
  end
end
