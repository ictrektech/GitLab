# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanResultPoliciesFinder, feature_category: :security_policy_management do
  let!(:approval_policy) do
    build(:approval_policy, name: 'Contains security critical', policy_scope: policy_scope)
  end

  let!(:policy_yaml) do
    build(:orchestration_policy_yaml, approval_policy: [approval_policy])
  end

  let(:policy) { approval_policy.merge({ type: 'approval_policy' }) }
  let(:expected_extra_attrs) { { policy_index: 0 } }

  include_context 'with security policies information'

  it_behaves_like 'security policies finder'

  context 'when an unrelated policy type in the same configuration is invalid' do
    let!(:policy_yaml) do
      build(
        :orchestration_policy_yaml,
        approval_policy: [approval_policy],
        pipeline_execution_policy: [build(:pipeline_execution_policy, name: 'a' * 256)]
      )
    end

    before do
      stub_licensed_features(security_orchestration_policies: true)
      object.add_developer(actor)
    end

    it 'returns the approval policies' do
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

    context 'when include_unscoped is false' do
      let(:include_unscoped) { false }
      let(:policy_scope) { { projects: { including: [{ id: object.id }] } } }

      it 'returns the scoped approval policies' do
        expect(described_class.new(actor, object, params).execute).to contain_exactly(
          a_hash_including(name: approval_policy[:name], config: policy_configuration)
        )
      end
    end
  end
end
