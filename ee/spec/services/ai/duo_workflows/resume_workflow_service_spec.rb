# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Ai::DuoWorkflows::ResumeWorkflowService, :request_store, feature_category: :duo_agent_platform do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :small_repo, group: group) }
  let_it_be(:maintainer) { create(:user, maintainer_of: project) }

  let(:image) { 'example.com/example-image:latest' }
  let(:workflow) { create(:duo_workflows_workflow, user: maintainer, image: image, project: project) }
  let(:duo_config) { instance_double(::Gitlab::DuoAgentPlatform::Config) }
  let(:sandbox) { instance_double(::Gitlab::DuoWorkflow::Sandbox) }

  let(:params) do
    {
      goal: 'test-goal',
      workflow: workflow,
      workflow_oauth_token: 'fresh-oauth-token',
      workflow_service_token: 'fresh-service-token',
      workflow_metadata: { key: 'val' }.to_json,
      human_approval: true,
      human_message: 'looks good',
      service_account: service_account
    }
  end

  let(:duo_cli_command) do
    "duo run --existing-session-id #{workflow.id} --connection-type websocket " \
      "--approval true --rejection-reason looks\\ good"
  end

  let(:wrapped_commands) do
    [
      %(if which srt > /dev/null; then),
      %(  echo "SRT found, creating config..."),
      %(  srt --settings /tmp/srt-settings.json #{duo_cli_command}),
      %(fi)
    ]
  end

  let(:sandbox_env_vars) { { NPM_CONFIG_CACHE: "/tmp/.npm-cache" } }
  let(:sandbox_setup_commands) { ["mkdir -p #{::Gitlab::DuoWorkflow::Sandbox::SANDBOX_SYSTEM_DIR}"] }

  let_it_be(:service_account) { create(:user, :service_account) }

  before_all do
    project.add_member(service_account, Gitlab::Access::DEVELOPER)
  end

  subject(:execute) { described_class.new(workflow: workflow, params: params).execute }

  before do
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(project, :duo_workflow).and_return(true)
    allow(maintainer).to receive(:allowed_to_use?).and_return(true)
    allow(::Gitlab::DuoAgentPlatform::Config).to receive(:new).with(project).and_return(duo_config)
    allow(duo_config).to receive_messages(
      config_present?: false,
      valid_format?: true,
      default_image: nil,
      cache_config: nil,
      setup_script: nil,
      network_policy: nil,
      id_tokens: nil,
      reference_repository_path: nil
    )
    allow(::Gitlab::DuoWorkflow::Sandbox).to receive(:new).and_return(sandbox)
    allow(sandbox).to receive(:wrap_command).with(duo_cli_command).and_return(wrapped_commands)
    allow(sandbox).to receive_messages(
      setup_sandbox_commands: sandbox_setup_commands,
      environment_variables: sandbox_env_vars
    )
    allow(Ci::Workloads::RunWorkloadService).to receive(:new).and_call_original
  end

  context 'when a previous workload exists' do
    let!(:previous_pipeline) { create(:ci_pipeline, project: project) }
    let(:previous_variables) do
      [
        { key: 'DUO_WORKFLOW_GOAL', value: 'original-goal' },
        { key: 'DUO_WORKFLOW_SOURCE_BRANCH', value: 'feature-branch' },
        { key: 'DUO_WORKFLOW_ADDITIONAL_CONTEXT_CONTENT', value: 'previous context' },
        { key: 'GITLAB_OAUTH_TOKEN', value: 'old-expired-token' },
        { key: 'DUO_WORKFLOW_SERVICE_TOKEN', value: 'old-service-token' },
        { key: 'GIT_PASSWORD', value: 'old-expired-token' },
        { key: 'GITLAB_TOKEN', value: 'old-expired-token' },
        { key: 'DUO_WORKFLOW_GIT_HTTP_PASSWORD', value: 'old-expired-token' },
        { key: 'CUSTOM_PREVIOUS_VAR', value: 'custom-value' }
      ]
    end

    let!(:previous_build) do
      create(:ci_build, pipeline: previous_pipeline, yaml_variables: previous_variables)
    end

    let!(:previous_workload) { create(:ci_workload, pipeline: previous_pipeline, project: project) }
    let!(:workflows_workload) do
      create(:duo_workflows_workload, workflow: workflow, workload: previous_workload, project: project)
    end

    it 'carries forward variables from the previous workload' do
      expect(Ci::Workloads::RunWorkloadService)
        .to receive(:new).and_wrap_original do |method, **kwargs|
        variables = kwargs[:workload_definition].variables

        expect(variables[:DUO_WORKFLOW_SOURCE_BRANCH]).to eq('feature-branch')
        expect(variables[:DUO_WORKFLOW_ADDITIONAL_CONTEXT_CONTENT]).to eq('previous context')
        expect(variables[:CUSTOM_PREVIOUS_VAR]).to eq('custom-value')
        method.call(**kwargs)
      end

      expect(execute).to be_success
    end

    it 'overrides the goal with the new value' do
      expect(Ci::Workloads::RunWorkloadService)
        .to receive(:new).and_wrap_original do |method, **kwargs|
        variables = kwargs[:workload_definition].variables

        expect(variables[:DUO_WORKFLOW_GOAL]).to eq('test-goal')
        method.call(**kwargs)
      end

      expect(execute).to be_success
    end

    context 'when the previous workload named a different flow version' do
      let(:previous_variables) do
        super() + [
          { key: 'DUO_WORKFLOW_FLOW_CONFIG_ID', value: 'developer' },
          { key: 'DUO_WORKFLOW_FLOW_CONFIG_SCHEMA_VERSION', value: 'v1' },
          { key: 'DUO_WORKFLOW_FLOW_VERSION', value: '^4.0.0' }
        ]
      end

      let(:params) do
        super().merge(flow_config_id: 'developer', flow_config_schema_version: 'v1', flow_version: '4.0.0')
      end

      it 'names the flow the workflow token is bound to' do
        expect(Ci::Workloads::RunWorkloadService).to receive(:new).and_wrap_original do |method, **kwargs|
          expect(kwargs[:workload_definition].variables).to include(
            DUO_WORKFLOW_FLOW_CONFIG_ID: 'developer',
            DUO_WORKFLOW_FLOW_CONFIG_SCHEMA_VERSION: 'v1',
            DUO_WORKFLOW_FLOW_VERSION: '4.0.0'
          )
          method.call(**kwargs)
        end

        expect(execute).to be_success
      end
    end

    it 'does not echo the goal into the job trace' do
      expect(Ci::Workloads::RunWorkloadService)
        .to receive(:new).and_wrap_original do |method, **kwargs|
        commands = kwargs[:workload_definition].commands

        expect(commands).not_to include(a_string_including('DUO_WORKFLOW_GOAL'))
        expect(commands).to include('echo $DUO_WORKFLOW_SOURCE_BRANCH')
        method.call(**kwargs)
      end

      expect(execute).to be_success
    end

    context 'with source-stage retries', :aggregate_failures do
      shared_examples 'a resumed workload with source-stage retries' do
        it 'enables source-stage retries' do
          expect(Ci::Workloads::RunWorkloadService).to receive(:new).and_wrap_original do |method, **kwargs|
            expect(kwargs[:workload_definition].variables).to include(GET_SOURCES_ATTEMPTS: 6)
            method.call(**kwargs)
          end

          expect(execute).to be_success
        end
      end

      it_behaves_like 'a resumed workload with source-stage retries'

      context 'when the previous workload had source-stage retries' do
        let(:previous_variables) do
          super() + [{ key: 'GET_SOURCES_ATTEMPTS', value: '6' }]
        end

        shared_examples 'a resumed workload without source-stage retries' do
          it 'removes the previous retry variables' do
            expect(Ci::Workloads::RunWorkloadService).to receive(:new).and_wrap_original do |method, **kwargs|
              definition = kwargs[:workload_definition]

              expect(definition.variables).not_to include(:GET_SOURCES_ATTEMPTS)
              expect(definition.variables[:CUSTOM_PREVIOUS_VAR]).to eq('custom-value')
              method.call(**kwargs)
            end

            expect(execute).to be_success
          end
        end

        context 'when the flag is disabled at resume' do
          before do
            stub_feature_flags(dap_session_source_fetch_retry: false)
          end

          it_behaves_like 'a resumed workload without source-stage retries'
        end

        context 'when the coding environment is none' do
          let(:params) { super().merge(flow_config: { 'coding_environment' => 'none', 'version' => 'v1' }) }

          it_behaves_like 'a resumed workload without source-stage retries'
        end

        context 'when the previous workload skipped checkout' do
          let(:previous_variables) { super() + [{ key: 'GIT_STRATEGY', value: 'none' }] }

          it_behaves_like 'a resumed workload without source-stage retries'
        end
      end
    end

    it 'overrides token variables with fresh values' do
      expect(Ci::Workloads::RunWorkloadService)
        .to receive(:new).and_wrap_original do |method, **kwargs|
        variables = kwargs[:workload_definition].variables

        expect(variables[:GITLAB_OAUTH_TOKEN]).to eq('fresh-oauth-token')
        expect(variables[:DUO_WORKFLOW_SERVICE_TOKEN]).to eq('fresh-service-token')
        expect(variables[:GIT_PASSWORD]).to eq('fresh-oauth-token')
        expect(variables[:GITLAB_TOKEN]).to eq('fresh-oauth-token')
        expect(variables[:DUO_WORKFLOW_GIT_HTTP_PASSWORD]).to eq('fresh-oauth-token')
        method.call(**kwargs)
      end

      expect(execute).to be_success
    end

    context 'when the sandbox environment variables changed since the previous workload' do
      let(:previous_variables) { super() + [{ key: 'NPM_CONFIG_CACHE', value: '/old/npm-cache' }] }
      let(:sandbox_env_vars) { { NPM_CONFIG_CACHE: "/tmp/.npm-cache", GITLAB_BIN_DIR: "/tmp/gitlab-bin" } }

      it 'applies the current sandbox environment variables', :aggregate_failures do
        expect(Ci::Workloads::RunWorkloadService)
          .to receive(:new).and_wrap_original do |method, **kwargs|
          variables = kwargs[:workload_definition].variables

          expect(variables[:NPM_CONFIG_CACHE]).to eq('/tmp/.npm-cache')
          expect(variables[:GITLAB_BIN_DIR]).to eq('/tmp/gitlab-bin')
          method.call(**kwargs)
        end

        expect(execute).to be_success
      end
    end
  end

  context 'when no previous workload exists' do
    it 'falls back to computing variables from scratch' do
      expect(execute).to be_success
    end

    it 'does not set a runtime_environment_key' do
      expect(Ci::Workloads::RunWorkloadService)
        .to receive(:new).and_wrap_original do |method, **kwargs|
        expect(kwargs[:workload_definition].runtime_environment_key).to be_nil
        method.call(**kwargs)
      end

      expect(execute).to be_success
    end
  end

  context 'when the previous build has a runtime environment' do
    let_it_be(:previous_pipeline) { create(:ci_pipeline, project: project) }
    let_it_be(:previous_build) { create(:ci_build, pipeline: previous_pipeline) }
    let_it_be(:runtime_environment) { create(:ci_runtime_environment, project: project) }
    let_it_be(:previous_workload) { create(:ci_workload, pipeline: previous_pipeline, project: project) }
    let_it_be(:job_runtime_environment) do
      create(:ci_job_runtime_environment, build: previous_build, runtime_environment: runtime_environment)
    end

    let!(:workflows_workload) do
      create(:duo_workflows_workload, workflow: workflow, workload: previous_workload, project: project)
    end

    it 'carries forward the runtime_environment_key so the runner can route to the same machine' do
      expect(Ci::Workloads::RunWorkloadService)
        .to receive(:new).and_wrap_original do |method, **kwargs|
        workload_definition = kwargs[:workload_definition]
        expect(workload_definition.runtime_environment_key).to eq(runtime_environment.environment_key)
        method.call(**kwargs)
      end

      expect(execute).to be_success
    end
  end

  context 'when the previous build has no runtime environment' do
    let_it_be(:previous_pipeline) { create(:ci_pipeline, project: project) }
    let_it_be(:previous_build) { create(:ci_build, pipeline: previous_pipeline) }
    let_it_be(:previous_workload) { create(:ci_workload, pipeline: previous_pipeline, project: project) }
    let!(:workflows_workload) do
      create(:duo_workflows_workload, workflow: workflow, workload: previous_workload, project: project)
    end

    it 'does not set a runtime_environment_key' do
      expect(Ci::Workloads::RunWorkloadService)
        .to receive(:new).and_wrap_original do |method, **kwargs|
        expect(kwargs[:workload_definition].runtime_environment_key).to be_nil
        method.call(**kwargs)
      end

      expect(execute).to be_success
    end
  end

  context 'when a previous workload exists with empty yaml_variables' do
    let!(:previous_pipeline) { create(:ci_pipeline, project: project) }
    let!(:previous_build) do
      create(:ci_build, pipeline: previous_pipeline, yaml_variables: [])
    end

    let!(:previous_workload) { create(:ci_workload, pipeline: previous_pipeline, project: project) }
    let!(:workflows_workload) do
      create(:duo_workflows_workload, workflow: workflow, workload: previous_workload, project: project)
    end

    it 'falls back to computing variables from scratch via super' do
      expect(Ci::Workloads::RunWorkloadService)
        .to receive(:new).and_wrap_original do |method, **kwargs|
        variables = kwargs[:workload_definition].variables

        expect(variables[:DUO_WORKFLOW_GOAL]).to eq('test-goal')
        expect(variables[:GITLAB_OAUTH_TOKEN]).to eq('fresh-oauth-token')
        method.call(**kwargs)
      end

      expect(execute).to be_success
    end
  end

  context 'when human_approval is nil' do
    let(:params) { super().merge(human_approval: nil, human_message: nil) }
    let(:duo_cli_command) do
      "duo run --existing-session-id #{workflow.id} --connection-type websocket"
    end

    it 'omits --approval entirely, rather than sending it empty' do
      expect(execute).to be_success

      expect(sandbox).to have_received(:wrap_command) do |command|
        expect(command).not_to include('--approval')
      end
    end
  end

  context 'when human_approval is false and human_message is nil' do
    let(:params) { super().merge(human_approval: false, human_message: nil) }
    let(:duo_cli_command) do
      "duo run --existing-session-id #{workflow.id} --connection-type websocket " \
        "--approval false"
    end

    it 'omits --rejection-reason when human_message is nil' do
      expect(execute).to be_success
    end
  end

  context 'when human_approval is false' do
    let(:params) { super().merge(human_approval: false, human_message: 'not ready yet') }
    let(:duo_cli_command) do
      "duo run --existing-session-id #{workflow.id} --connection-type websocket " \
        "--approval false --rejection-reason not\\ ready\\ yet"
    end

    it 'renders boolean false as string in the CLI command' do
      expect(execute).to be_success
    end
  end

  context 'when human_message contains shell metacharacters' do
    let(:params) { super().merge(human_message: '"; rm -rf /; echo "pwned') }
    let(:duo_cli_command) do
      escaped = Shellwords.shellescape('"; rm -rf /; echo "pwned')
      "duo run --existing-session-id #{workflow.id} --connection-type websocket " \
        "--approval true --rejection-reason #{escaped}"
    end

    it 'escapes shell metacharacters in human_message' do
      expect(execute).to be_success
    end
  end

  # Git config is recomputed rather than carried forward, so a flag flip between start
  # and resume cannot leave the variables and the git-auth commands on opposite paths.
  context 'when dap_git_credential_helper was on at start and is off at resume' do
    let!(:previous_pipeline) { create(:ci_pipeline, project: project) }
    let!(:previous_build) do
      create(:ci_build, pipeline: previous_pipeline, yaml_variables: [
        { key: 'DUO_WORKFLOW_SOURCE_BRANCH', value: 'feature-branch' },
        { key: 'FF_GIT_URLS_WITHOUT_TOKENS', value: 'true' },
        { key: 'GIT_CONFIG_COUNT', value: '5' },
        { key: 'GIT_CONFIG_KEY_3', value: "credential.#{described_class.gitlab_origin}.helper" },
        { key: 'GIT_CONFIG_VALUE_3', value: described_class.git_credential_helper }
      ])
    end

    let!(:previous_workload) { create(:ci_workload, pipeline: previous_pipeline, project: project) }
    let!(:workflows_workload) do
      create(:duo_workflows_workload, workflow: workflow, workload: previous_workload, project: project)
    end

    before do
      stub_feature_flags(dap_git_credential_helper: false)
    end

    it 'ships the flag-off git config the resumed commands were built for' do
      expect(Ci::Workloads::RunWorkloadService)
        .to receive(:new).and_wrap_original do |method, **kwargs|
        definition = kwargs[:workload_definition]

        expect(definition.variables).not_to have_key(:FF_GIT_URLS_WITHOUT_TOKENS)
        expect(definition.variables[:GIT_CONFIG_COUNT]).to eq('3')
        expect(definition.variables.values).not_to include(described_class.git_credential_helper)
        expect(definition.commands.join("\n")).to include('git remote set-url origin')
        method.call(**kwargs)
      end

      expect(execute).to be_success
    end
  end

  context 'with a git_strategy reference repository', :aggregate_failures do
    let!(:previous_pipeline) { create(:ci_pipeline, project: project) }
    let(:git_strategy_variables) do
      [
        { key: 'GIT_STRATEGY', value: 'empty' },
        { key: 'GIT_LFS_SKIP_SMUDGE', value: '1' },
        { key: 'DUO_WORKFLOW_REFERENCE_REPOSITORY_PATH', value: '/opt/duo/ref.git' }
      ]
    end

    let!(:previous_build) do
      create(:ci_build, pipeline: previous_pipeline, yaml_variables: [
        { key: 'DUO_WORKFLOW_SOURCE_BRANCH', value: 'feature-branch' },
        *git_strategy_variables
      ])
    end

    let!(:previous_workload) { create(:ci_workload, pipeline: previous_pipeline, project: project) }
    let!(:workflows_workload) do
      create(:duo_workflows_workload, workflow: workflow, workload: previous_workload, project: project)
    end

    let(:reference_repository_path) { '/opt/duo/ref.git' }
    let(:captured) { [] }

    before do
      allow(duo_config).to receive(:reference_repository_path).and_return(reference_repository_path)
      allow(Ci::Workloads::RunWorkloadService).to receive(:new).and_wrap_original do |method, **kwargs|
        captured << kwargs[:workload_definition]
        method.call(**kwargs)
      end
    end

    def workload_definition
      expect(execute).to be_success

      captured.last
    end

    shared_examples 'a resumed workload cloned by the runner' do
      it 'replaces the reference repository variables and clone commands with a full native clone' do
        definition = workload_definition

        expect(definition.variables).to include(
          GIT_STRATEGY: 'clone',
          GIT_DEPTH: 0,
          GIT_LFS_SKIP_SMUDGE: 1,
          FF_USE_GIT_NATIVE_CLONE: 'true',
          GIT_CLONE_EXTRA_FLAGS: '--quiet',
          GET_SOURCES_ATTEMPTS: 6
        )
        expect(definition.variables).not_to have_key(:DUO_WORKFLOW_REFERENCE_REPOSITORY_PATH)
        expect(definition.commands.join("\n")).not_to include('.git/objects/info/alternates')
        expect(definition.commands.join("\n")).to include('remote set-url origin')
      end

      context 'when dap_unfiltered_clone is disabled' do
        before do
          stub_feature_flags(dap_unfiltered_clone: false)
        end

        it 'replaces the reference repository variables with a full blobless fetch' do
          variables = workload_definition.variables

          expect(variables).to include(GIT_DEPTH: 0, GIT_FETCH_EXTRA_FLAGS: '--prune --quiet --filter=blob:none')
          expect(variables).not_to have_key(:GIT_STRATEGY)
          expect(variables).not_to have_key(:FF_USE_GIT_NATIVE_CLONE)
          expect(variables).not_to have_key(:DUO_WORKFLOW_REFERENCE_REPOSITORY_PATH)
        end
      end
    end

    shared_examples 'a resumed workload cloned from the reference repository' do |path|
      it 'ships the reference repository variables with the clone commands' do
        definition = workload_definition

        expect(definition.variables).to include(GIT_STRATEGY: 'empty', DUO_WORKFLOW_REFERENCE_REPOSITORY_PATH: path)
        expect(definition.variables.keys).not_to include(
          :FF_USE_GIT_NATIVE_CLONE, :GIT_CLONE_EXTRA_FLAGS, :GIT_FETCH_EXTRA_FLAGS
        )
        expect(definition.commands.join("\n")).to include('.git/objects/info/alternates')
      end
    end

    it_behaves_like 'a resumed workload cloned from the reference repository', '/opt/duo/ref.git'

    context 'when dap_reference_repository is turned off at resume' do
      before do
        stub_feature_flags(dap_reference_repository: false)
      end

      it_behaves_like 'a resumed workload cloned by the runner'
    end

    context 'when git_strategy is removed from agent-config at resume' do
      let(:reference_repository_path) { nil }

      it_behaves_like 'a resumed workload cloned by the runner'
    end

    context 'when the path changed in agent-config at resume' do
      let(:reference_repository_path) { '/opt/duo/new-ref.git' }

      it_behaves_like 'a resumed workload cloned from the reference repository', '/opt/duo/new-ref.git'
    end

    context 'when the first job did not use a reference repository' do
      let(:git_strategy_variables) { [{ key: 'GIT_DEPTH', value: '0' }] }

      it_behaves_like 'a resumed workload cloned from the reference repository', '/opt/duo/ref.git'
    end

    context 'when the previous workload skipped checkout' do
      let(:git_strategy_variables) { [{ key: 'GIT_STRATEGY', value: 'none' }] }

      it 'keeps skipping checkout' do
        variables = workload_definition.variables

        expect(variables).to include(GIT_STRATEGY: 'none')
        expect(variables).not_to have_key(:DUO_WORKFLOW_REFERENCE_REPOSITORY_PATH)
        expect(variables).not_to have_key(:GIT_DEPTH)
      end
    end
  end

  context 'when human_message contains subshell expansion' do
    let(:params) { super().merge(human_message: '$(whoami)') }
    let(:duo_cli_command) do
      escaped = Shellwords.shellescape('$(whoami)')
      "duo run --existing-session-id #{workflow.id} --connection-type websocket " \
        "--approval true --rejection-reason #{escaped}"
    end

    it 'escapes subshell expansion in human_message' do
      expect(execute).to be_success
    end
  end
end
