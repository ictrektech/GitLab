# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::Impact::ScopeSupport, feature_category: :security_policy_management do
  describe '.single_arm?' do
    it 'is true for no scope, for exclusions only and for one inclusion dimension', :aggregate_failures do
      expect(described_class.single_arm?(nil)).to be(true)
      expect(described_class.single_arm?({ 'projects' => { 'excluding' => [{ 'id' => 1 }] } })).to be(true)
      expect(described_class.single_arm?({ projects: { including: [{ id: 1 }] } })).to be(true)
    end

    it 'is false once a second inclusion dimension is declared' do
      scope = { 'projects' => { 'including' => [{ 'id' => 1 }] }, 'compliance_frameworks' => [{ 'id' => 7 }] }

      expect(described_class.single_arm?(scope)).to be(false)
    end
  end

  describe '.unsupported_reason' do
    subject(:reason) { described_class.unsupported_reason(policy_scope, scope_rego: scope_rego) }

    let(:scope_rego) { nil }

    context 'with no scope' do
      let(:policy_scope) { nil }

      it { is_expected.to be_nil }
    end

    context 'with specific projects, the editor shape' do
      let(:policy_scope) { { 'projects' => { 'including' => [{ 'id' => 1 }, { 'id' => 2 }], 'excluding' => [] } } }

      it { is_expected.to be_nil }
    end

    context 'with symbol keys' do
      let(:policy_scope) { { projects: { including: [{ id: 1 }] } } }

      it { is_expected.to be_nil }
    end

    context 'with exclusions only' do
      let(:policy_scope) do
        { 'projects' => { 'excluding' => [{ 'id' => 1 }, { 'type' => 'archived' }] },
          'groups' => { 'excluding' => [{ 'id' => 3 }] } }
      end

      it { is_expected.to be_nil }
    end

    context 'with a scope written in Rego' do
      let(:policy_scope) { nil }
      let(:scope_rego) { 'package gitlab.scope' }

      it { is_expected.to eq(:scope_rego) }
    end

    context 'with a security attribute dimension' do
      let(:policy_scope) { { 'business_impact' => { 'including' => [{ 'id' => 1 }] } } }

      it { is_expected.to eq(:security_attributes) }
    end

    context 'with a security attribute dimension that only excludes' do
      let(:policy_scope) { { 'business_impact' => { 'excluding' => [{ 'id' => 1 }] } } }

      it { is_expected.to eq(:security_attributes) }
    end

    context 'with an inclusion that names nothing, which the compiled scope matches nothing with' do
      let(:policy_scope) { { 'projects' => { 'including' => [{}] } } }

      it { is_expected.to eq(:empty_inclusion) }
    end

    context 'with two inclusion dimensions' do
      let(:policy_scope) do
        { 'projects' => { 'including' => [{ 'id' => 1 }] }, 'groups' => { 'including' => [{ 'id' => 3 }] } }
      end

      it 'is unsupported, since the compiled scope intersects them and the resolver unions them' do
        expect(reason).to eq(:combined_inclusions)
      end

      context 'when the scope matches any of them' do
        let(:policy_scope) { super().merge('match_mode' => 'any') }

        it { is_expected.to be_nil }
      end
    end

    context 'with compliance frameworks alongside projects' do
      let(:policy_scope) do
        { 'projects' => { 'including' => [{ 'id' => 1 }] }, 'compliance_frameworks' => [{ 'id' => 7 }] }
      end

      it { is_expected.to eq(:combined_inclusions) }
    end
  end
end
