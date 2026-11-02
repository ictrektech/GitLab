# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PreferencesHelper, feature_category: :settings do
  before do
    allow(helper).to receive(:current_user).and_return(user)
  end

  let(:user) { build(:user) }

  describe '#dashboard_choices' do
    context 'when allowed to read operations dashboard' do
      before do
        allow(helper).to receive(:can?).with(user, :read_operations_dashboard).and_return(true)
      end

      it 'does not contain operations dashboard' do
        expect(helper.dashboard_choices).to include({ text: 'Operations Dashboard', value: 'operations' })
      end
    end

    context 'when not allowed to read operations dashboard' do
      before do
        allow(helper).to receive(:can?).with(user, :read_operations_dashboard).and_return(false)
      end

      it 'does not contain operations dashboard' do
        expect(helper.dashboard_choices).not_to include(['Operations Dashboard', 'operations'])
      end
    end
  end

  describe '#group_view_choices' do
    subject { helper.group_view_choices }

    context 'when security dashboard feature is enabled' do
      before do
        stub_licensed_features(security_dashboard: true)
      end

      it { is_expected.to include(['Security dashboard', :security_dashboard]) }
    end

    context 'when security dashboard feature is disabled' do
      it { is_expected.not_to include(['Security dashboard', :security_dashboard]) }
    end
  end

  describe '#extensions_marketplace_view' do
    let(:application_setting_enabled) { true }

    subject { helper.extensions_marketplace_view }

    before do
      allow(::WebIde::ExtensionMarketplace).to receive(:feature_enabled_from_application_settings?)
        .and_return(application_setting_enabled)
    end

    context 'when feature not enabled at application_settings' do
      let(:application_setting_enabled) { false }

      it { is_expected.to be_nil }
    end

    context 'when remote_development licensed feature is enabled' do
      before do
        stub_licensed_features(remote_development: true)
      end

      context 'when Web IDE Extension Marketplace feature is enabled' do
        let(:application_setting_enabled) { true }

        it { is_expected.to match(a_hash_including(title: 'Web IDE and Workspaces', message: /IDE and Workspaces/)) }
      end

      context 'when Web IDE Extension Marketplace feature not enabled' do
        let(:application_setting_enabled) { false }

        it { is_expected.to match(a_hash_including(title: 'Workspaces', message: /for Workspaces/)) }
      end
    end

    context 'when remote_development licensed feature is not enabled' do
      before do
        stub_licensed_features(remote_development: false)
      end

      context 'when Web IDE Extension Marketplace feature is enabled' do
        let(:application_setting_enabled) { true }

        it { is_expected.to match(a_hash_including(name: 'extensions_marketplace')) }
      end
    end
  end

  describe '#group_overview_content_preference?' do
    subject { helper.group_overview_content_preference? }

    context 'when security dashboard feature is enabled' do
      before do
        stub_licensed_features(security_dashboard: true)
      end

      it { is_expected.to be(true) }
    end

    context 'when security dashboard feature is disabled' do
      it { is_expected.to be(false) }
    end
  end

  describe '#preferences_tabs' do
    let(:user) { create_default(:user) }
    let(:tab_ids) { helper.preferences_tabs.pluck(:id) }

    before do
      stub_feature_flags(enable_hamilton_in_user_preferences: false)
      allow(helper).to receive(:integration_views).and_return([])
      allow(helper).to receive(:can?).with(user, :assign_default_duo_group).and_return(false)
      allow(helper).to receive(:can?).with(user, :update_governing_knowledge_graph_namespace).and_return(false)
      allow(::Ai::Orbit::Settings).to receive(:orbit_in_duo_on?).with(user).and_return(false)
    end

    it 'does not include the GitLab Duo tab when no Duo preference is available' do
      expect(tab_ids).not_to include('ai-assistance')
    end

    it 'places the GitLab Duo tab after localization when the default Duo group can be assigned' do
      allow(helper).to receive(:can?).with(user, :assign_default_duo_group).and_return(true)

      expect(tab_ids).to eq(%w[appearance behavior editing localization ai-assistance])
      expect(helper.preferences_tabs.last).to eq(id: 'ai-assistance', title: 'AI assistance', partial: 'duo')
    end

    it 'includes the GitLab Duo tab when the Orbit preference is visible' do
      allow(::Ai::Orbit::Settings).to receive(:orbit_in_duo_on?).with(user).and_return(true)

      expect(tab_ids).to include('ai-assistance')
    end

    it 'includes the GitLab Duo tab when the user can choose a billable Orbit namespace' do
      allow(helper).to receive(:orbit_billable_namespace_candidates).and_return(build_list(:group, 2))

      expect(tab_ids).to include('ai-assistance')
    end

    it 'includes the GitLab Duo tab when the Code Suggestions preference is enabled' do
      stub_feature_flags(enable_hamilton_in_user_preferences: user)

      expect(tab_ids).to include('ai-assistance')
    end
  end

  describe '#orbit_billable_namespace_candidates' do
    let(:user) { create_default(:user) }
    let(:candidates) { build_list(:group, 2) }

    subject { helper.orbit_billable_namespace_candidates }

    before do
      allow(helper).to receive(:can?).with(user, :update_governing_knowledge_graph_namespace).and_return(allowed)
      finder = instance_double(::Analytics::KnowledgeGraph::GoverningNamespaceFinder, candidates: candidates)
      allow(::Analytics::KnowledgeGraph::GoverningNamespaceFinder).to receive(:for).with(user).and_return(finder)
    end

    context 'when the user may not update the governing namespace' do
      let(:allowed) { false }

      it { is_expected.to be_empty }
    end

    context 'when the user may update the governing namespace' do
      let(:allowed) { true }

      it { is_expected.to eq(candidates) }

      context 'with a single candidate' do
        let(:candidates) { build_list(:group, 1) }

        it { is_expected.to be_empty }
      end
    end
  end

  describe '#should_show_code_suggestions_preferences?' do
    subject { helper.should_show_code_suggestions_preferences?(user) }

    let(:user) { create_default(:user) }

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(enable_hamilton_in_user_preferences: false)
      end

      it { is_expected.to be(false) }
    end

    it { is_expected.to be(true) }
  end
end
