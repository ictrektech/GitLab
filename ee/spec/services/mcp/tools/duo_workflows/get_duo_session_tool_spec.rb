# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::DuoWorkflows::GetDuoSessionTool, feature_category: :mcp_server do
  let_it_be(:ai_settings, freeze: false) { create(:namespace_ai_settings, duo_workflow_mcp_enabled: true) }
  let_it_be(:group, freeze: false) { create(:group, ai_settings: ai_settings) }
  let_it_be(:user, freeze: false) { create(:user, developer_of: group) }
  let_it_be(:other_user, freeze: false) { create(:user, developer_of: group) }
  let_it_be(:project, freeze: false) { create(:project, :repository, group: group) }

  let(:workflow) { create(:duo_workflows_workflow, user: user, project: project) }
  let(:params) { { workflow_id: workflow.id } }
  let(:tool) { described_class.new(current_user: user, params: params, access_token: nil) }
  let(:artifact_limit) { ::Mcp::Tools::Concerns::CursorPagination::DEFAULT_PAGE_SIZE }

  before do
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(any_args).and_return(true)
    # rubocop:disable RSpec/AnyInstanceOf -- Duo Agent Platform authorization is evaluated by the workflow policy.
    allow_any_instance_of(User).to receive_messages(allowed_to_use?: true, allowed_to_use_for_resource?: true)
    # rubocop:enable RSpec/AnyInstanceOf
  end

  describe '#build_variables' do
    it 'converts the numeric workflow ID to the GraphQL global ID' do
      expect(tool.build_variables).to eq(
        workflowId: Gitlab::GlobalId.build(model_name: ::Ai::DuoWorkflows::Workflow.name, id: workflow.id).to_s,
        artifactLimit: artifact_limit
      )
    end
  end

  describe '#message_history_variables' do
    it 'asks for the newest messages only' do
      expect(tool.message_history_variables).to eq(
        workflowId: Gitlab::GlobalId.build(model_name: ::Ai::DuoWorkflows::Workflow.name, id: workflow.id).to_s,
        messageLimit: described_class::HISTORY_MESSAGE_LIMIT
      )
    end
  end

  describe '#execute' do
    it 'returns compact progress and a polling hint for a running session' do
      workflow.update!(status: status_value(:running))
      add_checkpoint(workflow, [{ content: 'Working on the request', role: 'assistant', message_type: 'agent' }])

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: session_metadata('running', poll_after_seconds: 30)
      )
      expect(result[:content]).to eq([
        {
          type: 'text',
          text: "Status: running. Poll again in 30 seconds.\n\nLatest agent update: Working on the request"
        }
      ])
    end

    it 'returns the running fallback when the checkpoint contains no agent messages' do
      workflow.update!(status: status_value(:running))
      add_checkpoint(workflow, [{ content: 'Please continue.', role: 'user', message_type: 'user' }])

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: session_metadata('running', poll_after_seconds: 30),
        content: [{ type: 'text', text: 'Status: running. Poll again in 30 seconds.' }]
      )
    end

    it 'returns the final answer when a finished session ends with an empty agent turn' do
      workflow.update!(status: status_value(:finished))
      add_checkpoint(workflow, [
        { content: 'Here is the full answer.', role: 'assistant', message_type: 'agent' },
        { content: '', role: 'assistant', message_type: 'agent' }
      ])

      result = tool.execute

      expect(result).to include(
        isError: false,
        content: [{ type: 'text', text: 'Here is the full answer.' }]
      )
    end

    it 'returns the final answer when a finished session ends with a tool-only turn' do
      workflow.update!(status: status_value(:finished))
      add_checkpoint(workflow, [
        { content: 'Here is the full answer.', role: 'assistant', message_type: 'agent' },
        { content: 'read_file', message_type: 'tool' }
      ])

      result = tool.execute

      expect(result).to include(
        isError: false,
        content: [{ type: 'text', text: 'Here is the full answer.' }]
      )
    end

    it 'returns the latest agent answer for a finished session when the latest message is not from the agent' do
      workflow.update!(status: status_value(:finished))
      add_checkpoint(workflow, [
        { content: 'The change is complete.', role: 'assistant', message_type: 'agent' },
        { content: 'Thanks', role: 'user', message_type: 'user' }
      ])

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: session_metadata('finished'),
        content: [{ type: 'text', text: 'The change is complete.' }]
      )
    end

    it 'returns the finished fallback when the session has no checkpoint at all' do
      workflow.update!(status: status_value(:finished))

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: session_metadata('finished'),
        content: [{ type: 'text', text: 'Session finished, but no final answer was produced.' }]
      )
    end

    context 'with a flow-shaped chat log' do
      # Flow sessions tag the agent with message_type 'agent' and carry no role.
      it 'returns the final answer for a finished session' do
        workflow.update!(status: status_value(:finished))
        add_checkpoint(workflow, [
          { content: 'Ran the migration.', message_type: 'agent' },
          { content: 'read_file', message_type: 'tool' }
        ])

        result = tool.execute

        expect(result).to include(
          isError: false,
          content: [{ type: 'text', text: 'Ran the migration.' }]
        )
      end

      it 'returns compact progress for a running session' do
        workflow.update!(status: status_value(:running))
        add_checkpoint(workflow, [{ content: 'Working on the request', message_type: 'agent' }])

        result = tool.execute

        expect(result[:content]).to eq([
          {
            type: 'text',
            text: "Status: running. Poll again in 30 seconds.\n\nLatest agent update: Working on the request"
          }
        ])
      end

      it 'returns the finished fallback when no agent message is present' do
        workflow.update!(status: status_value(:finished))
        add_checkpoint(workflow, [
          { content: 'Run the migration', message_type: 'user' },
          { content: 'read_file', message_type: 'tool' }
        ])

        result = tool.execute

        expect(result).to include(
          isError: false,
          content: [{ type: 'text', text: 'Session finished, but no final answer was produced.' }]
        )
      end
    end

    it 'identifies input required as a completed chat turn' do
      workflow.update!(status: status_value(:input_required))
      add_checkpoint(workflow, [{ content: 'How should I proceed?', role: 'assistant', message_type: 'agent' }])

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: session_metadata('input_required', turn_complete: true),
        content: [{ type: 'text', text: 'How should I proceed?' }]
      )
    end

    it 'identifies an idle session as a completed turn' do
      workflow.update!(status: status_value(:idle))
      add_checkpoint(workflow, [{ content: 'Done for now.', role: 'assistant', message_type: 'agent' }])

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: session_metadata('idle', turn_complete: true),
        content: [{ type: 'text', text: 'Done for now.' }]
      )
    end

    it 'explains how to resume a session awaiting tool-call approval' do
      workflow.update!(status: status_value(:tool_call_approval_required))
      add_checkpoint(workflow, [{ content: 'I need approval.', role: 'assistant', message_type: 'agent' }])

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: session_metadata('tool_call_approval_required', awaiting_approval: true)
      )
      expect(result.dig(:content, 0, :text)).to include(
        'I need approval.',
        'Polling will NOT move it forward.',
        "send_duo_session_input with workflow_id=#{workflow.id}",
        'human_approval=true to approve, or false to reject'
      )
    end

    it 'explains how to resume a session awaiting plan approval' do
      workflow.update!(status: status_value(:plan_approval_required))
      add_checkpoint(workflow, [{ content: 'Here is my plan.', role: 'assistant', message_type: 'agent' }])

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: session_metadata('plan_approval_required', awaiting_approval: true)
      )
      expect(result.dig(:content, 0, :text)).to include(
        'Here is my plan.',
        'Polling will NOT move it forward.',
        "send_duo_session_input with workflow_id=#{workflow.id}"
      )
    end

    it 'tells the agent that polling will not move a paused session forward' do
      workflow.update!(status: status_value(:paused))
      add_checkpoint(workflow, [{ content: 'Pausing here.', role: 'assistant', message_type: 'agent' }])

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: session_metadata('paused', paused: true)
      )
      expect(result.dig(:content, 0, :text)).to include(
        'Pausing here.',
        'Polling will NOT move it forward',
        "See #{workflow.web_url} to resume it."
      )
      expect(result[:structuredContent]).not_to include('poll_after_seconds')
    end

    it 'returns a session URL for a stopped session' do
      workflow.update!(status: status_value(:stopped))

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: session_metadata('stopped'),
        content: [{ type: 'text', text: "Session stopped. See #{workflow.web_url} for details." }]
      )
    end

    it 'returns the GraphQL not-found error for an unknown workflow' do
      result = described_class.new(
        current_user: user, params: { workflow_id: non_existing_record_id }, access_token: nil
      ).execute

      expect(result).to include(isError: true)
      expect(result.dig(:content, 0, :text)).to include('Workflow not found')
    end

    # The resolver answers not-found rather than forbidden so the response cannot
    # be used to probe which workflow IDs exist.
    it 'hides a workflow owned by another user behind the not-found error' do
      other_workflow = create(:duo_workflows_workflow, user: other_user, project: project)

      result = described_class.new(
        current_user: user, params: { workflow_id: other_workflow.id }, access_token: nil
      ).execute

      expect(result).to include(isError: true)
      expect(result.dig(:content, 0, :text)).to include('Workflow not found')
    end
  end

  describe 'polling hint' do
    it 'allows longer for a session still waiting for its CI job to start' do
      workflow.update!(status: status_value(:created))

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: session_metadata('created', poll_after_seconds: 120),
        content: [{ type: 'text', text: 'Status: created. Poll again in 120 seconds.' }]
      )
    end

    it 'shortens once the session is running' do
      workflow.update!(status: status_value(:running))

      result = tool.execute

      expect(result[:structuredContent]).to include('poll_after_seconds' => 30)
      expect(result.dig(:content, 0, :text)).to eq('Status: running. Poll again in 30 seconds.')
    end
  end

  describe 'what the session produced' do
    let_it_be(:created_merge_request) { create(:merge_request, source_project: project, title: 'Add the parser') }
    let_it_be(:created_work_item) { create(:work_item, project: project, title: 'Follow up on the parser') }
    let_it_be(:created_note) do
      create(:note_on_merge_request, project: project, noteable: created_merge_request,
        note: 'Looks good, one nit on the parser.')
    end

    it 'returns a merge request the session created' do
      workflow.update!(status: status_value(:finished))
      add_checkpoint(workflow, [{ content: 'Opened the merge request.', role: 'assistant', message_type: 'agent' }])
      link_merge_request(created_merge_request, :created)

      result = tool.execute

      expect(result[:structuredContent]).to include(
        'created_merge_requests' => [
          { 'title' => 'Add the parser', 'url' => Gitlab::UrlBuilder.build(created_merge_request) }
        ]
      )
      expect(result.dig(:content, 0, :text)).to eq(
        "Opened the merge request.\n\nMerge request created: #{Gitlab::UrlBuilder.build(created_merge_request)}"
      )
    end

    it 'returns a work item the session created' do
      workflow.update!(status: status_value(:finished))
      add_checkpoint(workflow, [{ content: 'Filed the follow-up.', role: 'assistant', message_type: 'agent' }])
      link_work_item(created_work_item, :created)

      result = tool.execute

      expect(result[:structuredContent]).to include(
        'created_work_items' => [
          { 'title' => 'Follow up on the parser', 'url' => Gitlab::UrlBuilder.build(created_work_item) }
        ]
      )
      expect(result.dig(:content, 0, :text)).to eq(
        "Filed the follow-up.\n\nWork item created: #{Gitlab::UrlBuilder.build(created_work_item)}"
      )
    end

    it 'returns a comment the session posted' do
      workflow.update!(status: status_value(:finished))
      add_checkpoint(workflow, [{ content: 'Left my review.', role: 'assistant', message_type: 'agent' }])
      link_note(created_note, :created)

      result = tool.execute

      expect(result[:structuredContent]).to include(
        'created_notes' => [
          { 'body' => 'Looks good, one nit on the parser.', 'url' => Gitlab::UrlBuilder.build(created_note) }
        ]
      )
      expect(result.dig(:content, 0, :text)).to eq(
        "Left my review.\n\nComment posted: #{Gitlab::UrlBuilder.build(created_note)}"
      )
    end

    it 'previews a long comment rather than returning it whole' do
      workflow.update!(status: status_value(:finished))
      add_checkpoint(workflow, [{ content: 'Left my review.', role: 'assistant', message_type: 'agent' }])
      link_note(create(:note_on_merge_request, project: project, noteable: created_merge_request,
        note: 'a' * 400), :created)

      body = tool.execute.dig(:structuredContent, 'created_notes', 0, 'body')

      expect(body.length).to eq(160)
      expect(body).to end_with('...')
    end

    it 'returns every key as an empty array when the session produced nothing' do
      workflow.update!(status: status_value(:finished))
      add_checkpoint(workflow, [{ content: 'Nothing to change.', role: 'assistant', message_type: 'agent' }])

      result = tool.execute

      expect(result[:structuredContent]).to include(
        'created_merge_requests' => [], 'created_work_items' => [], 'created_notes' => []
      )
      expect(result.dig(:content, 0, :text)).to eq('Nothing to change.')
    end

    it 'ignores the merge request, work item and comment the session was started from' do
      workflow.update!(status: status_value(:finished))
      add_checkpoint(workflow, [{ content: 'Reviewed it.', role: 'assistant', message_type: 'agent' }])
      link_merge_request(created_merge_request, :source)
      link_work_item(created_work_item, :source)
      link_note(created_note, :triggered)

      result = tool.execute

      expect(result[:structuredContent]).to include(
        'created_merge_requests' => [], 'created_work_items' => [], 'created_notes' => []
      )
    end

    context 'when the caller may read the session but not what it created' do
      let_it_be(:auditor) { create(:user) }
      let_it_be(:auditor_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: group) }
      let_it_be(:auditor_membership) do
        create(:group_member, :guest, member_role: auditor_role, user: auditor, group: group)
      end

      before do
        stub_licensed_features(custom_roles: true, project_level_compliance_dashboard: true)
      end

      it 'omits them rather than reporting that they exist' do
        workflow.update!(status: status_value(:finished))
        add_checkpoint(workflow, [{ content: 'Opened the merge request.', role: 'assistant',
                                    message_type: 'agent' }])
        link_merge_request(created_merge_request, :created)
        link_note(created_note, :created)

        result = described_class.new(current_user: auditor, params: params, access_token: nil).execute

        expect(result).to include(isError: false)
        expect(result[:structuredContent]).to include(
          'created_merge_requests' => [], 'created_notes' => []
        )
        expect(result.dig(:content, 0, :text)).to eq('Opened the merge request.')
      end
    end

    it 'returns the most recent comments and says the list was cut off' do
      workflow.update!(status: status_value(:finished))
      add_checkpoint(workflow, [{ content: 'Reviewed it.', role: 'assistant', message_type: 'agent' }])
      notes = Array.new(artifact_limit + 2) do |i|
        create(:note_on_merge_request, project: project, noteable: created_merge_request, note: "finding #{i}")
      end
      notes.each { |note| link_note(note, :created) }

      result = tool.execute

      bodies = result.dig(:structuredContent, 'created_notes').map { |n| n['body'] }
      expect(bodies.size).to eq(artifact_limit)
      expect(bodies.first).to eq(notes.last.note)
      expect(result[:structuredContent]).to include(
        'artifacts_truncated' => ['created_notes'], 'artifact_limit' => artifact_limit
      )
      expect(result.dig(:content, 0, :text)).to include(
        "Only the #{artifact_limit} most recent are listed for created_notes.",
        'Call get_merge_request with include: ["notes"] for every comment on a merge request.'
      )
    end

    it 'names only the list that was cut and omits the comment tool when comments fit' do
      workflow.update!(status: status_value(:finished))
      add_checkpoint(workflow, [{ content: 'Filed them.', role: 'assistant', message_type: 'agent' }])
      create_list(:work_item, artifact_limit + 2, project: project).each do |work_item|
        link_work_item(work_item, :created)
      end
      link_note(created_note, :created)

      result = tool.execute

      expect(result.dig(:structuredContent, 'created_work_items').size).to eq(artifact_limit)
      expect(result[:structuredContent]).to include('artifacts_truncated' => ['created_work_items'])
      text = result.dig(:content, 0, :text)
      expect(text).to include("Only the #{artifact_limit} most recent are listed for created_work_items.")
      expect(text).not_to include('get_merge_request')
    end

    it 'names a tool that tools/list still advertises' do
      expect(::Mcp::Tools::Manager.new.list_tools.fetch('get_merge_request')).not_to be_unlisted
    end

    it 'says nothing about truncation when the lists fit' do
      workflow.update!(status: status_value(:finished))
      add_checkpoint(workflow, [{ content: 'Reviewed it.', role: 'assistant', message_type: 'agent' }])
      link_note(created_note, :created)

      result = tool.execute

      expect(result[:structuredContent].keys).not_to include('artifacts_truncated', 'artifact_limit')
      expect(result.dig(:content, 0, :text)).not_to include('most recent')
    end

    it 'reports what a running session has produced so far' do
      workflow.update!(status: status_value(:running))
      link_merge_request(created_merge_request, :created)

      result = tool.execute

      expect(result.dig(:content, 0, :text)).to eq(
        "Status: running. Poll again in 30 seconds.\n\nMerge request created: #{Gitlab::UrlBuilder.build(created_merge_request)}"
      )
    end
  end

  describe 'when the session failed' do
    let_it_be(:reason) { 'The WebSocket connection was rejected with HTTP 401 Unauthorized.' }

    let(:job) { create(:ci_build, :failed, project: project) }
    let(:job_url) { Gitlab::UrlBuilder.build(job) }

    before do
      workflow.update!(status: status_value(:failed), summary: reason)
    end

    it 'returns the recorded reason and the failing job' do
      add_checkpoint(workflow, [{ content: 'Working on the request', role: 'assistant', message_type: 'agent' }])
      link_workload(job)

      result = tool.execute

      expect(result).to include(
        isError: false,
        structuredContent: session_metadata('failed', failure_reason: reason, job_url: job_url),
        content: [{
          type: 'text',
          text: "Session failed: #{reason}\n\nJob log: #{job_url}\n\nSee #{workflow.web_url} for details."
        }]
      )
    end

    it 'says no reason was recorded when there is none' do
      workflow.update!(summary: nil)
      add_checkpoint(workflow, [{ content: 'Working on the request', role: 'assistant', message_type: 'agent' }])
      link_workload(job)

      result = tool.execute

      expect(result[:structuredContent]).to include('failure_reason' => nil, 'job_url' => job_url)
      expect(result.dig(:content, 0, :text)).to start_with("Session failed. No reason was recorded.\n\n")
    end

    it 'says the session can be started again when the agent never started' do
      link_workload(job)

      result = tool.execute

      expect(result.dig(:content, 0, :text)).to eq(
        "Session failed: #{reason}\n\n#{described_class::FAILED_BEFORE_START}\n\n" \
          "Job log: #{job_url}\n\nSee #{workflow.web_url} for details."
      )
    end

    it 'does not say the session can be started again once its checkpoints are past retention' do
      workflow.update!(created_at: 31.days.ago)

      result = tool.execute

      expect(result.dig(:content, 0, :text)).not_to include(described_class::FAILED_BEFORE_START)
    end

    it 'says no job ran when the session never got one' do
      result = tool.execute

      expect(result[:structuredContent]).to include('job_url' => nil)
      expect(result.dig(:content, 0, :text)).to include('No CI job ran for this session.')
    end

    context 'when the caller may read the session but not its job' do
      let_it_be(:auditor) { create(:user) }
      let_it_be(:auditor_role) { create(:member_role, :guest, :read_agent_artifacts, namespace: group) }
      let_it_be(:auditor_membership) do
        create(:group_member, :guest, member_role: auditor_role, user: auditor, group: group)
      end

      before do
        stub_licensed_features(custom_roles: true, project_level_compliance_dashboard: true)
        project.update!(public_builds: false)
      end

      it 'returns the reason but not the job URL' do
        add_checkpoint(workflow, [{ content: 'Working on the request', role: 'assistant', message_type: 'agent' }])
        link_workload(job)

        result = described_class.new(current_user: auditor, params: params, access_token: nil).execute

        expect(result[:structuredContent]).to include('failure_reason' => reason, 'job_url' => nil)
        expect(result.dig(:content, 0, :text)).to eq(
          "Session failed: #{reason}\n\nYou do not have access to the job log.\n\n" \
            "See #{workflow.web_url} for details."
        )
      end
    end
  end

  describe 'message truncation' do
    let(:long_message) { 'a' * 600 }

    it 'truncates a running progress update' do
      workflow.update!(status: status_value(:running))
      add_checkpoint(workflow, [{ content: long_message, role: 'assistant', message_type: 'agent' }])

      result = tool.execute

      expect(result.dig(:content, 0, :text)).to eq(
        "Status: running. Poll again in 30 seconds.\n\nLatest agent update: #{long_message.truncate(500)}"
      )
    end

    it 'returns a final answer whole' do
      workflow.update!(status: status_value(:finished))
      add_checkpoint(workflow, [{ content: long_message, role: 'assistant', message_type: 'agent' }])

      result = tool.execute

      expect(result.dig(:content, 0, :text)).to eq(long_message)
    end

    it 'returns a plan awaiting approval whole' do
      workflow.update!(status: status_value(:plan_approval_required))
      add_checkpoint(workflow, [{ content: long_message, role: 'assistant', message_type: 'agent' }])

      result = tool.execute

      expect(result.dig(:content, 0, :text)).to start_with(long_message)
    end

    it 'returns the last message of a paused session whole' do
      workflow.update!(status: status_value(:paused))
      add_checkpoint(workflow, [{ content: long_message, role: 'assistant', message_type: 'agent' }])

      result = tool.execute

      expect(result.dig(:content, 0, :text)).to start_with(long_message)
    end

    it 'returns a question awaiting input whole' do
      workflow.update!(status: status_value(:input_required))
      add_checkpoint(workflow, [{ content: long_message, role: 'assistant', message_type: 'agent' }])

      result = tool.execute

      expect(result.dig(:content, 0, :text)).to eq(long_message)
    end
  end

  describe 'when the chat log cannot be read' do
    it 'says so rather than reporting that no answer was produced' do
      workflow.update!(status: status_value(:finished))
      add_checkpoint(workflow, [{ content: 'read_file', message_type: 'tool' }])
      allow(GitlabSchema).to receive(:execute).and_call_original
      allow(GitlabSchema).to receive(:execute)
        .with(described_class::MESSAGE_HISTORY_QUERY, any_args)
        .and_return({ 'errors' => [{ 'message' => 'Query timed out' }] })

      result = tool.execute

      expect(result).to include(
        isError: false,
        content: [{ type: 'text', text: described_class::HISTORY_UNREADABLE }]
      )
    end
  end

  describe 'cost of a poll' do
    it 'does not read the chat history while the session runs' do
      workflow.update!(status: status_value(:running))
      add_checkpoint(workflow, [{ content: 'Working on the request', role: 'assistant', message_type: 'agent' }])

      expect(::Ai::DuoWorkflows::WorkflowCheckpointEventPresenter).not_to receive(:batch_duo_messages)

      tool.execute
    end

    it 'leaves an answer hidden behind a trailing turn unread while the session runs' do
      workflow.update!(status: status_value(:running))
      add_checkpoint(workflow, [
        { content: 'Working on the request', role: 'assistant', message_type: 'agent' },
        { content: 'read_file', message_type: 'tool' }
      ])

      result = tool.execute

      expect(result.dig(:content, 0, :text)).to eq('Status: running. Poll again in 30 seconds.')
    end

    context 'when the answer is further back than the history read reaches' do
      before do
        stub_const("#{described_class}::HISTORY_MESSAGE_LIMIT", 2)
        workflow.update!(status: status_value(:finished))
      end

      it 'finds an answer within the newest messages' do
        add_checkpoint(workflow, [
          { content: 'Run the migration', message_type: 'user' },
          { content: 'Ran the migration.', role: 'assistant', message_type: 'agent' },
          { content: 'read_file', message_type: 'tool' }
        ])

        expect(tool.execute.dig(:content, 0, :text)).to eq('Ran the migration.')
      end

      it 'reports no answer rather than reading the whole history' do
        add_checkpoint(workflow, [
          { content: 'Ran the migration.', role: 'assistant', message_type: 'agent' },
          { content: 'read_file', message_type: 'tool' },
          { content: 'grep', message_type: 'tool' }
        ])

        expect(tool.execute.dig(:content, 0, :text)).to eq('Session finished, but no final answer was produced.')
      end
    end
  end

  describe 'status vocabulary' do
    it 'matches the string list_duo_sessions returns for the same session' do
      workflow.update!(status: status_value(:input_required))

      listed = Mcp::Tools::DuoWorkflows::ListDuoSessionsTool
        .new(current_user: user, params: { project_id: project.full_path }, access_token: nil)
        .execute
        .dig(:structuredContent, 'sessions')
        .find { |session| session['id'] == workflow.id }

      expect(tool.execute.dig(:structuredContent, 'status')).to eq(listed['status'])
      expect(listed['status']).to eq('input_required')
    end
  end

  private

  def session_metadata(status, **extra)
    {
      'workflow_id' => workflow.id,
      'status' => status,
      'web_url' => workflow.web_url,
      'created_merge_requests' => [],
      'created_work_items' => [],
      'created_notes' => []
    }.merge(extra.transform_keys(&:to_s))
  end

  def add_checkpoint(workflow, messages)
    create(:duo_workflows_checkpoint, workflow: workflow, project: project,
      checkpoint: { channel_values: { ui_chat_log: messages } })
  end

  def link_merge_request(merge_request, link_type)
    create(:duo_workflows_workflow_merge_request, workflow: workflow, project: project,
      merge_request: merge_request, link_type: link_type)
  end

  def link_note(note, link_type)
    create(:duo_workflows_workflow_note, workflow: workflow, project: project,
      note: note, link_type: link_type)
  end

  def link_work_item(work_item, link_type)
    create(:duo_workflows_workflow_work_item, workflow: workflow, project: project,
      work_item: work_item, link_type: link_type)
  end

  def link_workload(job)
    workload = create(:ci_workload, pipeline: job.pipeline, project: project)
    workflow.workflows_workloads.create!(workload: workload, project: project)
  end

  def status_value(status)
    ::Ai::DuoWorkflows::Workflow.state_machines[:status].states.fetch(status).value
  end
end
