# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::Impact::Evaluators, feature_category: :security_policy_management do
  describe '.for' do
    let(:setting_rule) do
      { 'type' => 'setting_validation', 'value' => { 'setting' => 'visibility', 'value' => 'private' } }
    end

    it 'returns the settings evaluator for setting_validation rules' do
      expect(described_class.for([setting_rule, setting_rule])).to be_a(described_class::Settings)
    end

    it 'returns nil for a rule kind without a host-side evaluator' do
      expect(described_class.for([{ 'type' => 'custom', 'value' => 'package governance' }])).to be_nil
    end

    it 'returns nil for a rule set that mixes kinds' do
      expect(described_class.for([setting_rule, { 'type' => 'custom', 'value' => 'package governance' }])).to be_nil
    end

    it 'returns nil when a setting_validation rule has no readable shape' do
      expect(described_class.for([{ 'type' => 'setting_validation', 'value' => { 'value' => true } }])).to be_nil
    end

    it 'returns nil for a rule that is not an object' do
      expect(described_class.for(['package governance'])).to be_nil
    end
  end
end
