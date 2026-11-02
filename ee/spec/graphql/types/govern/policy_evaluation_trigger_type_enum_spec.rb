# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['GovernPolicyEvaluationTriggerType'], feature_category: :security_policy_management do
  it 'mirrors the model enum' do
    # A GraphQL enum name cannot hold a dot, so the type substitutes an underscore.
    expect(described_class.values.keys)
      .to match_array(Govern::PolicyEvaluation.trigger_types.keys.map { |type| type.tr('.', '_').upcase })
  end
end
