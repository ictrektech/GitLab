# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::BlSecurity::Definition, feature_category: :duo_agent_platform do
  include ProjectForksHelper
  using RSpec::Parameterized::TableSyntax

  def stub_gitlab_enabled(enabled)
    allow(Ai::Catalog::FoundationalFlows::EnabledFlowsClient).to receive(:enabled?)
      .with('bl_security').and_return(enabled)
  end

  subject(:flow) { Ai::Catalog::FoundationalFlow.bl_security_experimental }

  it 'is a beta feature' do
    expect(flow.feature_maturity).to eq('beta')
  end

  it 'is gated by the bl_security_analyzer feature flag' do
    expect(flow.feature_flag).to eq('bl_security_analyzer')
  end

  it 'runs only on GitLab-hosted runners' do
    expect(flow.gitlab_hosted_runner_only).to be(true)
  end

  it 'uses the bl_security AI feature' do
    expect(flow.ai_feature).to eq('bl_security')
  end

  it 'is available on GitLab.com and on the Dedicated instances GitLab has enabled it for' do
    expect(flow.available_on).to eq(%i[gitlab_com dedicated_enabled_instances])
  end

  describe 'availability for a group' do
    let(:group) { build_stubbed(:group) }

    before do
      allow(group).to receive(:licensed_feature_available?).with(:ai_features).and_return(true)
    end

    context 'on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
        allow(group).to receive(:experiment_features_enabled).and_return(true)
      end

      it 'is available with the bl_security_analyzer flag on' do
        stub_feature_flags(bl_security_analyzer: true)

        expect(flow.available_for?(group)).to be(true)
      end

      it 'is not available with the bl_security_analyzer flag off, even with the instance beta setting on' do
        stub_feature_flags(bl_security_analyzer: false)
        stub_application_setting(instance_level_ai_beta_features_enabled: true)

        expect(flow.available_for?(group)).to be(false)
      end
    end

    context 'on GitLab Dedicated', :dedicated do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        stub_feature_flags(bl_security_analyzer: false)
      end

      where(:beta_setting, :gitlab_enabled, :expected) do
        true  | true  | true
        true  | false | false
        false | true  | false
      end

      with_them do
        it 'is available only when GitLab enabled the instance and the beta setting is on' do
          stub_application_setting(instance_level_ai_beta_features_enabled: beta_setting)
          stub_gitlab_enabled(gitlab_enabled)

          expect(flow.available_for?(group)).to be(expected)
        end
      end
    end

    context 'on Self-Managed' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        stub_application_setting(instance_level_ai_beta_features_enabled: true)
      end

      it 'is not available, even with the flag and the instance beta setting on' do
        stub_feature_flags(bl_security_analyzer: true)

        expect(flow.available_for?(group)).to be(false)
      end
    end
  end

  describe '.scan_profiles_enabled_for?' do
    let(:group) { build_stubbed(:group) }

    before do
      stub_saas_features(gitlab_com_subscriptions: true)
    end

    where(:beta, :flag, :experiment_features, :expected) do
      false | true  | false | true
      false | false | true  | false
      true  | true  | false | false
      true  | true  | true  | true
      true  | false | true  | false
    end

    with_them do
      it 'needs the flow on and, while it is beta, the Experiment and beta features setting' do
        allow(flow).to receive(:beta?).and_return(beta)
        stub_feature_flags(bl_security_analyzer: flag)
        allow(group).to receive(:experiment_features_enabled).and_return(experiment_features)

        expect(described_class.scan_profiles_enabled_for?(group)).to be(expected)
      end
    end
  end

  it 'keeps only session metadata' do
    expect(flow.content_retention).to eq('metadata')
  end

  it 'creates and supports only a pipeline_hooks trigger' do
    expect(flow.triggers).to eq([::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]])
    expect(flow.supported_events).to eq([::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]])
  end

  it 'runs automatically on merge request and non-default branch pipelines' do
    expect(flow.precondition).to eq({
      'match' => 'all',
      'rules' => [
        { 'field' => 'object_attributes.source', 'operator' => 'in', 'value' => %w[merge_request_event push] },
        { 'field' => 'object_attributes.default_branch', 'operator' => 'eq', 'value' => false }
      ]
    })
  end

  describe 'which pipelines fire the flow' do
    # The auto-created trigger carries the default trigger filter, and the real
    # Ai::FlowTriggers::FilterEvaluator ANDs it with the flow's precondition.
    let(:flow_trigger) do
      build(:ai_flow_trigger, filter: flow.default_trigger_filter).tap do |trigger|
        allow(trigger).to receive(:foundational_flow).and_return(flow)
      end
    end

    where(:source, :default_branch, :status, :fires) do
      'merge_request_event' | false | 'success' | true
      'merge_request_event' | false | 'failed'  | false
      'merge_request_event' | false | 'running' | false
      'push'                | true  | 'success' | false
      'push'                | false | 'success' | true
      'push'                | false | 'failed'  | false
      'schedule'            | true  | 'success' | false
      'parent_pipeline'     | false | 'success' | false
      'parent_pipeline'     | true  | 'success' | false
    end

    with_them do
      let(:data) do
        { object_attributes: { source: source, default_branch: default_branch, status: status } }
      end

      it 'matches the expected pipelines' do
        evaluator = ::Ai::FlowTriggers::FilterEvaluator.new(
          flow_trigger: flow_trigger, hook_scope: :pipeline_hooks, data: data
        )

        expect(evaluator.allowed?).to be(fires)
      end
    end
  end

  describe 'goal validation' do
    let_it_be(:project) { create(:project, :repository) }
    let_it_be(:merge_request, refind: true) { create(:merge_request, source_project: project) }

    subject(:result) { flow.validate_start_request(container: project, goal: goal) }

    context 'when the goal is a merge request that only deletes files' do
      let(:goal) { merge_request.iid.to_s }

      before do
        MergeRequestDiffFile.where(merge_request_diff_id: merge_request.merge_request_diff.id)
          .update_all(deleted_file: true)
      end

      it 'refuses the run and logs why' do
        allow(::Gitlab::AppJsonLogger).to receive(:info)
        expect(::Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including(project_id: project.id, goal: goal)
        )

        expect(result).to be_error
        expect(result.reason).to eq(:no_files_to_scan)
      end

      context 'when the bl_security_analyzer feature flag is disabled' do
        before do
          stub_feature_flags(bl_security_analyzer: false)
        end

        it { is_expected.to be_nil }

        context 'on GitLab Dedicated', :dedicated do
          it 'still refuses the run when GitLab enabled the instance and the beta setting is on' do
            stub_application_setting(instance_level_ai_beta_features_enabled: true)
            stub_gitlab_enabled(true)

            expect(result).to be_error
            expect(result.reason).to eq(:no_files_to_scan)
          end

          it 'skips the checks with the instance beta setting off' do
            stub_application_setting(instance_level_ai_beta_features_enabled: false)

            expect(result).to be_nil
          end
        end
      end
    end

    context 'when the goal is a merge request IID' do
      let(:goal) { merge_request.iid.to_s }

      it { is_expected.to be_nil }
    end

    context 'when the goal is an IID that matches no merge request' do
      let(:goal) { non_existing_record_iid.to_s }

      it 'refuses the run and logs why' do
        expect(::Gitlab::AppJsonLogger).to receive(:info).with(
          hash_including(message: 'Business logic security scan not started: merge request not found', goal: goal)
        )

        expect(result).to be_error
        expect(result.reason).to eq(:invalid_goal)
      end
    end

    context 'when the goal is the IID of a merge request that is not open' do
      where(state: %i[closed merged])

      with_them do
        let(:goal) { create(:merge_request, state, source_project: project).iid.to_s }

        it 'refuses the run and logs why' do
          expect(::Gitlab::AppJsonLogger).to receive(:info).with(
            hash_including(message: 'Business logic security scan not started: the merge request is not open')
          )

          expect(result).to be_error
          expect(result.message).to eq('The merge request is not open')
          expect(result.reason).to eq(:invalid_goal)
        end
      end
    end

    context 'when the goal is a resource URL' do
      let(:goal) { 'http://example.com/pipelines/1' }

      it { is_expected.to be_nil }
    end

    context 'when the goal is a branch pipeline' do
      let_it_be(:branch_pipeline) do
        create(:ci_pipeline, source: :push, project: project, ref: merge_request.source_branch,
          sha: merge_request.diff_head_sha)
      end

      let(:goal) do
        ::Ai::Catalog::GoalTemplates::BlSecurity.resolve(event_type: :pipeline_hooks, resource: branch_pipeline)
      end

      shared_examples 'refuses the branch pipeline' do
        it 'refuses the run and logs why' do
          allow(::Gitlab::AppJsonLogger).to receive(:info)
          expect(::Gitlab::AppJsonLogger).to receive(:info).with(
            hash_including(
              message: 'Business logic security scan not started: ' \
                'pipeline is not the head pipeline of an open merge request'
            )
          )

          expect(result).to be_error
          expect(result.reason).to eq(:no_merge_request)
        end
      end

      context 'when it is the head pipeline of an open merge request' do
        before do
          merge_request.update!(head_pipeline: branch_pipeline)
        end

        it 'passes with the merge request goal' do
          expect(goal).to eq(merge_request.iid.to_s)
          expect(result).to be_nil
        end

        context 'when the merge request is closed' do
          before do
            merge_request.close!
          end

          it_behaves_like 'refuses the branch pipeline'
        end
      end

      context 'when no merge request has it as head pipeline' do
        it_behaves_like 'refuses the branch pipeline'
      end

      # The MR pipeline is the head pipeline, so the branch pipeline is refused.
      context 'when the merge request head pipeline is its merge request pipeline' do
        before do
          merge_request.update!(
            head_pipeline: create(:ci_pipeline, :detached_merge_request_pipeline, merge_request: merge_request)
          )
        end

        it_behaves_like 'refuses the branch pipeline'
      end
    end

    context 'when the merge request is from a fork' do
      let_it_be(:fork) { fork_project(project, nil, repository: true) }
      let_it_be(:fork_merge_request) do
        create(:merge_request, source_project: fork, target_project: project, source_branch: 'feature')
      end

      shared_examples 'refuses the fork merge request' do
        it 'refuses the run and logs why' do
          allow(::Gitlab::AppJsonLogger).to receive(:info)
          expect(::Gitlab::AppJsonLogger).to receive(:info).with(
            hash_including(
              message: 'Business logic security scan not started: merge request is from a fork',
              merge_request_id: fork_merge_request.id
            )
          )

          expect(result).to be_error
          expect(result.reason).to eq(:fork_merge_request)
        end
      end

      context 'when its pipeline runs in the fork' do
        subject(:result) { flow.validate_start_request(container: fork, goal: goal) }

        let(:goal) do
          pipeline = create(:ci_pipeline, :detached_merge_request_pipeline, merge_request: fork_merge_request)
          ::Ai::Catalog::GoalTemplates::BlSecurity.resolve(event_type: :pipeline_hooks, resource: pipeline)
        end

        it_behaves_like 'refuses the fork merge request'
      end

      context 'when its pipeline runs in the target project' do
        let(:goal) do
          pipeline = create(:ci_pipeline, :detached_merge_request_pipeline,
            merge_request: fork_merge_request, project: project)
          ::Ai::Catalog::GoalTemplates::BlSecurity.resolve(event_type: :pipeline_hooks, resource: pipeline)
        end

        it_behaves_like 'refuses the fork merge request'
      end

      context 'when the goal is its IID' do
        let(:goal) { fork_merge_request.iid.to_s }

        it_behaves_like 'refuses the fork merge request'
      end
    end

    context 'when the container is a group' do
      subject(:result) { flow.validate_start_request(container: create(:group), goal: '1') }

      it { is_expected.to be_nil }
    end
  end

  describe 'source branch resolution' do
    let_it_be(:project) { create(:project, :repository) }
    let_it_be(:merge_request) { create(:merge_request, :simple, source_project: project) }

    subject(:source_branch) { flow.resolve_source_branch_for(project: project, goal: goal) }

    context 'when the goal is a merge request IID' do
      let(:goal) { merge_request.iid.to_s }

      it { is_expected.to eq('feature') }
    end

    context 'when the goal is a fork merge request IID' do
      let_it_be(:fork) { fork_project(project, nil, repository: true) }
      let_it_be(:fork_merge_request) do
        create(:merge_request, source_project: fork, target_project: project, source_branch: 'feature')
      end

      let(:goal) { fork_merge_request.iid.to_s }

      it { is_expected.to be_nil }
    end

    context 'when the goal is not a merge request IID' do
      let(:goal) { "http://example.com/pipelines/#{merge_request.iid}" }

      it { is_expected.to be_nil }
    end

    context 'when no merge request matches the IID' do
      let(:goal) { non_existing_record_iid.to_s }

      it { is_expected.to be_nil }
    end

    context 'when the merge request is not open' do
      let(:goal) { create(:merge_request, :closed, source_project: project).iid.to_s }

      it { is_expected.to be_nil }
    end
  end

  it 'declares the SAST report artifact' do
    expect(flow.report_artifacts.stringify_keys).to eq('sast' => ['gl-sast-report.json'])
  end
end
