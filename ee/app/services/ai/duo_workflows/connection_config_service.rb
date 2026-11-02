# frozen_string_literal: true

module Ai
  module DuoWorkflows
    # Everything Workhorse needs to open the DWS gRPC stream on the caller's behalf.
    # Shared by the WebSocket handshake, where the client drives the flow, and by
    # :execute, where Workhorse itself does; the two differ only in how the workflow
    # is resolved, so it is passed in.
    #
    # Keys are PascalCase because Workhorse unmarshals this payload into Go structs.
    # See workhorse/internal/ai_assist/duoworkflow.
    class ConnectionConfigService
      include ::Gitlab::Utils::StrongMemoize

      # How many of the actions Workhorse runs itself (HTTP requests, MCP tool calls,
      # self-hosted tracking) may run at once in one workflow. 1 runs them one at a time.
      MAX_CONCURRENT_ACTIONS = 8

      # The raw request attributes the payload depends on. Held raw rather than
      # resolved because the outgoing headers echo caller-supplied ids verbatim.
      RequestMetadata = Data.define(
        :project_id,
        :namespace_id,
        :client_type,
        :organization_id,
        :feature_setting_name,
        :user_selected_model_identifier,
        :workflow_definition,
        :environment,
        :ai_catalog_item_version_id,
        # Already downcased for gRPC metadata, and pruned of blank values.
        :forwarded_grpc_metadata,
        # True only when the caller is the workflow's own CI job.
        :trusted_job_caller
      )

      def initialize(
        current_user, gitlab_token,
        root_namespace:, namespace:, request_metadata:, server_capabilities:,
        workflow: nil, project: nil)
        @current_user = current_user
        @gitlab_token = gitlab_token
        @root_namespace = root_namespace
        @namespace = namespace
        @request_metadata = request_metadata
        @server_capabilities = server_capabilities
        @workflow = workflow
        @project = project
      end

      attr_writer :model_metadata_service

      def execute
        {
          Service: {
            Headers: grpc_headers,
            URI: ::Gitlab::DuoWorkflow::Client.url_for(feature_setting: feature_setting, user: current_user),
            Secure: ::Gitlab::DuoWorkflow::Client.secure?(feature_setting: feature_setting)
          },
          CloudServiceForSelfHosted: cloud_service_for_self_hosted,
          # Workhorse authenticates the agent's HTTP actions to the GitLab API with this.
          GitlabToken: gitlab_token,
          McpServers: mcp_config_service.execute(denied: tool_access_policies[:deny]),
          LockConcurrentFlow: true,
          TimeoutHTTPRequests: Feature.enabled?(:timeout_dap_http_requests_in_workhorse, current_user),
          MaxConcurrentActions: max_concurrent_actions,
          RejectInvalidClientEvents: Feature.enabled?(:duo_workflow_reject_invalid_client_events, current_user),
          ServerCapabilities: server_capabilities
        }
      end

      private

      attr_reader :current_user, :gitlab_token, :root_namespace, :namespace, :request_metadata,
        :server_capabilities, :workflow, :project

      def max_concurrent_actions
        return 1 unless Feature.enabled?(:duo_workflow_concurrent_actions_in_workhorse, current_user)

        MAX_CONCURRENT_ACTIONS
      end

      def grpc_headers
        headers = cloud_connector_headers.merge(
          'x-gitlab-unidirectional-streaming' => 'enabled',
          # gRPC metadata for the Duo Workflow Service. `API::Mcp::Base` reads an inbound HTTP
          # header of the same name on a different channel; nothing forwards this one to it.
          'x-gitlab-enabled-mcp-server-tools' =>
            mcp_config_service.gitlab_enabled_tools(denied: tool_access_policies[:deny]).join(','),
          'x-gitlab-model-prompt-cache-enabled' => model_prompt_cache_enabled.to_s,
          'x-gitlab-self-hosted-dap-billing-enabled' => self_hosted_dap_billing_enabled?.to_s,
          'x-gitlab-extended-logging' =>
            ::Gitlab::DuoWorkflow::Client.enable_extended_logging?(current_user, namespace: namespace).to_s
        ).merge(model_metadata_headers)

        # DWS makes every GitLab call through actions that Workhorse executes, so it
        # has no use for the user's token. Kept behind the flag only for DWS versions
        # that still called GitLab directly.
        unless Feature.enabled?(:duo_workflow_omit_gitlab_token_from_dws_metadata, current_user)
          headers['x-gitlab-oauth-token'] = gitlab_token
        end

        # Forwarded last so a caller-sent header wins, matching the previous behaviour
        # for x-gitlab-client-type.
        headers.merge(request_metadata.forwarded_grpc_metadata)
      end

      def cloud_connector_headers
        headers = ::Gitlab::DuoWorkflow::Client.cloud_connector_headers(
          user: current_user,
          project_id: request_metadata.project_id,
          namespace_id: request_metadata.namespace_id.presence&.to_i,
          governing_namespace_id: root_namespace.id,
          feature_setting: feature_setting,
          tool_access_policies: tool_access_policies,
          workflow_id: workflow&.id,
          flow_config_id: trusted_flow_config_id,
          subject: workflow&.service_account || current_user
        )

        # client type from the browser is sent as a param rather than a header
        headers['x-gitlab-client-type'] ||= request_metadata.client_type.presence

        # Workhorse forwards these on the HTTP actions it runs for the agent, so
        # events those calls fire attribute to the client that opened the session.
        client = ::Gitlab::Tracking::ClientIdentity.current
        headers['x-gitlab-client-type'] ||= client&.type
        headers['x-gitlab-client-name'] ||= client&.name

        ::Gitlab::AiGateway.add_organization_header!(headers, request_metadata.organization_id)

        headers
      end
      strong_memoize_attr :cloud_connector_headers

      # Resolved like Runtimes::Ci does. Only sent to the workflow's own CI job (the
      # composite identity of the flow's service account) and only while the flow is
      # available. Any other client, including the owner's, gets none, so DWS does not
      # grant the models reserved for trusted flows.
      def trusted_flow_config_id
        return unless request_metadata.trusted_job_caller

        flow = workflow&.foundational_flow
        return unless flow&.gitlab_hosted_runner_only
        return if flow.blocked_for?(workflow.resource_parent.root_ancestor)

        workflow.foundational_flow_params[:flow_config_id]
      end

      def cloud_service_for_self_hosted
        return unless self_hosted_dap_billing_enabled?

        {
          Headers: cloud_connector_headers.merge(
            'authorization' => "Bearer #{::CloudConnector::Tokens.cloud_connector_token}"
          ),
          URI: ::Gitlab::DuoWorkflow::Client.cloud_connected_url(user: current_user),
          Secure: true
        }
      end

      def self_hosted_dap_billing_enabled?
        return false if workflow&.triggered_by_verification?

        ::Ai::SelfHostedDapBilling.should_bill?(feature_setting)
      end
      strong_memoize_attr :self_hosted_dap_billing_enabled?

      def feature_setting
        ::Ai::FeatureSettingSelectionService.new(
          current_user,
          request_metadata.feature_setting_name,
          root_namespace
        ).execute.payload
      end
      strong_memoize_attr :feature_setting

      def model_metadata_headers
        if reuse_workflow_model_metadata?
          return {
            ::Gitlab::Llm::AiGateway::AgentPlatform::ModelMetadata::HEADER_KEY => workflow.model_metadata_json
          }
        end

        model_metadata_service.execute
      end
      strong_memoize_attr :model_metadata_headers

      def model_metadata_service
        @model_metadata_service ||= ::Ai::DuoWorkflows::DuoAgentPlatformModelMetadataService.new(
          root_namespace: root_namespace,
          current_user: current_user,
          user_selected_model_identifier: request_metadata.user_selected_model_identifier,
          feature_name: request_metadata.feature_setting_name
        )
      end

      def reuse_workflow_model_metadata?
        return false if request_metadata.user_selected_model_identifier.present?
        return false if workflow&.model_metadata_json.blank?

        previous_model_included_in_defaults?
      end

      def previous_model_included_in_defaults?
        default_model_refs.include?(workflow_model_ref)
      end

      def workflow_model_ref
        parsed = ::Gitlab::Json.safe_parse(workflow.model_metadata_json)

        parsed['name'] if parsed.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end

      def default_model_refs
        parser = ::Ai::ModelSelection::ModelDefinitions.fetch(current_user).parser

        parser ? parser.default_model_refs_for_feature(request_metadata.feature_setting_name) : []
      end

      def model_prompt_cache_enabled
        ns_settings = namespace.namespace_settings

        ns_settings ? ns_settings.model_prompt_cache_enabled : root_namespace.model_prompt_cache_enabled
      end

      def mcp_config_service
        ::Ai::DuoWorkflows::McpConfigService.new(
          current_user,
          gitlab_token,
          workflow_definition: request_metadata.workflow_definition,
          ai_catalog_item_version_id: request_metadata.ai_catalog_item_version_id,
          namespace: project&.project_namespace || enforcement_namespace
        )
      end
      strong_memoize_attr :mcp_config_service

      # Project-level blocks live on the project namespace (SetBlockService), so it wins.
      # The group namespace is anchored to the validated root because it can come from the
      # unvalidated X-Gitlab-Namespace-Id header; unanchored, a foreign header would skip
      # this hierarchy's blocks. Freshness relies on the web client reconnecting per message
      # and per approval; a persistent socket would degrade enforcement to per-session. See
      # https://gitlab.com/gitlab-org/modelops/applied-ml/code-suggestions/ai-assist/-/work_items/2694.
      def enforcement_namespace
        return namespace if namespace.root_ancestor.id == root_namespace.id

        root_namespace
      end

      # root_namespace and project are caller-supplied, so a policy resolved from them is
      # not necessarily the one the executed workflow is subject to.
      def tool_access_policies
        container = workflow&.resource_parent

        # Without a container everything below falls back to the request context, which
        # is what this no longer trusts.
        return no_tool_access_policies if workflow && container.nil?

        governance_namespace = container&.root_ancestor || root_namespace
        governance_surface = governance_surface_for(container, governance_namespace)

        # Must stay empty: DWS reads empty allow/ask/deny as governance inactive and
        # keeps the client's pre-approvals. A non-empty allow would replace them.
        # Pinned DWS-side by test_compile_and_run_graph_keeps_client_preapproved_when_governance_inactive.
        return no_tool_access_policies if ::Ai::ToolRules::GovernanceSurface.ungoverned?(governance_surface)

        governance_surface ||= :web

        own_project =
          if container.is_a?(::Project)
            container
          elsif workflow.nil?
            project
          end

        policy = resolve_rules(governance_namespace, governance_surface, own_project)
        return no_tool_access_policies unless policy

        policy = tighten_with_requested_project(policy, governance_namespace, governance_surface, own_project)

        # MCP pre-approvals are appended after governance has resolved, so a verdict
        # has to be subtracted again here or the append outlives it.
        allowed_tools = policy[:pre_approved_tools] + mcp_config_service.preapproved_tool_names
        allowed_tools -= policy[:ask_tools]
        allowed_tools -= policy[:denied_tools]

        policies = {
          allow: allowed_tools.uniq,
          ask: policy[:ask_tools],
          deny: policy[:denied_tools]
        }
        # Inside the signed claim, so a client cannot drop it the way it could a flag header.
        policies[:ceiling] = true if Feature.enabled?(:duo_workflow_governance_ceiling, governance_namespace)
        policies
      end
      strong_memoize_attr :tool_access_policies

      # Returns the raw surface. Defaulting to :web here would swallow UNGOVERNED, and an
      # ungoverned session must not be resolved at all.
      def governance_surface_for(container, governance_namespace)
        # `||` here would also fire for a workflow whose environment is nil, letting the
        # request pick the surface for a session it named.
        environment = workflow ? workflow.environment : request_metadata.environment

        ::Ai::ToolRules::GovernanceSurface.for(
          environment: environment,
          container: container || governance_namespace,
          workflow_definition: workflow&.workflow_definition
        )
      end

      def resolve_rules(namespace, surface, project)
        result = ::Ai::ToolRules::ResolutionService.new(
          namespace: namespace, surface: surface, project: project
        ).execute

        return unless result.success?

        result.payload.slice(:pre_approved_tools, :ask_tools, :denied_tools)
      end

      # A project the workflow does not run in may only restrict this policy, never widen it.
      def tighten_with_requested_project(policy, namespace, surface, own_project)
        requested = project
        return policy if requested.nil? || requested == own_project
        return policy unless requested.root_ancestor.id == namespace.id

        # Falling back is safe: the workflow's own policy is already authoritative for it.
        tightened = resolve_rules(namespace, surface, requested)
        return policy unless tightened

        denied = policy[:denied_tools] | tightened[:denied_tools]
        {
          # Intersected, not subtracted: the project's own resolution is authoritative for what
          # it pre-approves, so a tool it leaves out drops here whether a rule or a group
          # verdict removed it.
          pre_approved_tools: policy[:pre_approved_tools] & tightened[:pre_approved_tools],
          ask_tools: (policy[:ask_tools] | tightened[:ask_tools]) - denied,
          denied_tools: denied
        }
      end

      def no_tool_access_policies
        { allow: [], ask: [], deny: [] }
      end
    end
  end
end
