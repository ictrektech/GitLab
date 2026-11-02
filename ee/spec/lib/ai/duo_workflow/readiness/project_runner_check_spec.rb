# frozen_string_literal: true

require 'spec_helper'

# Runner filtering and validation are covered by runner_check_spec.rb.
RSpec.describe Ai::DuoWorkflow::Readiness::ProjectRunnerCheck, feature_category: :duo_agent_platform do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, namespace: group) }

  let(:check) { described_class.new(project) }

  def create_duo_runner(*traits, **runner_args)
    create(:ci_runner, :online, *traits,
      tag_list: [::Ai::DuoWorkflows::Workflow.workload_tag_for(project)], **runner_args).tap do |runner|
      create(:ci_runner_machine, runner: runner, executor_type: :docker)
    end
  end

  it 'reports a usable runner available to the project' do
    create_duo_runner(:group, groups: [group])

    expect(check.runner_available?).to be(true)
    expect(check.usable_runner_type).to eq('group_type')
  end

  it 'ignores runners not available to the project' do
    create_duo_runner(:group, groups: [create(:group)])

    expect(check.runner_available?).to be(false)
    expect(check.usable_runner_type).to be_nil
  end

  it 'validates candidates against the project' do
    create_duo_runner(:instance)

    expect(::Ai::DuoWorkflow::RunnerValidator)
      .to receive(:new).with(instance_of(Ci::Runner), project).and_call_original

    expect(check.runner_available?).to be(true)
  end

  it 'does not load the project runners that RunnerValidator rejects anyway' do
    create_duo_runner(:project, projects: [project])

    recorder = ActiveRecord::QueryRecorder.new { check.runner_available? }

    expect(recorder.log.grep(/ci_runner_projects/)).to be_empty
  end

  it 'stops scanning after the candidate window' do
    stub_const("#{described_class}::RUNNER_CANDIDATE_LIMIT", 1)

    create_duo_runner(:instance)
    newer = create(:ci_runner, :instance, :online, tag_list: [::Ai::DuoWorkflows::Workflow.workload_tag_for(project)])
    create(:ci_runner_machine, runner: newer, executor_type: :shell)

    expect(check.runner_available?).to be(false)
  end
end
