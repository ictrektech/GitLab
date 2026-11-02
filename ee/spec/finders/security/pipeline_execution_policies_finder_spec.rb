# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::PipelineExecutionPoliciesFinder, feature_category: :security_policy_management do
  let!(:policy) do
    build(:pipeline_execution_policy, name: 'Contains custom pipeline configuration', policy_scope: policy_scope)
  end

  let!(:policy_yaml) do
    build(:orchestration_policy_yaml, pipeline_execution_policy: [policy])
  end

  let(:expected_extra_attrs) { { type: 'pipeline_execution_policy', policy_index: 0 } }

  include_context 'with security policies information'

  it_behaves_like 'security policies finder'

  context 'when an unrelated policy type in the same configuration is invalid' do
    let!(:policy_yaml) do
      build(
        :orchestration_policy_yaml,
        pipeline_execution_policy: [policy],
        approval_policy: [build(:approval_policy), build(:approval_policy, name: 'a' * 256)]
      )
    end

    before do
      stub_licensed_features(security_orchestration_policies: true)
      object.add_developer(actor)
    end

    it 'returns the pipeline execution policies' do
      expect(policy_configuration.policy_configuration_valid?).to be(false)

      expect(described_class.new(actor, object, params).execute).to match_array([policy.merge(
        config: policy_configuration,
        project: object,
        namespace: nil,
        inherited: false,
        csp: false,
        **expected_extra_attrs
      )])
    end
  end
end
