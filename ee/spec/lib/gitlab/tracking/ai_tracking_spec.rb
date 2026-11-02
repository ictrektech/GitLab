# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Tracking::AiTracking, feature_category: :value_stream_management do
  describe '.track_event', :freeze_time, :click_house, :clean_gitlab_redis_shared_state do
    let_it_be(:group) { create(:group, path: 'group') }
    let_it_be(:organization) { create(:organization) }
    let_it_be(:current_user) { create(:user, organizations: [organization]) }
    let(:event_context) do
      { user: current_user }
    end

    let_it_be(:project) { create(:project, namespace: group, path: 'project') }

    subject(:track_event) { described_class.track_event(event_name, **event_context) }

    before do
      allow(Gitlab::ClickHouse).to receive(:globally_enabled_for_analytics?).and_return(true)
    end

    context 'for unknown event' do
      let(:event_name) { 'something_unrelated' }

      it { is_expected.to be_nil }
    end

    describe 'guessing namespace ID' do
      let(:event_name) { 'request_duo_chat_response' }
      let(:expected_event_hash) do
        { user: current_user, event: event_name, extras: {} }
      end

      context 'with project ID provided' do
        let(:event_context) { super().merge(project_id: project.id, namespace_id: nil) }

        let(:expected_event_hash) do
          super().merge(namespace_id: project.project_namespace_id)
        end

        it 'includes project namespace id' do
          expect(Ai::UsageEvent).to receive(:new).with(expected_event_hash).and_call_original
          track_event
        end
      end

      context 'with project object is provided' do
        let(:event_context) { super().merge(project: project, namespace_id: nil) }

        let(:expected_event_hash) do
          super().merge(namespace_id: project.project_namespace_id)
        end

        it 'includes project namespace id' do
          expect(Ai::UsageEvent).to receive(:new).with(expected_event_hash).and_call_original
          track_event
        end
      end

      context 'with namespace ID provided' do
        let(:event_context) { super().merge(namespace_id: group.id) }

        let(:expected_event_hash) do
          super().merge(namespace_id: group.id)
        end

        it 'includes namespace id' do
          expect(Ai::UsageEvent).to receive(:new).with(expected_event_hash).and_call_original
          track_event
        end
      end

      context 'with namespace object is provided' do
        let(:event_context) { super().merge(namespace: group, namespace_id: nil) }

        let(:expected_event_hash) do
          super().merge(namespace_id: group.id)
        end

        it 'includes namespace id' do
          expect(Ai::UsageEvent).to receive(:new).with(expected_event_hash).and_call_original
          track_event
        end
      end

      context 'with namespace ID and project ID is provided' do
        let(:event_context) { super().merge(namespace_id: group.id, project_id: project.id) }

        let(:expected_event_hash) do
          super().merge(namespace_id: project.project_namespace_id)
        end

        it 'takes project namespace id' do
          expect(Ai::UsageEvent).to receive(:new).with(expected_event_hash).and_call_original
          track_event
        end
      end
    end

    describe 'deprecated events' do
      events = %w[code_suggestions_requested code_suggestion_direct_access_token_refresh]

      events.each do |e|
        it "declares `#{e} as deprecated" do
          expect(described_class.deprecated_event?(e)).to be_truthy
        end
      end
    end

    %w[code_suggestion_shown_in_ide code_suggestion_accepted_in_ide code_suggestion_rejected_in_ide].each do |e|
      context "for `#{e}` event" do
        let(:event_name) { e }
        let(:event_context) { super().merge(extras) }
        let(:extras) do
          {
            unique_tracking_id: "AB1",
            suggestion_size: 10,
            language: 'cobol',
            branch_name: 'main',
            ide_name: 'VSCode',
            ide_vendor: 'Microsoft',
            ide_version: '2',
            extension_name: 'cobol-vscode',
            extension_version: '1',
            language_server_version: '3.11',
            model_name: 'ModelName',
            model_engine: 'ModelEngine'
          }
        end

        let(:expected_pg_attributes) do
          {
            user_id: current_user.id,
            event: event_name,
            extras: extras
          }
        end

        let(:expected_ch_attributes) do
          {
            user_id: current_user.id,
            event: Ai::UsageEvent.events[event_name],
            extras: extras.to_json
          }
        end

        it_behaves_like 'standard ai usage event tracking'
      end
    end

    context 'for `request_duo_chat_response` event' do
      let(:event_name) { 'request_duo_chat_response' }

      let(:expected_pg_attributes) do
        {
          user_id: current_user.id,
          event: event_name,
          extras: {}
        }
      end

      let(:expected_ch_attributes) do
        {
          user_id: current_user.id,
          event: Ai::UsageEvent.events[event_name],
          extras: {}.to_json
        }
      end

      it_behaves_like 'standard ai usage event tracking'
    end

    context 'for Duo Chat tool events' do
      let(:tool_extras) do
        {
          session_id: 42,
          tool_name: 'create_issue',
          flow_type: 'chat',
          trigger_source: 'web_chat',
          model: 'claude-3-5-sonnet'
        }
      end

      %w[tool_succeeded_duo_chat tool_failed_duo_chat].each do |e|
        context "for `#{e}` event" do
          let(:event_name) { e }
          let(:event_context) do
            super().merge(
              project: project,
              session_id: '42',
              tool_name: 'create_issue',
              flow_type: 'chat',
              trigger_source: 'web_chat',
              model: 'claude-3-5-sonnet'
            )
          end

          let(:expected_pg_attributes) do
            {
              user_id: current_user.id,
              event: event_name,
              namespace_id: project.project_namespace_id,
              extras: tool_extras
            }
          end

          let(:expected_ch_attributes) do
            {
              user_id: current_user.id,
              event: Ai::UsageEvent.events[event_name],
              namespace_path: project.project_namespace.reload.traversal_path(with_organization: false),
              extras: tool_extras.to_json
            }
          end

          it_behaves_like 'standard ai usage event tracking'
        end
      end
    end

    context 'for `report_duo_chat_token_usage` event' do
      let(:event_name) { 'report_duo_chat_token_usage' }
      let(:usage) do
        {
          'claude-sonnet-4-5' => { 'input_tokens' => 8, 'output_tokens' => 12 },
          'claude-haiku-4-5' => { 'input_tokens' => 3, 'output_tokens' => 5 }
        }
      end

      let(:event_context) { super().merge(project: project, request_id: 'request-1', usage: usage) }
      let(:usage_extras) { { request_id: 'request-1', usage: usage } }

      let(:expected_pg_attributes) do
        {
          user_id: current_user.id,
          event: event_name,
          namespace_id: project.project_namespace_id,
          extras: usage_extras
        }
      end

      let(:expected_ch_attributes) do
        {
          user_id: current_user.id,
          event: Ai::UsageEvent.events[event_name],
          namespace_path: project.project_namespace.reload.traversal_path(with_organization: false),
          extras: usage_extras.to_json
        }
      end

      it_behaves_like 'standard ai usage event tracking'

      context 'when the request has no request ID' do
        let(:event_context) { super().merge(request_id: nil) }
        let(:usage_extras) { { usage: usage } }

        it_behaves_like 'standard ai usage event tracking'
      end
    end

    context 'for `complete_duo_chat_response` event' do
      let(:event_name) { 'complete_duo_chat_response' }
      let(:event_context) { super().merge(project: project, request_id: 'request-1', error_code: error_code) }
      let(:completion_extras) { { request_id: 'request-1', error_code: error_code }.compact }

      let(:expected_pg_attributes) do
        {
          user_id: current_user.id,
          event: event_name,
          namespace_id: project.project_namespace_id,
          extras: completion_extras
        }
      end

      let(:expected_ch_attributes) do
        {
          user_id: current_user.id,
          event: Ai::UsageEvent.events[event_name],
          namespace_path: project.project_namespace.reload.traversal_path(with_organization: false),
          extras: completion_extras.to_json
        }
      end

      context 'when the response ended in an error' do
        let(:error_code) { 'A1006' }

        it_behaves_like 'standard ai usage event tracking'
      end

      context 'when the response was answered' do
        let(:error_code) { nil }

        it_behaves_like 'standard ai usage event tracking'
      end
    end

    context 'for `troubleshoot_job` event' do
      let(:event_name) { 'troubleshoot_job' }
      let_it_be(:merge_request) { create(:merge_request, source_project: project) }
      let_it_be(:pipeline) { create(:ci_pipeline, project: project, merge_request: merge_request) }
      let(:job) { create(:ci_build, pipeline: pipeline, project: project, user_id: current_user.id) }

      let(:event_context) { super().merge({ job: job }) }

      let(:extras) do
        {
          job_id: job.id,
          project_id: project.id,
          pipeline_id: pipeline.id,
          merge_request_id: merge_request.id
        }
      end

      let(:expected_pg_attributes) do
        {
          user_id: current_user.id,
          event: event_name,
          namespace_id: project.project_namespace_id,
          extras: extras
        }
      end

      let(:expected_ch_attributes) do
        {
          user_id: current_user.id,
          event: Ai::UsageEvent.events[event_name],
          namespace_path: project.project_namespace.reload.traversal_path(with_organization: false),
          extras: extras.to_json
        }
      end

      it_behaves_like 'standard ai usage event tracking'
    end

    %w[
      agent_platform_session_created
      agent_platform_session_started
      agent_platform_session_finished
      agent_platform_session_dropped
      agent_platform_session_stopped
      agent_platform_session_resumed
      agent_platform_session_input_required
      report_agent_platform_token_usage
    ].each do |e|
      context "for `#{e}` event" do
        let(:event_name) { e }
        let(:event_context) do
          super().merge({ project: project, value: 1, label: "software_development", property: "ide" })
        end

        let(:extras) do
          {
            project_id: project.id,
            session_id: 1,
            flow_type: "software_development",
            environment: "ide"
          }
        end

        let(:expected_pg_attributes) do
          {
            user_id: current_user.id,
            event: event_name,
            namespace_id: project.project_namespace_id,
            extras: extras
          }
        end

        let(:expected_ch_attributes) do
          {
            user_id: current_user.id,
            event: Ai::UsageEvent.events[event_name],
            namespace_path: project.project_namespace.reload.traversal_path(with_organization: false),
            extras: extras.to_json
          }
        end

        it_behaves_like 'standard ai usage event tracking'

        context 'when triggered by a verification run' do
          let(:event_context) { super().merge({ verification_run: "true" }) }
          let(:extras) { super().merge(verification_run: "true") }

          it_behaves_like 'standard ai usage event tracking'
        end

        context 'when verification_run is present but not the string "true"' do
          let(:event_context) { super().merge({ verification_run: false }) }

          it_behaves_like 'standard ai usage event tracking'
        end
      end
    end

    context 'for `report_agent_platform_token_usage` event' do
      let(:event_name) { 'report_agent_platform_token_usage' }
      let(:usage) do
        {
          'claude-sonnet-4-5' => { 'input_tokens' => 8, 'output_tokens' => 12 },
          'claude-haiku-4-5' => { 'input_tokens' => 3, 'output_tokens' => 5 }
        }
      end

      let(:event_context) do
        super().merge(project: project, value: 1, label: 'chat', property: 'web', usage: usage)
      end

      let(:usage_extras) do
        { project_id: project.id, session_id: 1, flow_type: 'chat', environment: 'web', usage: usage }
      end

      let(:expected_pg_attributes) do
        {
          user_id: current_user.id,
          event: event_name,
          namespace_id: project.project_namespace_id,
          extras: usage_extras
        }
      end

      let(:expected_ch_attributes) do
        {
          user_id: current_user.id,
          event: Ai::UsageEvent.events[event_name],
          namespace_path: project.project_namespace.reload.traversal_path(with_organization: false),
          extras: usage_extras.to_json
        }
      end

      it_behaves_like 'standard ai usage event tracking'

      context 'when the session has no project' do
        let(:event_context) do
          { user: current_user, namespace: group, value: 1, label: 'chat', property: 'web', usage: usage }
        end

        let(:usage_extras) { { project_id: nil, session_id: 1, flow_type: 'chat', environment: 'web', usage: usage } }

        let(:expected_pg_attributes) do
          { user_id: current_user.id, event: event_name, namespace_id: group.id, extras: usage_extras }
        end

        let(:expected_ch_attributes) do
          {
            user_id: current_user.id,
            event: Ai::UsageEvent.events[event_name],
            namespace_path: group.traversal_path(with_organization: false),
            extras: usage_extras.to_json
          }
        end

        it_behaves_like 'standard ai usage event tracking'
      end
    end

    %w[
      encounter_duo_code_review_error_during_review
      find_no_issues_duo_code_review_after_review
      find_nothing_to_review_duo_code_review_on_mr
      post_comment_duo_code_review_on_diff
      react_thumbs_up_on_duo_code_review_comment
      react_thumbs_down_on_duo_code_review_comment
      request_review_duo_code_review_on_mr_by_author
      request_review_duo_code_review_on_mr_by_non_author
      excluded_files_from_duo_code_review
      publish_duo_code_review_comments
    ].each do |e|
      context "for `#{e}` event" do
        let(:event_name) { e }
        let(:event_context) { super().merge({ project: project }) }

        let(:expected_pg_attributes) do
          {
            user_id: current_user.id,
            event: event_name,
            namespace_id: project.project_namespace_id,
            extras: {}
          }
        end

        let(:expected_ch_attributes) do
          {
            user_id: current_user.id,
            event: Ai::UsageEvent.events[event_name],
            namespace_path: project.project_namespace.reload.traversal_path(with_organization: false),
            extras: {}.to_json
          }
        end

        it_behaves_like 'standard ai usage event tracking'
      end
    end

    %w[create_duo_suggested_reviewers assign_duo_suggested_reviewer].each do |e|
      context "for `#{e}` event" do
        let(:event_name) { e }
        let(:event_context) { super().merge({ project: project, property: '1', value: 2 }) }
        let(:extras) { { merge_request_id: 1, count: 2 } }

        let(:expected_pg_attributes) do
          {
            user_id: current_user.id,
            event: event_name,
            namespace_id: project.project_namespace_id,
            extras: extras
          }
        end

        let(:expected_ch_attributes) do
          {
            user_id: current_user.id,
            event: Ai::UsageEvent.events[event_name],
            namespace_path: project.project_namespace.reload.traversal_path(with_organization: false),
            extras: extras.to_json
          }
        end

        it_behaves_like 'standard ai usage event tracking'
      end
    end

    context 'for `approve_merge_request_duo_code_review` event' do
      let(:event_name) { 'approve_merge_request_duo_code_review' }
      let(:event_context) { super().merge({ project: project, property: '1' }) }

      let(:expected_pg_attributes) do
        {
          user_id: current_user.id,
          event: event_name,
          namespace_id: project.project_namespace_id,
          extras: { merge_request_id: '1' }
        }
      end

      let(:expected_ch_attributes) do
        {
          user_id: current_user.id,
          event: Ai::UsageEvent.events[event_name],
          namespace_path: project.project_namespace.reload.traversal_path(with_organization: false),
          extras: { merge_request_id: '1' }.to_json
        }
      end

      it_behaves_like 'standard ai usage event tracking'
    end

    context 'for `restore_ai_catalog_item` event' do
      let(:event_name) { 'restore_ai_catalog_item' }

      let(:expected_pg_attributes) do
        {
          user_id: current_user.id,
          event: event_name,
          extras: {}
        }
      end

      let(:expected_ch_attributes) do
        {
          user_id: current_user.id,
          event: Ai::UsageEvent.events[event_name],
          extras: {}.to_json
        }
      end

      it_behaves_like 'standard ai usage event tracking'
    end

    context 'for `summarize_review` event' do
      let(:event_name) { 'summarize_review' }
      let(:event_context) { super().merge(project: project) }

      let(:expected_pg_attributes) do
        {
          user_id: current_user.id,
          event: event_name,
          namespace_id: project.project_namespace_id,
          extras: {}
        }
      end

      let(:expected_ch_attributes) do
        {
          user_id: current_user.id,
          event: Ai::UsageEvent.events[event_name],
          namespace_path: project.project_namespace.reload.traversal_path(with_organization: false),
          extras: {}.to_json
        }
      end

      it_behaves_like 'standard ai usage event tracking'
    end

    context 'for `summarize_new_merge_request` event' do
      let(:event_name) { 'summarize_new_merge_request' }
      let(:event_context) { super().merge(project: project) }

      let(:expected_pg_attributes) do
        {
          user_id: current_user.id,
          event: event_name,
          namespace_id: project.project_namespace_id,
          extras: {}
        }
      end

      let(:expected_ch_attributes) do
        {
          user_id: current_user.id,
          event: Ai::UsageEvent.events[event_name],
          namespace_path: project.project_namespace.reload.traversal_path(with_organization: false),
          extras: {}.to_json
        }
      end

      it_behaves_like 'standard ai usage event tracking'
    end

    context 'for `ai_duo_messaging_feedback_submitted` event' do
      let(:event_name) { 'ai_duo_messaging_feedback_submitted' }
      let(:event_context) do
        super().merge(
          namespace: group,
          label: 'thumbs_down',
          value: 42,
          property: 'slack',
          reason: 'incorrect',
          comment: 'wrong project'
        )
      end

      let(:expected_pg_attributes) do
        {
          user_id: current_user.id,
          event: event_name,
          namespace_id: group.id,
          extras: {
            feedback: 'thumbs_down',
            workflow_id: 42,
            surface: 'slack'
          }
        }
      end

      let(:expected_ch_attributes) do
        {
          user_id: current_user.id,
          event: Ai::UsageEvent.events[event_name],
          namespace_path: group.reload.traversal_path(with_organization: false),
          extras: {
            feedback: 'thumbs_down',
            workflow_id: 42,
            surface: 'slack'
          }.to_json
        }
      end

      it_behaves_like 'standard ai usage event tracking'
    end

    context 'for `trigger_slack_duo` event' do
      let(:event_name) { 'trigger_slack_duo' }
      let(:event_context) { super().merge(project: project) }

      let(:expected_pg_attributes) do
        {
          user_id: current_user.id,
          event: event_name,
          namespace_id: project.project_namespace_id,
          extras: { project_id: project.id }
        }
      end

      let(:expected_ch_attributes) do
        {
          user_id: current_user.id,
          event: Ai::UsageEvent.events[event_name],
          namespace_path: project.project_namespace.reload.traversal_path(with_organization: false),
          extras: { project_id: project.id }.to_json
        }
      end

      it_behaves_like 'standard ai usage event tracking'
    end

    context 'for `generate_merge_commit_message` event' do
      let(:event_name) { 'generate_merge_commit_message' }
      let(:event_context) { super().merge(project: project) }

      let(:expected_pg_attributes) do
        {
          user_id: current_user.id,
          event: event_name,
          namespace_id: project.project_namespace_id,
          extras: {}
        }
      end

      let(:expected_ch_attributes) do
        {
          user_id: current_user.id,
          event: Ai::UsageEvent.events[event_name],
          namespace_path: project.project_namespace.reload.traversal_path(with_organization: false),
          extras: {}.to_json
        }
      end

      it_behaves_like 'standard ai usage event tracking'
    end

    %w[
      request_duo_vulnerability_resolution
      explain_vulnerability
      fix_code
      refactor_code
      write_tests
      explain_code
    ].each do |duo_feature_event|
      context "for `#{duo_feature_event}` event" do
        let(:event_name) { duo_feature_event }
        let(:event_context) { super().merge(project: project) }

        let(:expected_pg_attributes) do
          {
            user_id: current_user.id,
            event: event_name,
            namespace_id: project.project_namespace_id,
            extras: {}
          }
        end

        let(:expected_ch_attributes) do
          {
            user_id: current_user.id,
            event: Ai::UsageEvent.events[event_name],
            namespace_path: project.project_namespace.reload.traversal_path(with_organization: false),
            extras: {}.to_json
          }
        end

        it_behaves_like 'standard ai usage event tracking'
      end
    end

    context 'for `resolve_feature_discovery_search` event' do
      let(:event_name) { 'resolve_feature_discovery_search' }
      let(:event_context) do
        super().merge(
          namespace: group,
          label: 'exact_map',
          value: 250
        )
      end

      let(:expected_extras) do
        {
          resolution_tier: 'exact_map',
          latency_ms: 250
        }
      end

      let(:expected_pg_attributes) do
        {
          user_id: current_user.id,
          event: event_name,
          namespace_id: group.id,
          extras: expected_extras
        }
      end

      let(:expected_ch_attributes) do
        {
          user_id: current_user.id,
          event: Ai::UsageEvent.events[event_name],
          namespace_path: group.reload.traversal_path(with_organization: false),
          extras: expected_extras.to_json
        }
      end

      it_behaves_like 'standard ai usage event tracking'
    end

    context 'for MCP events' do
      let(:mcp_extras) do
        {
          request_id: 123,
          tool_name: "test_tool",
          has_tool_call_success: true,
          failure_reason: nil,
          error_status: nil,
          dispatched_tool_name: "gitlab_search_in_project"
        }
      end

      %w[
        start_mcp_tool_call
        finish_mcp_tool_call
      ].each do |e|
        context "for `#{e}` event" do
          let(:event_name) { e }
          let(:event_context) do
            super().merge({
              project: project,
              request_id: 123,
              tool_name: "test_tool",
              has_tool_call_success: true,
              failure_reason: nil,
              error_status: nil,
              dispatched_tool_name: "gitlab_search_in_project"
            })
          end

          let(:expected_pg_attributes) do
            {
              user_id: current_user.id,
              event: event_name,
              namespace_id: project.project_namespace_id,
              extras: mcp_extras
            }
          end

          let(:expected_ch_attributes) do
            {
              user_id: current_user.id,
              event: Ai::UsageEvent.events[event_name],
              namespace_path: project.project_namespace.reload.traversal_path(with_organization: false),
              extras: mcp_extras.to_json
            }
          end

          it_behaves_like 'standard ai usage event tracking'
        end
      end
    end
  end

  describe 'client attribution', :clean_gitlab_redis_shared_state do
    let_it_be(:current_user) { create(:user) }

    subject(:track_event) { described_class.track_event('request_duo_chat_response', user: current_user) }

    it 'stores no client keys without a request context' do
      expect(Ai::UsageEvent).to receive(:new).with(hash_including(extras: {})).and_call_original

      track_event
    end

    it 'stores the client identity of the current request' do
      context = { client_type: 'mobile', client_name: 'gitlab-mobile-ios', client_version: '1.2.0' }

      expect(Ai::UsageEvent).to receive(:new).with(hash_including(extras: context)).and_call_original

      Gitlab::ApplicationContext.with_context(context) { track_event }
    end

    it 'omits the client name when the identity has none' do
      expect(Ai::UsageEvent).to receive(:new).with(hash_including(extras: { client_type: 'api' })).and_call_original

      Gitlab::ApplicationContext.with_context(client_type: 'api') { track_event }
    end
  end

  describe '.track_user_activity' do
    let(:current_user) { create(:user) }

    it 'refreshes user metrics for last activity' do
      expect(Ai::UserMetrics).to receive(:refresh_last_activity_on).with(current_user).and_call_original

      described_class.track_user_activity(current_user)
    end
  end

  describe 'code_suggestions feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:code_suggestions).keys).to match_array(%w[
        code_suggestions_requested
        code_suggestion_shown_in_ide
        code_suggestion_accepted_in_ide
        code_suggestion_rejected_in_ide
        code_suggestion_direct_access_token_refresh
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'agent_platform feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:agent_platform).keys).to match_array(%w[
        agent_platform_session_created
        agent_platform_session_started
        agent_platform_session_finished
        agent_platform_session_dropped
        agent_platform_session_stopped
        agent_platform_session_resumed
        agent_platform_session_input_required
        view_duo_agentic_subscription_expired_empty_state
        click_duo_agentic_subscription_expired_upgrade
        click_duo_agentic_subscription_expired_learn_more
        report_agent_platform_token_usage
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'events that are not user actions' do
    it 'marks only the Agent Platform token usage event' do
      marked = described_class.registered_events.keys.select { |name| described_class.non_user_action_event?(name) }

      expect(marked).to contain_exactly('report_agent_platform_token_usage')
    end
  end

  describe 'ai_catalog feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:ai_catalog).keys).to match_array(%w[
        restore_ai_catalog_item
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'code_review feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:code_review).keys).to match_array(%w[
        encounter_duo_code_review_error_during_review
        find_no_issues_duo_code_review_after_review
        find_nothing_to_review_duo_code_review_on_mr
        post_comment_duo_code_review_on_diff
        react_thumbs_up_on_duo_code_review_comment
        react_thumbs_down_on_duo_code_review_comment
        request_review_duo_code_review_on_mr_by_author
        request_review_duo_code_review_on_mr_by_non_author
        excluded_files_from_duo_code_review
        publish_duo_code_review_comments
        create_duo_suggested_reviewers
        assign_duo_suggested_reviewer
        approve_merge_request_duo_code_review
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'chat feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:chat).keys).to match_array(%w[
        request_duo_chat_response
        tool_succeeded_duo_chat
        tool_failed_duo_chat
        report_duo_chat_token_usage
        complete_duo_chat_response
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'troubleshoot_job feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:troubleshoot_job).keys).to match_array(%w[
        troubleshoot_job
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'mcp feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:mcp).keys).to match_array(%w[
        start_mcp_tool_call
        finish_mcp_tool_call
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'fix_pipeline feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:fix_pipeline).keys).to match_array(%w[
        fix_pipeline_suggestion_posted
        fix_pipeline_suggestion_applied
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'duo_workflow feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:duo_workflow).keys).to match_array(%w[
        duo_workflow_workload_completed
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'summarize_review feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:summarize_review).keys).to match_array(%w[
        summarize_review
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'summarize_new_merge_request feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:summarize_new_merge_request).keys).to match_array(%w[
        summarize_new_merge_request
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'generate_merge_commit_message feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:generate_merge_commit_message).keys).to match_array(%w[
        generate_merge_commit_message
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'request_duo_vulnerability_resolution feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:request_duo_vulnerability_resolution).keys).to match_array(%w[
        request_duo_vulnerability_resolution
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'explain_vulnerability feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:explain_vulnerability).keys).to match_array(%w[
        explain_vulnerability
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'feature_discovery feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:feature_discovery).keys).to match_array(%w[
        resolve_feature_discovery_search
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'fix_code feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:fix_code).keys).to match_array(%w[
        fix_code
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'refactor_code feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:refactor_code).keys).to match_array(%w[
        refactor_code
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'write_tests feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:write_tests).keys).to match_array(%w[
        write_tests
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end

  describe 'explain_code feature events' do
    it 'contains exact events' do
      expect(described_class.registered_events(:explain_code).keys).to match_array(%w[
        explain_code
      ]), "When adding events, consider how they should be added to corresponding materialized views."
    end
  end
end
