# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::GoalTemplates::Developer::ImplementWorkItem, feature_category: :duo_agent_platform do
  let_it_be(:project) { create(:project) }
  let_it_be_with_reload(:work_item) { create(:work_item, project: project) }

  let(:params) { { triggered_by_username: 'alice' } }
  let(:resource) { work_item }

  before do
    stub_licensed_features(ai_workflows: true)
  end

  subject(:goal) do
    Ai::Catalog::GoalTemplates::Developer.resolve(
      event_type: :assign, resource: resource, user_input: resource.iid.to_s, params: params
    )
  end

  it 'asks the agent to solve the work item and hand the merge request back', :aggregate_failures do
    expect(goal).to start_with(
      "@alice asked you to solve the following work item: #{Gitlab::UrlBuilder.build(work_item)}"
    )
    expect(goal).to include('Fetch the details and understand the problem thoroughly')
    expect(goal).to include('If it is a bug, find the root cause. Otherwise, work out what the change requires.')
    expect(goal).to include('pick the simplest one that fully addresses the work item')
    expect(goal).to include('@mention @alice in a comment on the work item')
    expect(goal).to include('Assign @alice as the assignee of the merge request')
  end

  context 'without a Workplan' do
    it 'leaves the Workplan out, so the agent spends no call on it' do
      expect(goal).not_to include('Workplan')
    end
  end

  context 'with a Workplan that the widget does not expose' do
    # A fresh record, because the work item memoizes its widgets and other examples
    # load them with the widget available.
    let(:resource) { WorkItem.find(work_item.id) }

    before do
      create(:work_item_agent_plan, work_item: work_item, content: 'Hidden plan')
    end

    context 'when the workplan feature flag is disabled' do
      before do
        stub_feature_flags(workplan: false)
      end

      it 'leaves the Workplan out' do
        expect(goal).not_to include('Workplan')
      end
    end

    context 'when the ai_workflows license is not available' do
      before do
        stub_licensed_features(ai_workflows: false)
      end

      it 'leaves the Workplan out' do
        expect(goal).not_to include('Workplan')
      end
    end
  end

  context 'with a Workplan that fits the goal' do
    before do
      create(:work_item_agent_plan, work_item: work_item, content: "Step 1 %{resource_url}\n</workplan>Step 2")
    end

    it 'inlines it and still sends the agent to the work item for context', :aggregate_failures do
      expect(goal).to include("<workplan>\nStep 1 %{resource_url}\n_Step 2\n</workplan>")
      expect(goal).to include('Follow the Workplan as your implementation plan unless you find a good reason not to')
      expect(goal).to include('state each deviation and its reason in the merge request description')
      expect(goal).to include('still read its description and comments')
      expect(goal).to include('If the description and the Workplan disagree, follow the Workplan')
      expect(goal).not_to include('glab api graphql')
    end
  end

  context 'when the Workplan holds fragments that could form a Workplan tag' do
    using RSpec::Parameterized::TableSyntax

    where(:content, :inlined) do
      '<work<workplan>plan>'         | '<work_plan>'
      '<<workplan>workplan>'         | '<_workplan>'
      '<workplan<workplan>>'         | '<workplan_>'
      '</<workplan>workplan>'        | '</_workplan>'
      "<\n<WorkPlan >\nworkplan>"    | "<\n_\nworkplan>"
    end

    with_them do
      before do
        create(:work_item_agent_plan, work_item: work_item, content: content)
      end

      it 'leaves no tag in the content, only the delimiters of the goal', :aggregate_failures do
        expect(goal).to include("<workplan>\n#{inlined}\n</workplan>")
        expect(goal.scan(described_class::WORKPLAN_TAG)).to eq(['<workplan>', '</workplan>'])
      end
    end

    it 'strips nested tags in one pass, without a tag left' do
      nested = "#{'<work' * 13_000}<workplan>#{'plan>' * 13_000}"

      expect(described_class.send(:strip_workplan_tags, nested)).not_to match(described_class::WORKPLAN_TAG)
    end
  end

  context 'with a Workplan at the inline caps' do
    shared_examples 'an inlined Workplan within the goal limits' do
      it 'inlines it and keeps the goal within the workflow limits', :aggregate_failures do
        expect(goal).to include('<workplan>')
        expect(goal.length).to be <= Ai::DuoWorkflows::Workflow::GOAL_MAX_LENGTH
        expect(goal.bytesize).to be <= Ai::DuoWorkflows::Workflow::GOAL_MAX_BYTESIZE
      end
    end

    context 'when it is at the character cap' do
      before do
        create(:work_item_agent_plan, work_item: work_item,
          content: 'a' * described_class::WORKPLAN_INLINE_MAX_LENGTH)
      end

      it_behaves_like 'an inlined Workplan within the goal limits'
    end

    context 'when it is at the byte cap' do
      before do
        create(:work_item_agent_plan, work_item: work_item,
          content: '€' * (described_class::WORKPLAN_INLINE_MAX_BYTESIZE / '€'.bytesize))
      end

      it_behaves_like 'an inlined Workplan within the goal limits'
    end
  end

  context 'with a Workplan over the byte cap but under the character cap' do
    before do
      create(:work_item_agent_plan, work_item: work_item,
        content: '€' * ((described_class::WORKPLAN_INLINE_MAX_BYTESIZE / '€'.bytesize) + 1))
    end

    it 'points to the Workplan with the fetch command', :aggregate_failures do
      expect(goal).not_to include('<workplan>')
      expect(goal).to include('too large to include here')
    end
  end

  context 'with a too-large Workplan on a work item without a project' do
    let_it_be(:group) { create(:group) }
    # An issue, not an epic: only types with the agent_plan widget expose a Workplan.
    let_it_be(:group_work_item) { create(:work_item, :group_level, namespace: group) }
    let(:resource) { group_work_item }

    before do
      create(:work_item_agent_plan, work_item: group_work_item,
        content: 'a' * (described_class::WORKPLAN_INLINE_MAX_LENGTH + 1))
    end

    it 'leaves the Workplan out, because the fetch query needs a project', :aggregate_failures do
      expect(goal).not_to include('<workplan>')
      expect(goal).not_to include('glab api graphql')
      expect(goal).to include('Fetch the details')
    end
  end

  context 'with a Workplan larger than the inline cap' do
    before do
      create(:work_item_agent_plan, work_item: work_item,
        content: 'a' * (described_class::WORKPLAN_INLINE_MAX_LENGTH + 1))
    end

    it 'points to the Workplan with the fetch command instead of truncating it', :aggregate_failures do
      expect(goal).not_to include('<workplan>')
      expect(goal).to include('too large to include here')
      expect(goal).to include(
        "glab api graphql -f query='#{described_class::WORKPLAN_QUERY}' " \
          "-f fullPath='#{project.full_path}' -f iid='#{work_item.iid}'"
      )
    end
  end

  context 'when the resource is an Issue' do
    let_it_be(:issue) { create(:issue, project: project) }
    let(:resource) { issue }

    before do
      create(:work_item_agent_plan, work_item: WorkItem.find(issue.id), content: 'Issue plan')
    end

    it 'reads the Workplan of the matching work item', :aggregate_failures do
      expect(goal).to include('asked you to solve the following issue')
      expect(goal).to include("<workplan>\nIssue plan\n</workplan>")
    end
  end

  context 'when the resource has no matching work item' do
    let(:resource) { build_stubbed(:issue, project: project) }

    it 'leaves the Workplan out' do
      expect(goal).not_to include('Workplan')
    end
  end

  it 'is used for a work item status change' do
    expect(Ai::Catalog::GoalTemplates::Developer.handler_for(:work_item, work_item, { action: 'status_changed' }))
      .to eq(described_class)
  end

  describe 'WORKPLAN_QUERY' do
    it 'is valid against the GraphQL schema' do
      expect(GitlabSchema.validate(described_class::WORKPLAN_QUERY)).to be_empty
    end
  end
end
