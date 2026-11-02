# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Seeders::WorkItems::Workplans, feature_category: :duo_agent_platform do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, maintainer_of: project) }

  let(:reset) { false }

  subject(:seeder) { described_class.new(project: project, user: user, reset: reset) }

  def seeded(key)
    scenario = described_class::SCENARIOS.find { |s| s[:key] == key }
    project.work_items.find_by!(title: "#{described_class::TITLE_PREFIX} #{key} #{scenario[:name]}")
  end

  # Seeds a single scenario, for examples that don't need all of them.
  def only_scenario(key)
    stub_const("#{described_class}::SCENARIOS", described_class::SCENARIOS.select { |s| s[:key] == key })
  end

  def generation_status(work_item)
    WorkItems::Widgets::AgentPlan.generation_statuses_for([work_item.id])[work_item.id]
  end

  describe '#seed!' do
    it 'creates one work item per scenario', :aggregate_failures do
      results = seeder.seed!

      expect(results.size).to eq(described_class::SCENARIOS.size)
      expect(results).to all(include(created: true))
    end

    it 'enables the workplan feature flags' do
      described_class::FEATURE_FLAGS.each { |flag| expect(Feature).to receive(:enable).with(flag) }

      seeder.seed!
    end

    context 'with the scenarios seeded once' do
      # These examples only read, so they share one seed run.
      before_all do
        described_class.new(project: project, user: user).seed!
      end

      it 'gives each scenario its readiness score' do
        scores = described_class::SCENARIOS.to_h do |scenario|
          [scenario[:key], seeded(scenario[:key]).agent_plan&.readiness_score]
        end

        expect(scores).to eq(
          '01' => nil, '02' => nil, '03' => 25, '04' => 60, '05' => 85, '06' => 55, '07' => 90, '08' => nil,
          '09' => nil, '10' => 60
        )
      end

      it 'enables AI planning on every work item, including those without a plan', :aggregate_failures do
        expect(described_class::SCENARIOS.map { |s| seeded(s[:key]).agent_plan.ai_planning_enabled }).to all(be(true))
        expect(%w[01 08 09].map { |key| seeded(key).agent_plan.content }).to all(be_nil)
      end

      it 'gives every scored work item a workplan' do
        scored = described_class::SCENARIOS.select { |s| s[:score] }.map { |s| seeded(s[:key]).agent_plan }

        expect(scored.map(&:content)).to all(be_present)
      end

      it 'seeds Duo questions that the workplan widget reads' do
        counts = %w[03 04 05 06 07].to_h do |key|
          questions = Ai::DuoWorkflows::WorkplanQuestions.new(seeded(key), user)

          [key, [questions.questions.size, questions.open_count]]
        end

        expect(counts).to eq('03' => [0, 0], '04' => [2, 0], '05' => [2, 0], '06' => [4, 3], '07' => [4, 0])
      end

      it 'writes question payloads that parse', :aggregate_failures do
        notes = Note.created_by_duo_workflows(seeded('06').duo_workflows).order(:id)

        expect(notes.map { |note| Gitlab::WorkItems::DuoQuestion.parse(note.note) }).to all(be_present)
        expect(notes.first.note).to start_with("@#{user.username} ")
      end

      it 'answers questions in the format the question card writes' do
        answers = seeded('07').notes.where.not(id: Note.created_by_duo_workflows(seeded('07').duo_workflows))
          .user.order(:id).pluck(:note)

        expect(answers).to eq([
          "Last 90 days\n\n<!-- duo-answer: last_90_days -->",
          "Include them, but as a separate series\n\n<!-- duo-answer: rejected -->",
          "- Median\n- 95th percentile\n\n<!-- duo-answer: median,p95 -->",
          "Exclude them\n\n<!-- duo-answer: exclude_failed -->"
        ])
      end

      context 'without a workplan service account' do
        it 'posts questions as the user and records no decisions', :aggregate_failures do
          expect(Note.created_by_duo_workflows(seeded('06').duo_workflows).map(&:author)).to all(eq(user))
          expect(WorkItems::Decision.where(work_item: project.issues)).to be_empty
        end
      end

      it 'reports the latest generation run', :aggregate_failures do
        expect(generation_status(seeded('01'))).to eq(:not_started)
        expect(generation_status(seeded('03'))).to eq(:not_started)
        expect(generation_status(seeded('04'))).to eq(:completed)
        expect(generation_status(seeded('05'))).to eq(:completed)
        expect(generation_status(seeded('06'))).to eq(:needs_input)
        expect(generation_status(seeded('07'))).to eq(:completed)
        expect(generation_status(seeded('08'))).to eq(:generating)
        expect(generation_status(seeded('09'))).to eq(:failed)
        expect(generation_status(seeded('10'))).to eq(:failed)
        expect(seeded('10').agent_plan.content).to be_present
      end
    end

    context 'with a workplan service account' do
      let_it_be(:item) { create(:ai_catalog_flow, :public, foundational_flow_reference: 'workplan/v1') }
      let_it_be(:service_account) { create(:user, :service_account, developer_of: project) }

      before do
        stub_licensed_features(ai_workflows: true)
        allow_next_instance_of(Ai::Catalog::ItemConsumers::ResolveServiceAccountService) do |service|
          allow(service).to receive(:execute)
            .and_return(ServiceResponse.success(payload: { service_account: service_account }))
        end
      end

      it 'posts questions as the service account', :aggregate_failures do
        seeder.seed!

        expect(Note.created_by_duo_workflows(seeded('06').duo_workflows).map(&:author)).to all(eq(service_account))
        expect(seeded('06').duo_workflows.map(&:service_account)).to all(eq(service_account))
      end

      it 'records a decision per question and resolves the answered ones', :aggregate_failures do
        seeder.seed!

        decisions = seeded('07').decisions.includes(:options).order(:id)

        expect(decisions.size).to eq(4)
        expect(decisions).to all(have_attributes(resolved_at: be_present))
        expect(decisions.map { |d| d.options.select(&:selected).map(&:content) }).to eq([
          ['Last 90 days'], ['Include them, but as a separate series'], ['Median', '95th percentile'],
          ['Exclude them']
        ])
        expect(seeded('06').decisions.where(resolved_at: nil).count).to eq(3)
      end

      it 'resets items whose decisions reference a workflow', :aggregate_failures do
        seeder.seed!
        old_decision_ids = WorkItems::Decision.where.not(workflow_id: nil).pluck(:id)

        expect(old_decision_ids).to be_present
        expect { described_class.new(project: project, user: user, reset: true).seed! }.not_to raise_error

        expect(WorkItems::Decision.where(id: old_decision_ids)).to be_empty
      end

      it 'raises and removes the work item when a decision cannot be resolved', :aggregate_failures do
        only_scenario('06')
        allow_next_instance_of(WorkItems::Decisions::ResolveService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'resolve failed'))
        end

        expect { seeder.seed! }.to raise_error(/Failed to resolve decision: resolve failed/)
        expect(project.work_items).to be_empty
      end
    end

    context 'when the workplan flow is not enabled for the project' do
      let_it_be(:item) { create(:ai_catalog_flow, :public, foundational_flow_reference: 'workplan/v1') }
      let_it_be(:username) { "duo-#{item.name}-#{project.root_ancestor.name}".parameterize }

      before do
        only_scenario('06')
        stub_licensed_features(ai_workflows: true)
        allow_next_instance_of(Ai::Catalog::ItemConsumers::ResolveServiceAccountService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'not enabled'))
        end
      end

      # The factory treats skip_ai_prefix_validation as transient, so set it on the model.
      def create_with_reserved_username(*traits)
        build(:user, *traits, username: username).tap do |user|
          user.skip_ai_prefix_validation = true
          user.save!
        end
      end

      it 'posts questions as a service account left over from when it was enabled' do
        leftover = create_with_reserved_username(:service_account).tap { |account| project.add_developer(account) }

        seeder.seed!

        expect(Note.created_by_duo_workflows(seeded('06').duo_workflows).map(&:author)).to all(eq(leftover))
      end

      it 'posts questions as the user when no account has that username' do
        seeder.seed!

        expect(Note.created_by_duo_workflows(seeded('06').duo_workflows).map(&:author)).to all(eq(user))
      end

      it 'posts questions as the user when the username belongs to a regular user' do
        create_with_reserved_username

        seeder.seed!

        expect(Note.created_by_duo_workflows(seeded('06').duo_workflows).map(&:author)).to all(eq(user))
      end
    end

    context 'when seeding fails' do
      before do
        only_scenario('06')
      end

      it 'raises when the work item cannot be created' do
        allow_next_instance_of(WorkItems::CreateService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'create failed'))
        end

        expect { seeder.seed! }.to raise_error(/Failed to create .*: create failed/)
      end

      it 'raises and removes the work item when a question cannot be linked', :aggregate_failures do
        errors = ActiveModel::Errors.new(Note.new).tap { |e| e.add(:base, 'link failed') }
        allow(Ai::DuoWorkflows::WorkflowNote).to receive(:ensure_link).and_return(errors)

        expect { seeder.seed! }.to raise_error(/Failed to link question note: link failed/)
        expect(project.work_items).to be_empty
      end

      it 'raises and removes the work item when a decision cannot be created', :aggregate_failures do
        allow_next_instance_of(WorkItems::Decisions::CreateFromDuoQuestionService) do |service|
          allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'decision failed'))
        end

        expect { seeder.seed! }.to raise_error(/Failed to create decision: decision failed/)
        expect(project.work_items).to be_empty
      end
    end

    context 'when the work items were already seeded' do
      before do
        described_class.new(project: project, user: user).seed!
      end

      it 'keeps them' do
        expect { seeder.seed! }.not_to change { project.issues.count }
        expect(seeder.seed!).to all(include(created: false))
      end

      context 'with reset' do
        let(:reset) { true }

        it 'recreates them' do
          old_ids = project.issues.pluck(:id)

          seeder.seed!

          expect(project.issues.pluck(:id)).not_to include(*old_ids)
          expect(project.issues.count).to eq(described_class::SCENARIOS.size)
        end

        it 'removes items from renumbered scenarios but keeps other work items', :aggregate_failures do
          renumbered = create(:work_item, project: project, title: "#{described_class::TITLE_PREFIX} 99 Old")
          unrelated = create(:work_item, project: project, title: 'Unrelated')

          seeder.seed!

          expect(Issue.exists?(renumbered.id)).to be(false)
          expect(Issue.exists?(unrelated.id)).to be(true)
        end
      end
    end
  end
end
