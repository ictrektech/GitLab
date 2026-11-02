# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflow::Readiness::RunnerCheck, feature_category: :duo_agent_platform do
  let_it_be(:project) { create(:project) }

  let(:check_class) do
    Class.new do
      include ::Ai::DuoWorkflow::Readiness::RunnerCheck

      def initialize(container, runner_scope)
        @container = container
        @runner_scope = runner_scope
      end

      private

      attr_reader :container, :runner_scope
    end
  end

  let(:runner_scope) { Ci::Runner.instance_type }
  let(:check) { check_class.new(project, runner_scope) }

  def create_duo_runner(*traits, **runner_args)
    create(:ci_runner, :online, *traits,
      tag_list: [::Ai::DuoWorkflows::Workflow.workload_tag_for(project)], **runner_args).tap do |runner|
      create(:ci_runner_machine, runner: runner, executor_type: :docker)
    end
  end

  it 'reports a usable runner from the scope the including class hands it' do
    runner = create_duo_runner(:instance)

    expect(check.runner_available?).to be(true)
    expect(check.usable_runner_type).to eq(runner.runner_type)
  end

  it 'does not look beyond that scope' do
    create_duo_runner(:group, groups: [create(:group)])

    expect(check.runner_available?).to be(false)
    expect(check.usable_runner_type).to be_nil
  end

  it 'validates candidates against the container it was handed' do
    create_duo_runner(:instance)

    expect(::Ai::DuoWorkflow::RunnerValidator)
      .to receive(:new).with(instance_of(Ci::Runner), project).and_call_original

    check.runner_available?
  end

  it 'queries the scope once, however many readers ask' do
    create_duo_runner(:instance)

    expect(runner_scope).to receive(:active).once.and_call_original

    check.runner_available?
    check.usable_runner_type
  end

  describe 'the candidate window' do
    let(:workload_tag) { ::Ai::DuoWorkflows::Workflow.workload_tag_for(project) }

    before do
      stub_const('Ai::DuoWorkflow::Readiness::RunnerCheck::RUNNER_CANDIDATE_LIMIT', 1)
    end

    it 'misses a usable runner older than everything in the window' do
      create_duo_runner(:instance)
      newer = create(:ci_runner, :instance, :online, tag_list: [workload_tag])
      create(:ci_runner_machine, runner: newer, executor_type: :shell)

      expect(check.runner_available?).to be(false)
    end

    it 'finds the usable runner inside the window' do
      older = create(:ci_runner, :instance, :online, tag_list: [workload_tag])
      create(:ci_runner_machine, runner: older, executor_type: :shell)
      create_duo_runner(:instance)

      expect(check.runner_available?).to be(true)
    end
  end
end
