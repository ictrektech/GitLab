# frozen_string_literal: true

RSpec::Matchers.define :allow_action do |action|
  match do |policy|
    expect(policy).to be_allowed(action)
  end

  failure_message do |policy|
    policy.debug(action, debug_output = +'')
    "expected #{policy} to allow #{action}\n\n#{debug_output}"
  end

  failure_message_when_negated do |policy|
    policy.debug(action, debug_output = +'')
    "expected #{policy} not to allow #{action}\n\n#{debug_output}"
  end
end

RSpec::Matchers.define :override_delegates_for do |*abilities|
  def format_abilities(set)
    set.empty? ? 'nothing' : set.map { |a| ":#{a}" }.join(', ')
  end

  match do |policy_class|
    @overrides = policy_class.overrides
    @missing = abilities.to_set - @overrides
    @missing.empty?
  end

  failure_message do |policy_class|
    expected = format_abilities(abilities)

    msg = "expected #{policy_class.name} to override #{expected}\n"
    msg << "  missing:  #{format_abilities(@missing)}\n"
    msg << "  actually overrides: #{format_abilities(@overrides)}"
  end

  failure_message_when_negated do |policy_class|
    expected = format_abilities(abilities)
    unexpected = abilities.to_set & @overrides

    msg = "expected #{policy_class.name} not to override #{expected}\n"
    msg << "  unexpectedly overrides: #{format_abilities(unexpected)}\n"
    msg << "  all overrides: #{format_abilities(@overrides)}"
  end
end

# Accepts a policy instance, or a policy class whose subject is built from the
# model's default factory with a nil user.
RSpec::Matchers.define :delegate_to do |expected|
  def build_policy(policy_class)
    model = policy_class.name.delete_suffix('Policy').safe_constantize
    raise ArgumentError, "no model for #{policy_class}, pass a policy instance instead" unless model

    # Prefer the factory named after the model, so a variant such as :incident is never picked
    name = model.model_name.singular.to_sym
    factory = FactoryBot.factories.find(name) if FactoryBot.factories.registered?(name)
    factory ||= FactoryBot.factories.detect do |f|
      f.build_class == model
    rescue NameError # skip factories whose class doesn't exist
      false
    end
    raise ArgumentError, "no factory for #{model}, pass a policy instance instead" unless factory

    policy_class.new(nil, FactoryBot.build_stubbed(factory.name))
  end

  match do |actual|
    @policy = actual.is_a?(Class) ? build_policy(actual) : actual
    @policy.delegated_policies.values.any?(expected)
  end

  failure_message do
    "expected #{@policy.class.name} to delegate to #{expected.name}, but it does not"
  end

  failure_message_when_negated do
    "expected #{@policy.class.name} not to delegate to #{expected.name}, but it does"
  end
end
