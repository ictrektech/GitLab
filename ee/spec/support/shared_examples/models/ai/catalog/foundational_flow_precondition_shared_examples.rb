# frozen_string_literal: true

# Evaluates the flow's precondition through the same FilterEvaluator a trigger uses, so a typo in the
# field, operator, or value fails the spec. Requires `flow` to be defined.
RSpec.shared_examples 'a foundational flow precondition' do |hook_scope:, field:, allowed:, denied:|
  let(:flow_trigger) { build_stubbed(:ai_flow_trigger) }

  before do
    allow(flow_trigger).to receive(:foundational_flow).and_return(flow)
  end

  def precondition_allows?(hook_scope, field, value)
    data = field.split('.').reverse.reduce(value) { |nested, key| { key => nested } }

    ::Ai::FlowTriggers::FilterEvaluator.new(flow_trigger: flow_trigger, hook_scope: hook_scope, data: data).allowed?
  end

  allowed.each do |value|
    it "allows the flow to run when #{field} is #{value}" do
      expect(precondition_allows?(hook_scope, field, value)).to be(true)
    end
  end

  denied.each do |value|
    it "prevents the flow from running when #{field} is #{value}" do
      expect(precondition_allows?(hook_scope, field, value)).to be(false)
    end
  end
end
