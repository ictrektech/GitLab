# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WorkItems::Widgets::AgentPlan, feature_category: :team_planning do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:work_item) { create(:work_item) }
  let_it_be(:agent_plan) do
    create(
      :work_item_agent_plan,
      work_item: work_item,
      content: '**plan**',
      readiness_score_feedback: '**needs acceptance criteria**'
    )
  end

  describe '.type' do
    subject { described_class.type }

    it { is_expected.to eq(:agent_plan) }
  end

  describe '.required_user_ability' do
    it { expect(described_class.required_user_ability).to eq(:update_work_item) }
  end

  describe '.api_symbol' do
    subject { described_class.api_symbol }

    it { is_expected.to eq(:agent_plan_widget) }
  end

  describe '#content' do
    subject { described_class.new(work_item).content }

    it { is_expected.to eq('**plan**') }

    context 'when agent plan does not exist' do
      let_it_be(:work_item_without_plan) { create(:work_item) }

      subject { described_class.new(work_item_without_plan).content }

      it { is_expected.to be_nil }
    end
  end

  describe '#content_html' do
    subject { described_class.new(work_item).content_html }

    it { is_expected.to be_present }

    context 'when agent plan does not exist' do
      let_it_be(:work_item_without_plan) { create(:work_item) }

      subject { described_class.new(work_item_without_plan).content_html }

      it { is_expected.to be_nil }
    end
  end

  describe '#readiness_score_feedback' do
    subject { described_class.new(work_item).readiness_score_feedback }

    it { is_expected.to eq('**needs acceptance criteria**') }

    context 'when agent plan does not exist' do
      let_it_be(:work_item_without_plan) { create(:work_item) }

      subject { described_class.new(work_item_without_plan).readiness_score_feedback }

      it { is_expected.to be_nil }
    end
  end

  describe '#readiness_score_feedback_html' do
    subject { described_class.new(work_item).readiness_score_feedback_html }

    it { is_expected.to be_present }

    context 'when agent plan does not exist' do
      let_it_be(:work_item_without_plan) { create(:work_item) }

      subject { described_class.new(work_item_without_plan).readiness_score_feedback_html }

      it { is_expected.to be_nil }
    end
  end

  describe '#ai_planning_enabled_for_widget' do
    subject { described_class.new(work_item).ai_planning_enabled_for_widget }

    it { is_expected.to be(false) }

    context 'when AI planning is enabled' do
      let_it_be(:planned_work_item) { create(:work_item) }

      before_all do
        create(:work_item_agent_plan, work_item: planned_work_item, ai_planning_enabled: true)
      end

      subject { described_class.new(planned_work_item).ai_planning_enabled_for_widget }

      it { is_expected.to be(true) }
    end

    context 'when agent plan does not exist' do
      let_it_be(:work_item_without_plan) { create(:work_item) }

      subject { described_class.new(work_item_without_plan).ai_planning_enabled_for_widget }

      it { is_expected.to be(false) }
    end
  end

  describe '#has_content_for_widget?' do
    subject { described_class.new(work_item).has_content_for_widget? }

    it { is_expected.to be(true) }

    context 'when the plan has no content' do
      let_it_be(:planned_work_item) { create(:work_item) }

      before_all do
        create(:work_item_agent_plan, work_item: planned_work_item, ai_planning_enabled: true, content: nil)
      end

      subject { described_class.new(planned_work_item).has_content_for_widget? }

      it { is_expected.to be(false) }
    end

    context 'when agent plan does not exist' do
      let_it_be(:work_item_without_plan) { create(:work_item) }

      subject { described_class.new(work_item_without_plan).has_content_for_widget? }

      it { is_expected.to be(false) }
    end
  end

  describe '.generation_statuses_for' do
    let_it_be(:project) { create(:project) }
    let_it_be(:requester) { create(:user, developer_of: project) }
    let_it_be(:target_work_item) { create(:work_item, project: project) }

    subject(:generation_status) do
      described_class.generation_statuses_for([target_work_item.id])[target_work_item.id]
    end

    def create_workplan_workflow(*traits)
      create(:duo_workflows_workflow, *traits, project: project, user: requester,
        issue_id: target_work_item.id, workflow_definition: 'workplan/v1')
    end

    context 'when no workplan/v1 workflow has ever run for the work item' do
      it { is_expected.to eq(:not_started) }
    end

    context 'when the only workflow for the work item belongs to another flow' do
      before do
        create(:duo_workflows_workflow, :finished, project: project, user: requester,
          issue_id: target_work_item.id, workflow_definition: 'software_development')
      end

      it { is_expected.to eq(:not_started) }
    end

    context 'when a workplan/v1 workflow exists for the work item' do
      where(:workflow_status, :expected_status) do
        :running                     | :generating
        :input_required              | :needs_input
        :plan_approval_required      | :needs_input
        :tool_call_approval_required | :needs_input
        :finished                    | :completed
        :failed                      | :failed
        # Canceled by a user, so it is reported apart from a failed generation.
        :stopped                     | :canceled
      end

      with_them do
        before do
          create_workplan_workflow(workflow_status)
        end

        it { is_expected.to eq(expected_status) }
      end
    end

    context 'when an older workflow finished but a newer one is still running' do
      before do
        create_workplan_workflow(:finished)
        create_workplan_workflow(:running)
      end

      it 'reflects the most recent workflow' do
        expect(generation_status).to eq(:generating)
      end
    end

    it 'returns a status for every requested work item in a single query', :aggregate_failures do
      other_work_item = create(:work_item, project: project)
      create_workplan_workflow(:finished)

      statuses = nil
      expect { statuses = described_class.generation_statuses_for([target_work_item.id, other_work_item.id]) }
        .not_to exceed_query_limit(1)

      expect(statuses).to eq(target_work_item.id => :completed, other_work_item.id => :not_started)
    end
  end

  describe '#workplan_questions' do
    let_it_be(:project) { create(:project) }
    let_it_be(:work_item) { create(:work_item, project: project) }
    let_it_be(:developer) { create(:user, developer_of: project) }
    let_it_be(:other_user) { create(:user, developer_of: project) }

    let(:widget) { described_class.new(work_item) }

    it 'builds a WorkplanQuestions for the work item and user' do
      expect(::Ai::DuoWorkflows::WorkplanQuestions).to receive(:new).with(work_item, developer).and_call_original

      expect(widget.workplan_questions(developer)).to be_a(::Ai::DuoWorkflows::WorkplanQuestions)
    end

    it 'memoizes the result per user', :aggregate_failures do
      expect(widget.workplan_questions(developer)).to equal(widget.workplan_questions(developer))
      expect(widget.workplan_questions(developer)).not_to equal(widget.workplan_questions(other_user))
    end
  end
end
