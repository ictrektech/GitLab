# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying Duo Workflow Events', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:group) { create(:group) }
  let_it_be_with_reload(:project) { create(:project, group: group) }
  let_it_be(:another_project) { create(:project, group: group) }
  let_it_be_with_reload(:user) { create(:user, developer_of: [project, another_project]) }
  let_it_be(:another_user) { create(:user, developer_of: project) }
  # `freeze: false` is required here: this `let_it_be` subject is mutated
  # in-memory across examples in a way that survives both
  # `let_it_be_with_reload` and `let_it_be_with_refind` (e.g. a memoized
  # association/collection or a non-persisted attribute). Keeping it unfrozen
  # is the only correct cure (see gitlab-org/gitlab#602925).
  let_it_be(:checkpoints, freeze: false) { create_list(:duo_workflows_checkpoint, 3, :ui_chat_log, project: project) }

  let_it_be_with_reload(:ide_workflow) do
    create(:duo_workflows_workflow, project: project, user: user, checkpoints: checkpoints, environment: :ide)
  end

  let_it_be(:remote_workflow) do
    create(:duo_workflows_workflow, project: project, user: user,
      checkpoints: create_list(:duo_workflows_checkpoint, 2, project: project), environment: :web,
      workflow_definition: :convert_to_gitlab_ci)
  end

  let_it_be(:remote_workflow_for_another_project) do
    create(:duo_workflows_workflow, project: another_project, user: user,
      checkpoints: create_list(:duo_workflows_checkpoint, 2, project: another_project), environment: :web,
      workflow_definition: :convert_to_gitlab_ci)
  end

  let(:fields) do
    <<~GRAPHQL
      edges {
        cursor
        node {
          errors,
          checkpoint,
          compressedCheckpoint,
          metadata,
          workflowGoal,
          workflowDefinition,
          threadTs,
          parentTs,
          duoMessages {
            content
            messageType
            status
            toolInfo
            timestamp
            correlationId
            role
          }
        }
      }
      pageInfo {
        hasPreviousPage
        startCursor
        hasNextPage
        endCursor
      }
    GRAPHQL
  end

  let(:arguments) { { workflowId: global_id_of(ide_workflow) } }
  let(:query) { graphql_query_for('duoWorkflowEvents', arguments, fields) }

  subject(:event_nodes) { graphql_data.dig('duoWorkflowEvents', 'edges') }

  context 'when user is not logged in' do
    it 'returns an empty array' do
      post_graphql(query, current_user: nil)

      expect(event_nodes).to be_empty
    end
  end

  context 'when user is logged in' do
    let_it_be(:chat_log) do
      [{ "content" => "hi", "correlationId" => nil, "messageType" => "user", "role" => nil, "status" => "success",
         "timestamp" => "2025-11-25T21:10:57.734182+00:00", "toolInfo" => "null" }]
    end

    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
      # rubocop:disable RSpec/AnyInstanceOf  -- not the next instance
      allow_any_instance_of(User).to receive_messages(allowed_to_use?: true, allowed_to_use_for_resource?: true)
      # rubocop:enable RSpec/AnyInstanceOf
    end

    context 'with a granular token' do
      let(:fields) { 'nodes { threadTs }' }
      let(:boundary_object) { :user }
      let(:request) { post_graphql(query, current_user: user, token: { personal_access_token: pat }) }

      it_behaves_like 'authorizing granular token permissions for GraphQL', :read_duo_workflow

      it_behaves_like 'authorizing granular token permissions for GraphQL with a skipped child type',
        :read_duo_workflow do
        let(:skipped_data_path) { [:duo_workflow_events, :nodes, 0, :thread_ts] }
      end
    end

    context 'with default pagination (no cursor arguments)' do
      it 'returns only the latest checkpoint', :aggregate_failures do
        post_graphql(query, current_user: user)

        expect(event_nodes).not_to be_empty
        expect(event_nodes.length).to eq(1)

        event = event_nodes.first['node']
        expect(event['errors']).to eq([])

        # The resolver orders by created_at DESC so the returned checkpoint
        # must be the most recently created one.
        # Reload to compare against jsonb-normalized values: Postgres
        # jsonb reorders keys (by length, then alpha), so an in-memory
        # factory Hash and the API's serialized response only line up
        # after a DB round-trip.
        latest = checkpoints.max_by { |c| [c.created_at, c.id] }.reload
        expect(Gitlab::Json.safe_parse(event['checkpoint'])).to eq(latest.checkpoint)
        expect(event['compressedCheckpoint']).to eq(
          Base64.strict_encode64(Zlib::Deflate.deflate(latest.checkpoint.to_json, 6))
        )
        expect(Gitlab::Json.safe_parse(event['metadata'])).to eq(latest.metadata)
        expect(event['threadTs']).to eq(latest.thread_ts)
        expect(event['parentTs']).to eq(latest.parent_ts)
        expect(event['workflowGoal']).to eq("Fix pipeline")
        expect(event['workflowDefinition']).to eq("software_development")
        expect(event['duoMessages']).to eq(chat_log)
      end

      it 'reports hasNextPage true when older checkpoints exist' do
        post_graphql(query, current_user: user)

        page_info = graphql_data.dig('duoWorkflowEvents', 'pageInfo')
        expect(page_info['hasNextPage']).to be(true)
      end
    end

    context 'when an event has no checkpoint' do
      let(:fields) { 'edges { node { checkpoint compressedCheckpoint } }' }

      it 'returns null for both checkpoint fields', :aggregate_failures do
        # Both checkpoint columns are NOT NULL, so only a stub reaches the nil guard.
        allow_next_instance_of(::Ai::DuoWorkflows::WorkflowCheckpointEventPresenter) do |presenter|
          allow(presenter).to receive(:checkpoint).and_return(nil)
        end

        post_graphql(query, current_user: user)

        expect(graphql_errors).to be_nil
        expect(event_nodes.first.dig('node', 'checkpoint')).to be_nil
        expect(event_nodes.first.dig('node', 'compressedCheckpoint')).to be_nil
      end
    end

    context 'with offset pagination' do
      it 'returns N checkpoints when first: N is supplied', :aggregate_failures do
        paginated_query = graphql_query_for(
          'duoWorkflowEvents',
          arguments.merge(first: 2),
          fields
        )
        post_graphql(paginated_query, current_user: user)

        nodes = graphql_data.dig('duoWorkflowEvents', 'edges')
        expect(nodes.length).to eq(2)

        # Results must be ordered newest-first
        returned_ts = nodes.map { |e| e['node']['threadTs'] }
        expected_ts = checkpoints.sort_by { |c| [c.created_at, c.id] }.last(2).reverse.map(&:thread_ts)
        expect(returned_ts).to eq(expected_ts)
      end

      it 'pages to older checkpoints using after cursor', :aggregate_failures do
        # First page: newest checkpoint
        post_graphql(query, current_user: user)

        after_cursor = graphql_data.dig('duoWorkflowEvents', 'pageInfo', 'endCursor')
        expect(after_cursor).to be_present

        # Second page: the two older checkpoints
        paginated_query = graphql_query_for(
          'duoWorkflowEvents',
          arguments.merge(first: 2, after: after_cursor),
          fields
        )
        post_graphql(paginated_query, current_user: user)

        older_nodes = graphql_data.dig('duoWorkflowEvents', 'edges')
        expect(older_nodes.length).to eq(2)

        returned_thread_ts = older_nodes.map { |e| e['node']['threadTs'] }
        latest_thread_ts = checkpoints.max_by { |c| [c.created_at, c.id] }.thread_ts
        expect(returned_thread_ts).not_to include(latest_thread_ts)
      end

      it 'reports hasNextPage false when all checkpoints fit in one page', :aggregate_failures do
        all_query = graphql_query_for(
          'duoWorkflowEvents',
          arguments.merge(first: 10),
          fields
        )
        post_graphql(all_query, current_user: user)

        page_info = graphql_data.dig('duoWorkflowEvents', 'pageInfo')
        expect(page_info['hasNextPage']).to be(false)
        expect(graphql_data.dig('duoWorkflowEvents', 'edges').length).to eq(3)
      end
    end

    context 'when the session reconstructs checkpoints from blobs' do
      let_it_be(:headers) do
        %w[hts-1 hts-2 hts-3].map do |thread_ts|
          create(:duo_workflows_checkpoint_header, workflow: ide_workflow, thread_ts: thread_ts)
        end
      end

      before do
        ide_workflow.update!(incremental_checkpoints_enabled: true)
        stub_feature_flags(duo_workflow_read_incremental_checkpoints: project)
      end

      it 'serves the checkpoint headers, newest first' do
        post_graphql(graphql_query_for('duoWorkflowEvents', arguments.merge(first: 10), fields), current_user: user)

        expect(event_nodes.map { |edge| edge.dig('node', 'threadTs') }).to eq(%w[hts-3 hts-2 hts-1])
      end

      # The polling path: no cursor arguments, so the connection applies
      # DEFAULT_EVENTS_PAGE_SIZE and returns the newest header only.
      it 'returns only the latest header with default pagination', :aggregate_failures do
        post_graphql(query, current_user: user)

        expect(event_nodes.length).to eq(1)
        expect(event_nodes.first.dig('node', 'threadTs')).to eq('hts-3')
      end
    end

    context 'when first exceeds the page size cap' do
      let_it_be(:max_page_size) { Resolvers::Ai::DuoWorkflows::WorkflowEventsResolver::MAX_EVENTS_PAGE_SIZE }
      let_it_be(:long_workflow) do
        create(:duo_workflows_workflow, project: project, user: user, environment: :ide,
          checkpoints: create_list(:duo_workflows_checkpoint, max_page_size + 1, project: project))
      end

      let(:fields) { 'nodes { threadTs } pageInfo { hasNextPage endCursor }' }

      def events_page(**pagination)
        arguments = { workflowId: global_id_of(long_workflow), **pagination }
        post_graphql(graphql_query_for('duoWorkflowEvents', arguments, fields), current_user: user)

        graphql_data['duoWorkflowEvents']
      end

      it 'clamps the page and leaves the rest reachable by cursor', :aggregate_failures do
        first_page = events_page(first: 10)

        expect(first_page['nodes'].length).to eq(max_page_size)
        expect(first_page.dig('pageInfo', 'hasNextPage')).to be(true)

        second_page = events_page(first: 10, after: first_page.dig('pageInfo', 'endCursor'))

        expect(second_page['nodes'].length).to eq(1)
      end

      context 'when limit_duo_workflow_events_page_cost is disabled' do
        before do
          stub_feature_flags(limit_duo_workflow_events_page_cost: false)
        end

        it 'returns every requested checkpoint' do
          expect(events_page(first: 10)['nodes'].length).to eq(max_page_size + 1)
        end
      end
    end

    context 'when a page of checkpoints is rebuilt from blobs' do
      let_it_be(:blob_workflow) do
        create(:duo_workflows_workflow, project: project, user: user, environment: :ide,
          incremental_checkpoints_enabled: true)
      end

      let(:fields) { 'nodes { threadTs checkpoint compressedCheckpoint }' }

      before_all do
        %w[first second third].each.with_index(1) do |content, step|
          create(:duo_workflows_checkpoint_header, workflow: blob_workflow, thread_ts: "hts-#{step}",
            parent_ts: (step > 1 ? "hts-#{step - 1}" : nil), channel_keys: %w[ui_chat_log])
          create(:duo_workflows_checkpoint_blob, workflow: blob_workflow, thread_ts: "hts-#{step}",
            current_thread: 0, channel: 'ui_chat_log', version: step.to_s, step_action: 'conversation',
            data: Zlib::Deflate.deflate(Gitlab::Json.dump([{ 'content' => content, 'message_type' => 'agent' }])))
        end
      end

      before do
        stub_feature_flags(duo_workflow_read_incremental_checkpoints: project)
      end

      def post_events_page(first)
        arguments = { workflowId: global_id_of(blob_workflow), first: first }
        post_graphql(graphql_query_for('duoWorkflowEvents', arguments, fields), current_user: user)
      end

      def chat_log_contents(checkpoint)
        Gitlab::Json.safe_parse(checkpoint).dig('channel_values', 'ui_chat_log').pluck('content')
      end

      shared_examples 'rebuilding each checkpoint from its own chain' do
        it 'serves each row its own checkpoint in both fields', :aggregate_failures do
          post_events_page(3)

          nodes = graphql_data.dig('duoWorkflowEvents', 'nodes')
          expect(nodes.map { |node| [node['threadTs'], chat_log_contents(node['checkpoint'])] }).to eq([
            ['hts-3', %w[first second third]], ['hts-2', %w[first second]], ['hts-1', %w[first]]
          ])

          nodes.each do |node|
            compressed = Zlib::Inflate.inflate(Base64.strict_decode64(node['compressedCheckpoint']))
            expect(Gitlab::Json.safe_parse(compressed)).to eq(Gitlab::Json.safe_parse(node['checkpoint']))
          end
        end
      end

      it_behaves_like 'rebuilding each checkpoint from its own chain'

      it 'does not add queries per row' do
        post_events_page(1) # Warm up, so one-off setup queries don't pad the control.
        control = ActiveRecord::QueryRecorder.new(skip_cached: false) { post_events_page(1) }

        expect { post_events_page(3) }.not_to exceed_all_query_limit(control)
      end

      context 'when limit_duo_workflow_events_page_cost is disabled' do
        before do
          stub_feature_flags(limit_duo_workflow_events_page_cost: false)
        end

        it_behaves_like 'rebuilding each checkpoint from its own chain'
      end
    end
  end

  context 'when project_path is specified' do
    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(another_project, :duo_workflow).and_return(true)
      # rubocop:disable RSpec/AnyInstanceOf  -- not the next instance
      allow_any_instance_of(User).to receive_messages(allowed_to_use?: true, allowed_to_use_for_resource?: true)
      # rubocop:enable RSpec/AnyInstanceOf
    end

    let_it_be(:project_fields) { project_fields_for_workflow(remote_workflow) }
    let_it_be(:project_query) { graphql_query_for('project', { full_path: project.full_path }, project_fields) }

    it 'returns only the latest checkpoint for a users remote flow' do
      post_graphql(project_query, current_user: user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(graphql_errors).to be_nil

      events = graphql_data.dig("project", "duoWorkflowEvents", "nodes")
      expect(events.length).to eq(1)
    end

    it 'returns only the latest checkpoint for another users remote flow' do
      post_graphql(project_query, current_user: another_user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(graphql_errors).to be_nil

      events = graphql_data.dig("project", "duoWorkflowEvents", "nodes")
      expect(events.length).to eq(1)
    end

    it "does not return another users ide flow events for the project" do
      project_fields_ide = project_fields_for_workflow(ide_workflow)
      ide_workflow_project_query = graphql_query_for('project', { full_path: project.full_path }, project_fields_ide)
      post_graphql(ide_workflow_project_query, current_user: another_user)

      events = graphql_data.dig("project", "duoWorkflowEvents", "nodes")
      expect(events).to be_empty
    end

    it 'returns empty array if workflow is not in project' do
      project_fields = project_fields_for_workflow(remote_workflow)
      another_project_query = graphql_query_for('project', { full_path: another_project.full_path }, project_fields)
      post_graphql(another_project_query, current_user: user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(graphql_errors).to be_nil

      events = graphql_data.dig("project", "duoWorkflowEvents", "nodes")
      expect(events).to be_empty
    end
  end

  context 'when project_path is specified and user is not a member of the project' do
    before do
      allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(another_project, :duo_workflow).and_return(true)
      # rubocop:disable RSpec/AnyInstanceOf  -- not the next instance
      allow_any_instance_of(User).to receive_messages(allowed_to_use?: true, allowed_to_use_for_resource?: true)
      # rubocop:enable RSpec/AnyInstanceOf
    end

    let_it_be(:project_fields) { project_fields_for_workflow(remote_workflow_for_another_project) }
    let_it_be(:project_query) { graphql_query_for('project', { full_path: another_project.full_path }, project_fields) }

    it 'returns an empty array for a remote flow' do
      post_graphql(project_query, current_user: another_user)

      expect(response).to have_gitlab_http_status(:ok)
      expect(graphql_errors).to be_nil

      events = graphql_data.dig("project", "duoWorkflowEvents", "nodes")
      expect(events).to be_nil
    end
  end

  def project_fields_for_workflow(workflow)
    <<~GRAPHQL
      duoWorkflowEvents(workflowId: "#{workflow.to_global_id}") {
        nodes {
          checkpoint
        }
      }
    GRAPHQL
  end
end
