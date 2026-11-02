# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Orbit::Settings, feature_category: :duo_agent_platform do
  using RSpec::Parameterized::TableSyntax

  let_it_be_with_reload(:user) { create(:user) }

  # The Knowledge Graph service does not default on in tests.
  before do
    stub_config(knowledge_graph: { 'enabled' => true })
  end

  shared_examples 'a subsetting predicate' do |predicate, subsetting_key|
    describe ".#{predicate}" do
      subject(:result) { described_class.public_send(predicate, user) }

      before do
        stub_saas_features(gitlab_com_subscriptions: false)
        stub_ee_application_setting(orbit_dap_enabled_by_default: true)
        stub_licensed_features(orbit: true)
        stub_feature_flags(orbit_promo_access_gate: false)
      end

      it 'returns false without a user' do
        expect(described_class.public_send(predicate, nil)).to be(false)
      end

      context 'when the Knowledge Graph service is not configured on the instance' do
        before do
          stub_config(knowledge_graph: { 'enabled' => false })
        end

        it { is_expected.to be(false) }
      end

      context 'when Orbit in Duo is off' do
        before do
          stub_ee_application_setting(orbit_dap_enabled_by_default: false)
        end

        it { is_expected.to be(false) }
      end

      it 'returns false when this subsetting is off' do
        user.user_preference.update!(orbit_settings: { subsetting_key => false })

        expect(result).to be(false)
      end

      it 'returns true when this subsetting is on' do
        user.user_preference.update!(orbit_settings: { subsetting_key => true })

        expect(result).to be(true)
      end

      it 'returns true when the subsetting key is absent (defaults to true)' do
        user.user_preference.update!(orbit_settings: {})

        expect(result).to be(true)
      end

      it 'ignores a stored enabled value' do
        user.user_preference.update!(orbit_settings: { 'enabled' => false, subsetting_key => true })

        expect(result).to be(true)
      end
    end
  end

  it_behaves_like 'a subsetting predicate', :agent_enabled?, 'orbit_agent_enabled'
  it_behaves_like 'a subsetting predicate', :chat_enabled?, 'orbit_agentic_chat_enabled'
  it_behaves_like 'a subsetting predicate', :foundational_enabled?, 'orbit_other_foundational_agents_enabled'
  it_behaves_like 'a subsetting predicate', :custom_agents_enabled?, 'orbit_custom_agents_enabled'

  describe 'a GitLab team member' do
    before do
      allow(user).to receive(:gitlab_team_member?).and_return(true)
      stub_saas_features(gitlab_com_subscriptions: false)
      stub_ee_application_setting(orbit_dap_enabled_by_default: true)
      stub_licensed_features(orbit: true)
      stub_feature_flags(orbit_promo_access_gate: false)
    end

    it 'can turn the standalone agent subsetting off' do
      user.user_preference.update!(orbit_settings: { 'orbit_agent_enabled' => false })

      expect(described_class.agent_enabled?(user)).to be(false)
    end
  end

  describe '.orbit_in_duo_on?' do
    subject(:on) { described_class.orbit_in_duo_on?(user) }

    it 'returns false without a user' do
      expect(described_class.orbit_in_duo_on?(nil)).to be(false)
    end

    context 'on GitLab.com' do
      let(:finder) { instance_double(::Analytics::KnowledgeGraph::GoverningNamespaceFinder) }
      let(:candidates) { instance_double(ActiveRecord::Relation) }

      before do
        stub_saas_features(gitlab_com_subscriptions: true)
        allow(::Analytics::KnowledgeGraph::GoverningNamespaceFinder).to receive(:for).with(user).and_return(finder)
        allow(finder).to receive(:candidates).and_return(candidates)
      end

      it 'returns true when the user is in a participating namespace' do
        allow(candidates).to receive(:exists?).and_return(true)

        expect(on).to be(true)
      end

      it 'returns false when the user is not in a participating namespace' do
        allow(candidates).to receive(:exists?).and_return(false)

        expect(on).to be(false)
      end

      it 'returns false when the service is not configured, without consulting the finder' do
        stub_config(knowledge_graph: { 'enabled' => false })

        expect(::Analytics::KnowledgeGraph::GoverningNamespaceFinder).not_to receive(:new)

        expect(on).to be(false)
      end

      it 'does not fall back to the instance license' do
        allow(candidates).to receive(:exists?).and_return(false)

        expect(::Analytics::KnowledgeGraph::OrbitLicense).not_to receive(:available_for?)

        on
      end
    end

    context 'with real GitLab.com membership', :saas, :use_clean_rails_memory_store_caching do
      let_it_be(:root_group) { create(:group) }
      let_it_be(:subgroup) { create(:group, parent: root_group) }
      let_it_be(:root_member) { create(:user) }
      let_it_be(:subgroup_only_member) { create(:user) }

      before_all do
        create(:gitlab_subscription, :premium, namespace: root_group)
        create(:knowledge_graph_enabled_namespace, namespace: root_group)
        root_group.add_developer(root_member)
        subgroup.add_developer(subgroup_only_member)
      end

      before do
        stub_saas_features(gitlab_com_subscriptions: true)
        stub_feature_flags(orbit_promo_access_gate: false)
      end

      it 'counts a direct member of the paid Orbit-on root group' do
        expect(described_class.orbit_in_duo_on?(root_member)).to be(true)
      end

      it 'counts a Reporter+ member of only a subgroup of that root' do
        expect(described_class.orbit_in_duo_on?(subgroup_only_member)).to be(true)
      end
    end

    context 'on a self-managed instance' do
      where(:admin_default, :licensed, :expected) do
        [
          [true, true, true],
          [true, false, false],
          [false, true, false],
          [false, false, false]
        ]
      end

      with_them do
        before do
          stub_saas_features(gitlab_com_subscriptions: false)
          stub_ee_application_setting(orbit_dap_enabled_by_default: admin_default)
          stub_licensed_features(orbit: licensed)
          stub_feature_flags(orbit_promo_access_gate: false)
        end

        it { is_expected.to be(expected) }
      end
    end

    context 'with caching on GitLab.com', :saas, :use_clean_rails_memory_store_caching do
      let(:cache_key) { ['users', user.id, described_class::PARTICIPATING_CACHE_KEY] }
      let(:finder) { instance_double(::Analytics::KnowledgeGraph::GoverningNamespaceFinder) }
      let(:candidates) { instance_double(ActiveRecord::Relation) }

      before do
        stub_saas_features(gitlab_com_subscriptions: true)
        allow(::Analytics::KnowledgeGraph::GoverningNamespaceFinder).to receive(:for).and_return(finder)
        allow(finder).to receive(:candidates).and_return(candidates)
      end

      context 'when the result is positive' do
        before do
          allow(candidates).to receive(:exists?).and_return(true)
        end

        it 'resolves the finder only once within the cache window' do
          expect(::Analytics::KnowledgeGraph::GoverningNamespaceFinder).to receive(:for).once

          2.times { described_class.orbit_in_duo_on?(user) }
        end

        it 'caches the result with the positive TTL' do
          allow(Rails.cache).to receive(:write).and_call_original

          described_class.orbit_in_duo_on?(user)

          expect(Rails.cache).to have_received(:write).with(
            cache_key, true, expires_in: described_class::POSITIVE_CACHE_PERIOD
          )
        end
      end

      context 'when the result is negative' do
        before do
          allow(candidates).to receive(:exists?).and_return(false)
        end

        it 'caches the result with the negative TTL' do
          allow(Rails.cache).to receive(:write).and_call_original

          described_class.orbit_in_duo_on?(user)

          expect(Rails.cache).to have_received(:write).with(
            cache_key, false, expires_in: described_class::NEGATIVE_CACHE_PERIOD
          )
        end
      end
    end
  end

  describe 'SUBSETTINGS constant' do
    it 'maps every flow to a UserPreference accessor that exists' do
      preference = user.user_preference

      described_class::SUBSETTINGS.each_value do |accessor|
        expect(preference).to respond_to(accessor)
        expect(preference).to respond_to("#{accessor}=")
      end
    end

    it 'is the single source of truth for UserPreference::ORBIT_SUBSETTINGS' do
      expect(::UserPreference::ORBIT_SUBSETTINGS).to match_array(described_class::SUBSETTINGS.values)
    end
  end
end
