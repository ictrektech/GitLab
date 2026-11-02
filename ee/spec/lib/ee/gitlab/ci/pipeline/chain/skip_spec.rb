# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ci::Pipeline::Chain::Skip, feature_category: :pipeline_composition do
  let_it_be(:project) { create(:project, :small_repo) }
  let_it_be(:user) { create(:user) }
  let_it_be(:pipeline) { create(:ci_pipeline, project: project) }

  let(:command) do
    Gitlab::Ci::Pipeline::Chain::Command.new(
      project: project,
      current_user: user,
      ignore_skip_ci: false,
      save_incompleted: true,
      origin_ref: project.default_branch_or_main)
  end

  let(:step) { described_class.new(pipeline, command) }

  describe '#skipped?' do
    context 'when pipeline has not been skipped' do
      it 'does not break the chain' do
        expect(step.break?).to be false
      end
    end

    context 'when pipeline should be skipped' do
      before do
        allow(pipeline).to receive(:git_commit_message).and_return('commit message [ci skip]')
      end

      it 'breaks the chain' do
        expect(step.break?).to be true
      end

      context 'when execution policies are not allowing skip' do
        before do
          command.pipeline_policy_context = instance_double(
            Gitlab::Ci::Pipeline::ExecutionPolicies::PipelineContext,
            skip_ci_allowed?: false
          )
        end

        it 'does not break the chain' do
          expect(step.break?).to be false
        end
      end

      context 'when pipeline execution policies are allowing skip' do
        before do
          command.pipeline_policy_context = instance_double(
            Gitlab::Ci::Pipeline::ExecutionPolicies::PipelineContext,
            skip_ci_allowed?: true
          )
        end

        it 'breaks the chain' do
          expect(step.break?).to be true
        end
      end
    end

    context 'when the merge request title contains [ci skip]' do
      let(:merge_request) { build_stubbed(:merge_request, source_project: project, title: 'Title [ci skip]') }
      let(:command) do
        Gitlab::Ci::Pipeline::Chain::Command.new(
          project: project,
          current_user: user,
          ignore_skip_ci: false,
          save_incompleted: true,
          merge_request: merge_request,
          origin_ref: project.default_branch_or_main)
      end

      before do
        command.pipeline_policy_context = instance_double(
          Gitlab::Ci::Pipeline::ExecutionPolicies::PipelineContext,
          skip_ci_allowed?: skip_ci_allowed
        )
      end

      context 'when execution policies are not allowing skip' do
        let(:skip_ci_allowed) { false }

        it 'does not break the chain' do
          expect(step.break?).to be false
        end
      end

      context 'when execution policies are allowing skip' do
        let(:skip_ci_allowed) { true }

        it 'breaks the chain' do
          expect(step.break?).to be true
        end
      end
    end
  end

  describe '#perform!' do
    context 'when a project without CI config inherits the merge settings from its group' do
      let_it_be(:group) do
        create(:group).tap do |group|
          group.namespace_settings.update!(
            only_allow_merge_if_pipeline_succeeds: true,
            allow_merge_on_skipped_pipeline: true
          )
        end
      end

      let_it_be(:project) { create(:project, :small_repo, group: group) }
      let_it_be_with_reload(:pipeline) { create(:ci_pipeline, project: project) }

      before do
        stub_licensed_features(group_level_merge_checks_setting: true)
        allow(pipeline).to receive(:git_commit_message).and_return('commit message [ci skip]')
        allow_next_instance_of(Gitlab::Ci::ProjectConfig) do |instance|
          allow(instance).to receive(:exists?).and_return(false)
        end
      end

      it 'breaks the chain and skips the pipeline' do
        step.perform!

        expect(step.break?).to be true
        expect(pipeline.reload).to be_skipped
      end
    end
  end
end
