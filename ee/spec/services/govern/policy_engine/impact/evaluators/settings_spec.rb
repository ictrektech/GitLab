# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Govern::PolicyEngine::Impact::Evaluators::Settings, feature_category: :security_policy_management do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:group) { create(:group, organization: organization) }
  let_it_be(:compliant_project) { create(:project, group: group, only_allow_merge_if_pipeline_succeeds: true) }
  let_it_be(:violating_project) { create(:project, group: group, only_allow_merge_if_pipeline_succeeds: false) }

  let(:rules) { [rule('only_allow_merge_if_pipeline_succeeds', true)] }

  subject(:evaluator) { described_class.new(rules) }

  def rule(setting, expected)
    Govern::PolicyEngine::SettingValidationRule.new(setting, expected)
  end

  describe '.from_rules' do
    it 'parses the persisted rule shape through the engine class' do
      rules = [{ 'type' => 'setting_validation', 'value' => { 'setting' => 'visibility', 'value' => 'public' } }]

      expect(described_class.from_rules(rules).violates?(violating_project)).to be(true)
    end

    it 'is nil when a rule has no readable shape, rather than an evaluator that skips it' do
      rules = [
        { 'type' => 'setting_validation', 'value' => { 'setting' => 'visibility', 'value' => 'public' } },
        { 'type' => 'setting_validation', 'value' => { 'value' => true } }
      ]

      expect(described_class.from_rules(rules)).to be_nil
    end
  end

  describe '#preloads' do
    it 'asks for what the settings document reads' do
      expect(evaluator.preloads).to eq(Govern::PolicyEngine::ProjectSettingsContext::PRELOAD_ASSOCIATIONS)
    end
  end

  describe '#violates?' do
    it 'reads the same settings document the engine evaluates', :aggregate_failures do
      expect(Govern::PolicyEngine::ProjectSettingsContext).to receive(:settings_for).twice.and_call_original

      expect(evaluator.violates?(violating_project)).to be(true)
      expect(evaluator.violates?(compliant_project)).to be(false)
    end

    context 'with several rules' do
      let(:rules) { [rule('only_allow_merge_if_pipeline_succeeds', true), rule('visibility', 'public')] }

      it 'violates when any rule does' do
        expect(evaluator.violates?(compliant_project)).to be(true)
      end
    end

    context 'with surrounding whitespace in the authored strings, which the emitter strips' do
      let(:rules) { [rule(' visibility ', ' public ')] }

      it 'compares the stripped values' do
        expect(evaluator.violates?(compliant_project)).to be(true)
      end
    end

    context 'with a stored false, which object.get keeps distinct from an absent key' do
      let(:rules) { [rule('request_access_enabled', true)] }
      let_it_be(:closed_project) { create(:project, group: group, request_access_enabled: false) }

      it 'counts it as a violation' do
        expect(evaluator.violates?(closed_project)).to be(true)
      end
    end

    context 'when the stored value is NULL, which the emitter skips as it skips an absent key' do
      let(:rules) { [rule('remove_source_branch_after_merge', true)] }
      let(:unset_project) do
        create(:project, group: group).tap { |project| project.update_column(:remove_source_branch_after_merge, nil) }
      end

      it 'finds no violation' do
        expect(evaluator.violates?(unset_project)).to be(false)
      end
    end

    context 'when the document does not carry the setting' do
      let(:rules) { [rule('secret_push_protection_enabled', true)] }

      before do
        stub_licensed_features(secret_push_protection: false)
      end

      it 'finds no violation, as the emitted object.get guard would' do
        expect(evaluator.violates?(violating_project)).to be(false)
      end
    end
  end

  describe 'inside an impact run' do
    let(:draft) do
      Govern::PolicyEngine::Impact::Draft.build(
        organization_id: organization.id, namespace_id: nil, policy_scope: nil, rules: []
      )
    end

    def run
      Govern::PolicyEngine::Impact::Analysis.new(draft: draft, evaluator: evaluator).execute
    end

    it 'does not query once per project for the settings document' do
      control = ActiveRecord::QueryRecorder.new { run }

      create(:project, group: group, only_allow_merge_if_pipeline_succeeds: false)
      create(:project, group: group, only_allow_merge_if_pipeline_succeeds: true)

      expect { run }.not_to exceed_query_limit(control)
    end
  end
end
