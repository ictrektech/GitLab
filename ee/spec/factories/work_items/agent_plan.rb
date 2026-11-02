# frozen_string_literal: true

FactoryBot.define do
  factory :work_item_agent_plan, class: 'WorkItems::AgentPlan' do
    work_item { association(:work_item) }
    namespace { work_item&.namespace }
    content { 'Sample agent plan content' }
    ai_planning_enabled { false }
  end
end
