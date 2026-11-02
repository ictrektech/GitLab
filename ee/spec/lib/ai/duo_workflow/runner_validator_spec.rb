# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflow::RunnerValidator, feature_category: :duo_agent_platform do
  let_it_be(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:project) { create(:project, namespace: group) }

  describe '#valid?' do
    subject { described_class.new(runner, project).valid? }

    context 'with instance runner' do
      let(:runner) { create(:ci_runner, :instance) }

      it { is_expected.to be_truthy }
    end

    context 'with top level group runner' do
      let(:runner) { create(:ci_runner, :group, groups: [group]) }

      it { is_expected.to be_truthy }
    end

    context 'with subgroup runner' do
      let(:runner) { create(:ci_runner, :group, groups: [subgroup]) }

      it { is_expected.to be_falsey }
    end

    context 'with project runner' do
      let(:runner) { create(:ci_runner, :project, projects: [project]) }

      it { is_expected.to be_falsey }
    end

    context 'when duo_runner_restrictions is disabled' do
      before do
        stub_feature_flags(duo_runner_restrictions: false)
      end

      context 'with subgroup runner' do
        let(:runner) { create(:ci_runner, :group, groups: [subgroup]) }

        it { is_expected.to be_truthy }
      end

      context 'with project runner' do
        let(:runner) { create(:ci_runner, :project, projects: [project]) }

        it { is_expected.to be_truthy }
      end
    end
  end

  describe '#valid? for a job' do
    subject { described_class.new(runner, project, build: build).valid? }

    let_it_be(:pipeline) { create(:ci_pipeline, project: project, source: :duo_workflow) }
    let_it_be(:instance_runner) { create(:ci_runner, :instance) }
    let_it_be(:group_runner) { create(:ci_runner, :group, groups: [group]) }
    let_it_be(:subgroup_runner) { create(:ci_runner, :group, groups: [subgroup]) }

    let(:workflow_definition) { 'bl_security/experimental' }
    let(:workflow) { create(:duo_workflows_workflow, project: project, workflow_definition: workflow_definition) }
    let(:yaml_variables) { [] }
    let(:build) { create(:ci_build, pipeline: pipeline, yaml_variables: yaml_variables) }

    before do
      allow(Gitlab).to receive(:com?).and_return(true)
    end

    context 'when the workload links the job to its workflow' do
      before do
        create(:duo_workflows_workload, workflow: workflow, workload: create(:ci_workload, pipeline: pipeline))
      end

      context 'with a GitLab-hosted-runner-only flow' do
        context 'with a GitLab-hosted runner' do
          let(:runner) { instance_runner }

          it { is_expected.to be(true) }
        end

        context 'with a top level group runner' do
          let(:runner) { group_runner }

          it { is_expected.to be(false) }
        end

        context 'with an instance runner off GitLab.com' do
          let(:runner) { instance_runner }

          before do
            allow(Gitlab).to receive(:com?).and_return(false)
          end

          it { is_expected.to be(false) }
        end

        context 'when on GitLab Dedicated' do
          before do
            allow(Gitlab).to receive(:com?).and_return(false)
            stub_application_setting(gitlab_dedicated_instance: true)
          end

          context 'with a GitLab-hosted instance runner' do
            let(:runner) { create(:ci_runner, :instance, :hosted_runner) }

            before do
              create(:ci_hosted_runner, runner: runner)
            end

            it { is_expected.to be(true) }
          end

          context 'with a hosted registration on an instance runner a regular admin created' do
            let(:runner) { create(:ci_runner, :instance, creator: create(:admin)) }

            before do
              create(:ci_hosted_runner, runner: runner)
            end

            it { is_expected.to be(true) }
          end

          context 'with an instance runner created by the Admin Bot without a hosted registration' do
            let(:runner) { create(:ci_runner, :instance, :hosted_runner) }

            it { is_expected.to be(false) }
          end

          context 'with a customer-registered instance runner' do
            let(:runner) { create(:ci_runner, :instance, creator: create(:admin)) }

            it { is_expected.to be(false) }
          end

          context 'with a group runner created by the Admin Bot' do
            let(:runner) { create(:ci_runner, :group, :hosted_runner, groups: [group]) }

            it { is_expected.to be(false) }
          end
        end

        context 'when duo_runner_restrictions is disabled' do
          let(:runner) { group_runner }

          before do
            stub_feature_flags(duo_runner_restrictions: false)
          end

          it { is_expected.to be(false) }
        end
      end

      context 'with another flow' do
        let(:workflow_definition) { 'developer/v1' }

        context 'with a top level group runner' do
          let(:runner) { group_runner }

          it { is_expected.to be(true) }
        end

        context 'with a subgroup runner' do
          let(:runner) { subgroup_runner }

          it { is_expected.to be(false) }
        end
      end
    end

    context 'when the workload link does not exist yet' do
      let(:yaml_variables) { [{ key: 'DUO_WORKFLOW_WORKFLOW_ID', value: workflow.id.to_s, public: true }] }

      context 'with a GitLab-hosted-runner-only flow named by the job definition' do
        context 'with a GitLab-hosted runner' do
          let(:runner) { instance_runner }

          it { is_expected.to be(true) }
        end

        context 'with a top level group runner' do
          let(:runner) { group_runner }

          it { is_expected.to be(false) }
        end
      end

      context 'with another flow named by the job definition' do
        let(:workflow_definition) { 'developer/v1' }
        let(:runner) { group_runner }

        it { is_expected.to be(true) }
      end

      context 'when the job definition names a GitLab-hosted-runner-only workflow in another project' do
        let(:workflow) do
          create(:duo_workflows_workflow, project: create(:project), workflow_definition: workflow_definition)
        end

        let(:runner) { group_runner }

        it { is_expected.to be(true) }
      end

      context 'when the job definition names a workflow that does not exist' do
        let(:yaml_variables) { [{ key: 'DUO_WORKFLOW_WORKFLOW_ID', value: non_existing_record_id.to_s, public: true }] }
        let(:runner) { group_runner }

        it { is_expected.to be(true) }
      end

      context 'when the job cannot be tied to a workflow' do
        let(:yaml_variables) { [] }

        context 'with a GitLab-hosted runner' do
          let(:runner) { instance_runner }

          it { is_expected.to be(true) }
        end

        context 'with a top level group runner' do
          let(:runner) { group_runner }

          it { is_expected.to be(true) }
        end

        context 'with a subgroup runner' do
          let(:runner) { subgroup_runner }

          it { is_expected.to be(false) }
        end
      end
    end
  end
end
