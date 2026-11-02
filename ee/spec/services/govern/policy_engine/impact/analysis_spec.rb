# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::Impact::Analysis, feature_category: :security_policy_management do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:group) { create(:group, organization: organization) }
  let_it_be(:other_group) { create(:group, organization: organization) }

  let_it_be(:project_a) { create(:project, group: group) }
  let_it_be(:project_b) { create(:project, group: group) }
  let_it_be(:project_c) { create(:project, group: other_group) }
  let_it_be(:foreign_project) { create(:project) }

  # The evaluator contract is two methods; this one violates by id so the run
  # can be checked without any project settings.
  let(:violating_ids) { [project_b.id, project_c.id] }
  let(:evaluator) do
    ids = violating_ids
    Class.new do
      define_method(:preloads) { [] }
      define_method(:violates?) { |project| ids.include?(project.id) }
    end.new
  end

  let(:namespace_id) { nil }
  let(:policy_scope) { nil }
  let(:draft) do
    Govern::PolicyEngine::Impact::Draft.build(
      organization_id: organization.id, namespace_id: namespace_id, policy_scope: policy_scope, rules: []
    )
  end

  subject(:result) { described_class.new(draft: draft, evaluator: evaluator).execute }

  it 'checks every project of the organization and lists the violating ones in id order', :aggregate_failures do
    expect(result).to have_attributes(
      projects_in_scope_count: 3, violating_count: 2, compliant_count: 1, complete: true, unavailable_reason: nil
    )
    expect(result.violating_projects).to eq([project_b, project_c])
  end

  context 'with a scope the resolver serves from several arms' do
    # The project arm yields project_c first, then the group arm yields a and b.
    let(:policy_scope) do
      { 'match_mode' => 'any', 'projects' => { 'including' => [{ 'id' => project_c.id }] },
        'groups' => { 'including' => [{ 'id' => group.id }] } }
    end

    let(:violating_ids) { [project_a.id, project_b.id, project_c.id] }

    it 'lists and caps in one id order across the arms', :aggregate_failures do
      expect(result.violating_projects).to eq([project_a, project_b, project_c])

      stub_const("#{described_class}::MAX_PROJECTS", 2)

      expect(described_class.new(draft: draft, evaluator: evaluator).execute)
        .to have_attributes(violating_projects: [project_a, project_b], complete: false)
    end

    context 'when the first arm alone passes the cap' do
      let_it_be(:project_d) { create(:project, group: other_group) }

      let(:policy_scope) do
        { 'match_mode' => 'any',
          'projects' => { 'including' => [{ 'id' => project_c.id }, { 'id' => project_d.id }] },
          'groups' => { 'including' => [{ 'id' => group.id }] } }
      end

      let(:violating_ids) { [project_a.id, project_b.id, project_c.id, project_d.id] }

      before do
        stub_const("#{described_class}::MAX_PROJECTS", 1)
      end

      it 'keeps reading the later arms for smaller ids' do
        expect(result).to have_attributes(violating_projects: [project_a], complete: false)
      end
    end
  end

  it 'asks the evaluator about each candidate once' do
    expect(evaluator).to receive(:violates?).exactly(3).times.and_call_original

    result
  end

  it 'writes nothing' do
    expect { result }.not_to change { Govern::PolicyEvaluation.count }
  end

  context 'with a group draft' do
    let(:namespace_id) { group.id }

    it 'stays inside the subtree of the group', :aggregate_failures do
      expect(result).to have_attributes(projects_in_scope_count: 2, violating_count: 1, complete: true)
      expect(result.violating_projects).to eq([project_b])
    end
  end

  context 'with a scope naming specific projects' do
    let(:policy_scope) { { 'projects' => { 'including' => [{ 'id' => project_a.id }] } } }

    it 'checks only those' do
      expect(result).to have_attributes(projects_in_scope_count: 1, violating_count: 0, compliant_count: 1)
    end
  end

  context 'with more projects than the cap' do
    before do
      stub_const("#{described_class}::MAX_PROJECTS", 2)
    end

    it 'stops at the cap and reports the run as incomplete', :aggregate_failures do
      expect(result).to have_attributes(projects_in_scope_count: 2, complete: false)
      expect(result.violating_projects.size).to be <= 2
    end

    context 'when the ids arrive in several batches of one arm' do
      let_it_be(:project_d) { create(:project, group: other_group) }

      before do
        stub_const("#{described_class}::ID_BATCH_SIZE", 1)
      end

      it 'stops reading once the smallest ids past the cap are known', :aggregate_failures do
        yielded = 0
        allow_next_instance_of(Govern::PolicyEngine::ScopedProjectsResolver) do |resolver|
          allow(resolver).to receive(:each_candidate_batch).and_wrap_original do |original, **options, &block|
            original.call(**options) do |batch|
              yielded += 1
              block.call(batch)
            end
          end
        end

        expect(result).to have_attributes(projects_in_scope_count: 2, violating_count: 1, complete: false)
        expect(result.violating_projects).to eq([project_b])
        expect(yielded).to eq(3)
      end
    end
  end

  context 'when the ids of one arm span several batches' do
    before do
      stub_const("#{described_class}::ID_BATCH_SIZE", 2)
    end

    it 'collects them all', :aggregate_failures do
      expect(result).to have_attributes(projects_in_scope_count: 3, violating_count: 2, complete: true)
      expect(result.violating_projects).to match_array([project_b, project_c])
    end
  end

  context 'with exactly as many projects as the cap' do
    before do
      stub_const("#{described_class}::MAX_PROJECTS", 3)
    end

    it 'reports the run as complete' do
      expect(result).to have_attributes(projects_in_scope_count: 3, complete: true)
    end
  end

  context 'when the time budget runs out while evaluating' do
    before do
      # Deadline, one id batch, then one project checked before the clock passes it.
      allow_next_instance_of(described_class) do |analysis|
        allow(analysis).to receive(:monotonic_time).and_return(0, 0, 0, described_class::TIME_BUDGET.to_i + 1)
      end
    end

    it 'stops after the projects checked so far and reports the run as incomplete' do
      expect(result).to have_attributes(projects_in_scope_count: 1, complete: false)
    end
  end

  context 'when the time budget runs out before any id is read' do
    before do
      allow_next_instance_of(described_class) do |analysis|
        allow(analysis).to receive(:monotonic_time).and_return(0, described_class::TIME_BUDGET.to_i + 1, 0, 0, 0, 0)
      end
    end

    it 'evaluates nothing and reports the run as incomplete' do
      expect(result).to have_attributes(projects_in_scope_count: 0, complete: false)
    end
  end

  context 'when the id pass uses up its share of the budget' do
    let(:half_spent) { described_class::ID_PASS_BUDGET.to_i + 1 }

    before do
      stub_const("#{described_class}::ID_BATCH_SIZE", 1)
      # Start, first batch in time, second batch past the id pass share, then the
      # evaluation clock still inside the overall budget.
      allow_next_instance_of(described_class) do |analysis|
        allow(analysis).to receive(:monotonic_time).and_return(0, 0, half_spent, half_spent)
      end
    end

    it 'still evaluates the ids collected so far and reports the run as incomplete' do
      expect(result).to have_attributes(projects_in_scope_count: 1, complete: false)
    end
  end

  context 'with more violating projects than the list holds' do
    before do
      stub_const("#{described_class}::MAX_LISTED_PROJECTS", 1)
    end

    it 'counts every violation but lists the first ones', :aggregate_failures do
      expect(result.violating_count).to eq(2)
      expect(result.violating_projects).to eq([project_b])
    end
  end

  it 'preloads what the evaluator asks for, plus the route of the listed projects' do
    allow(evaluator).to receive(:preloads).and_return([:project_setting])

    expect(result.violating_projects).to all(satisfy { |project| project.association(:route).loaded? })
      .and all(satisfy { |project| project.association(:project_setting).loaded? })
  end
end
