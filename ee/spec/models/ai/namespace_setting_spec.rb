# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::NamespaceSetting, feature_category: :ai_abstraction_layer do
  describe 'concerns' do
    it { is_expected.to include_module(Ai::HasRolePermissions) }

    it_behaves_like 'settings with role permissions'
  end

  describe 'database' do
    it 'uses the correct table name' do
      expect(described_class.table_name).to eq('namespace_ai_settings')
    end
  end

  describe 'associations' do
    it { is_expected.to belong_to(:namespace).inverse_of(:ai_settings) }
  end

  describe 'validations' do
    it { is_expected.to validate_inclusion_of(:duo_workflow_mcp_enabled).in_array([true, false]) }
    it { is_expected.to validate_inclusion_of(:ai_usage_data_collection_enabled).in_array([true, false]) }
    it { is_expected.to validate_presence_of(:prompt_injection_protection_level) }
    it { is_expected.to validate_inclusion_of(:ai_catalog_restricted_to_group_hierarchy).in_array([true, false]) }
    it { is_expected.to validate_inclusion_of(:web_search_enabled).in_array([true, false]) }

    it_behaves_like 'settings with domain list limits' do
      let_it_be(:namespace) { create(:group) }
      let(:setting) { create(:namespace_ai_settings, namespace: namespace) }
      let(:feature_flag_actor) { namespace }
    end

    describe 'configured_at' do
      let(:setting) { build(:namespace_ai_settings, configured_at: configured_at) }

      context 'when empty' do
        let(:configured_at) { {} }

        it { expect(setting).to be_valid }
      end

      context 'when every tracked setting has a timestamp' do
        let(:configured_at) do
          described_class::PROVENANCE_TRACKED_SETTINGS.index_with('2026-09-14T10:00:00Z')
        end

        it { expect(setting).to be_valid }
      end

      context 'when a key is not a tracked setting' do
        let(:configured_at) { { 'duo_agent_platform_enabled' => '2026-09-14T10:00:00Z' } }

        it 'is invalid' do
          expect(setting).not_to be_valid
          expect(setting.errors[:configured_at]).to be_present
        end
      end

      context 'when a value is not a date-time' do
        let(:configured_at) { { 'duo_workflow_mcp_enabled' => 'yesterday' } }

        it 'is invalid' do
          expect(setting).not_to be_valid
          expect(setting.errors[:configured_at]).to be_present
        end
      end
    end

    describe 'feature_settings' do
      let(:setting) { build(:namespace_ai_settings, feature_settings: feature_settings) }

      context 'with seen foundational flow and agent references' do
        let(:feature_settings) do
          {
            'seen_foundational_flow_references' => %w[code_review/v1],
            'seen_foundational_agent_references' => %w[duo_planner]
          }
        end

        it { expect(setting).to be_valid }
      end

      context 'when a seen reference is not a string' do
        let(:feature_settings) { { 'seen_foundational_flow_references' => [1] } }

        it 'is invalid' do
          expect(setting).not_to be_valid
          expect(setting.errors[:feature_settings]).to be_present
        end
      end
    end

    describe '#validate_namespace_for_catalog_restriction' do
      context 'when namespace is a root group' do
        let(:group) { create(:group) }
        let(:ai_settings) { group.ai_settings }

        it 'is valid when setting is changed' do
          ai_settings.ai_catalog_restricted_to_group_hierarchy = true
          expect(ai_settings).to be_valid
        end
      end

      context 'when namespace is a sub-group' do
        let(:parent) { create(:group) }
        let(:subgroup) { create(:group, parent: parent) }
        let(:ai_settings) { subgroup.ai_settings }

        it 'is invalid when setting is changed' do
          ai_settings.ai_catalog_restricted_to_group_hierarchy = true
          expect(ai_settings).not_to be_valid
          expect(ai_settings.errors[:ai_catalog_restricted_to_group_hierarchy])
            .to include('can only be set for top-level groups')
        end
      end

      context 'when namespace is a personal namespace' do
        let(:user_namespace) { create(:namespace) }
        let(:ai_settings) { described_class.new(namespace: user_namespace) }

        it 'is invalid when setting is changed' do
          ai_settings.ai_catalog_restricted_to_group_hierarchy = true
          expect(ai_settings).not_to be_valid
          expect(ai_settings.errors[:ai_catalog_restricted_to_group_hierarchy])
            .to include('can only be set for top-level groups')
        end
      end
    end

    describe '#validate_namespace_for_web_search' do
      context 'when namespace is a root group' do
        let(:group) { create(:group) }
        let(:ai_settings) { group.ai_settings }

        it 'is valid when setting is changed' do
          ai_settings.web_search_enabled = true
          expect(ai_settings).to be_valid
        end
      end

      context 'when namespace is a sub-group' do
        let(:parent) { create(:group) }
        let(:subgroup) { create(:group, parent: parent) }
        let(:ai_settings) { subgroup.ai_settings }

        it 'is invalid when setting is changed' do
          ai_settings.web_search_enabled = true
          expect(ai_settings).not_to be_valid
          expect(ai_settings.errors[:web_search_enabled])
            .to include('can only be set for top-level groups')
        end
      end

      context 'when namespace is a personal namespace' do
        let(:user_namespace) { create(:namespace) }
        let(:ai_settings) { described_class.new(namespace: user_namespace) }

        it 'is invalid when setting is changed' do
          ai_settings.web_search_enabled = true
          expect(ai_settings).not_to be_valid
          expect(ai_settings.errors[:web_search_enabled])
            .to include('can only be set for top-level groups')
        end
      end

      context 'when the setting is not the attribute being changed' do
        let(:parent) { create(:group) }
        let(:subgroup) { create(:group, parent: parent) }
        let(:ai_settings) { subgroup.ai_settings }

        it 'is valid on a sub-group, so records can be created without touching the setting' do
          expect(ai_settings.web_search_enabled).to be(false)
          expect(ai_settings).to be_valid
        end

        it 'is valid when a sub-group record changes an unrelated attribute' do
          ai_settings.save!

          ai_settings.duo_workflow_mcp_enabled = true

          expect(ai_settings.web_search_enabled_changed?).to be(false)
          expect(ai_settings).to be_valid
        end
      end
    end
  end

  describe 'enums' do
    it 'defines prompt injection protection level enum' do
      is_expected.to define_enum_for(:prompt_injection_protection_level).with_values(log_only: 0, no_checks: 1,
        interrupt: 2)
    end
  end

  describe 'before_validation' do
    describe '#normalize_domain_lists' do
      let(:setting) { build(:namespace_ai_settings) }

      it 'lowercases allowed_domains before validation' do
        setting.allowed_domains = ['EXAMPLE.COM', 'GitLab.Com']
        setting.valid?
        expect(setting.allowed_domains).to match_array(['example.com', 'gitlab.com'])
      end

      it 'lowercases denied_domains before validation' do
        setting.denied_domains = ['EVIL.COM', 'Bad.Org']
        setting.valid?
        expect(setting.denied_domains).to match_array(['evil.com', 'bad.org'])
      end
    end
  end

  describe 'factory' do
    it 'has a valid factory' do
      expect(build(:namespace_ai_settings)).to be_valid
    end
  end
end
