# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'querying duoWorkflowRunnerAvailable on a group', feature_category: :duo_agent_platform do
  include GraphqlHelpers

  let_it_be(:group) do
    create(:group) { |g| g.namespace_settings.update!(duo_features_enabled: true) }
  end

  let_it_be(:current_user) { create(:user, developer_of: group) }

  let(:workload_tag) { ::Ai::DuoWorkflows::Workflow.workload_tag_for(group) }

  def query_group(fields, user: current_user)
    result = GitlabSchema.execute(%(
      query {
        group(fullPath: "#{group.full_path}") {
          #{fields}
        }
      }
    ), context: { current_user: user }).as_json

    result.dig('data', 'group')
  end

  def query_field(user: current_user)
    query_group('duoWorkflowRunnerAvailable', user: user)&.fetch('duoWorkflowRunnerAvailable')
  end

  before do
    # Stub the entitlement seams so the real :duo_workflow policy grant is exercised.
    allow(::Gitlab::Llm::StageCheck).to receive(:available?).with(group, :duo_workflow).and_return(true)
    allow(::Ai::DuoWorkflow).to receive(:duo_agent_platform_available?).with(group).and_return(true)
    allow(current_user).to receive(:allowed_to_use?).and_return(true)
  end

  it 'is false when the group has no runner that could pick up the workload' do
    expect(query_field).to be(false)
  end

  it 'is true once a usable runner exists' do
    runner = create(:ci_runner, :instance, :online, tag_list: [workload_tag])
    create(:ci_runner_machine, runner: runner, executor_type: :docker)

    expect(query_field).to be(true)
  end

  describe 'duoWorkflowUsableRunnerType' do
    it 'is the type of the runner that satisfied the check' do
      runner = create(:ci_runner, :group, :online, groups: [group], tag_list: [workload_tag])
      create(:ci_runner_machine, runner: runner, executor_type: :docker)

      expect(query_group('duoWorkflowRunnerAvailable duoWorkflowUsableRunnerType')).to eq(
        'duoWorkflowRunnerAvailable' => true,
        'duoWorkflowUsableRunnerType' => 'group_type'
      )
    end

    it 'is nil when no runner qualifies' do
      expect(query_group('duoWorkflowUsableRunnerType')['duoWorkflowUsableRunnerType']).to be_nil
    end

    it 'runs the runner scan once when both fields are requested' do
      expect(::Ai::DuoWorkflow::GroupReadiness).to receive(:new).once.and_call_original

      query_group('duoWorkflowRunnerAvailable duoWorkflowUsableRunnerType')
    end
  end

  # Runner topology is not public information.
  it 'is nil for a user who cannot use Duo Agent Platform here' do
    outsider = create(:user, guest_of: group)

    expect(query_field(user: outsider)).to be_nil
  end

  it 'is not resolved unless it is requested' do
    expect(::Ai::DuoWorkflow::GroupReadiness).not_to receive(:new)

    GitlabSchema.execute(%(
      query { group(fullPath: "#{group.full_path}") { id } }
    ), context: { current_user: current_user })
  end

  it 'can be requested for at most 10 groups in one query', :aggregate_failures do
    query_for = ->(count) do
      aliases = Array.new(count) { |i| %(g#{i}: group(fullPath: "#{group.full_path}") { duoWorkflowRunnerAvailable }) }
      GitlabSchema.execute("query { #{aliases.join("\n")} }", context: { current_user: current_user }).as_json
    end

    expect(query_for.call(10)['errors']).to be_nil
    expect(query_for.call(11)['errors'].pluck('message'))
      .to include('"duoWorkflowRunnerAvailable" field can be requested only for 10 Group(s) at a time.')
  end
end
