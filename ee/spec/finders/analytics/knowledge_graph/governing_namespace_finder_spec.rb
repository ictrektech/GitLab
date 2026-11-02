# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::KnowledgeGraph::GoverningNamespaceFinder, feature_category: :knowledge_graph do
  let_it_be_with_reload(:user) { create(:user, :with_namespace) }

  subject(:finder) { described_class.new(user) }

  describe '#candidates' do
    context 'when SaaS with the Orbit promo access gate', :saas do
      let_it_be(:add_on_namespace) { create(:group) }
      let_it_be(:trial_namespace) { create(:group) }
      let_it_be(:ended_trial_namespace) { create(:group) }
      let_it_be(:beta_premium_namespace) { create(:group) }
      let_it_be(:add_on_without_orbit_namespace) { create(:group) }

      let_it_be(:orbit_promo) { create(:gitlab_subscription_add_on, :orbit_promo) }

      before_all do
        create(:gitlab_subscription, :premium, namespace: beta_premium_namespace)
        create(:gitlab_subscription_add_on_purchase, add_on: orbit_promo, namespace: add_on_namespace)
        create(:gitlab_subscription_add_on_purchase, add_on: orbit_promo, namespace: add_on_without_orbit_namespace)
        create(:orbit_namespace_enrollment, namespace: trial_namespace)
        create(:orbit_namespace_enrollment, namespace: ended_trial_namespace, trial_ended_at: 1.day.ago)
        create(:orbit_namespace_enrollment, :beta, namespace: beta_premium_namespace)

        [add_on_namespace, trial_namespace, ended_trial_namespace, beta_premium_namespace].each do |namespace|
          create(:knowledge_graph_enabled_namespace, namespace: namespace)
        end

        [add_on_namespace, trial_namespace, ended_trial_namespace, beta_premium_namespace,
          add_on_without_orbit_namespace].each do |namespace|
          namespace.add_developer(user)
        end
      end

      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'returns the namespaces with the add-on or a trial in progress and Orbit enabled' do
        expect(finder.candidates).to contain_exactly(add_on_namespace, trial_namespace)
      end

      context 'when the orbit_promo_access_gate flag is enabled only for one namespace' do
        before do
          stub_feature_flags(orbit_promo_access_gate: add_on_namespace)
        end

        it 'keeps the paid plan rule for the other namespaces' do
          expect(finder.candidates).to contain_exactly(add_on_namespace, beta_premium_namespace)
        end
      end
    end

    context 'when SaaS', :saas do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
        stub_feature_flags(orbit_promo_access_gate: false)
      end

      context 'when user belongs to namespaces with various plan and Orbit configurations' do
        # Eligible: paid plan + Orbit enabled
        let_it_be(:premium_namespace) { create(:group, name: 'premium_namespace') }
        let_it_be(:ultimate_namespace) { create(:group, name: 'ultimate_namespace') }

        # Excluded: paid plan but Orbit NOT enabled
        let_it_be(:premium_without_orbit_namespace) do
          create(:group, name: 'premium_without_orbit_namespace')
        end

        # Excluded: Orbit enabled but no paid plan
        let_it_be(:orbit_only_namespace) { create(:group, name: 'orbit_only_namespace') }

        # Excluded: trial plan
        let_it_be(:premium_trial_namespace) { create(:group, name: 'premium_trial_namespace') }
        let_it_be(:ultimate_trial_namespace) { create(:group, name: 'ultimate_trial_namespace') }

        # Excluded: free plan
        let_it_be(:free_namespace) { create(:group, name: 'free_namespace') }

        let_it_be(:premium_subscription) do
          create(:gitlab_subscription, :premium, namespace: premium_namespace)
        end

        let_it_be(:ultimate_subscription) do
          create(:gitlab_subscription, :ultimate, namespace: ultimate_namespace)
        end

        let_it_be(:premium_without_orbit_subscription) do
          create(:gitlab_subscription, :premium, namespace: premium_without_orbit_namespace)
        end

        let_it_be(:premium_trial_subscription) do
          create(:gitlab_subscription, :premium, :active_trial, namespace: premium_trial_namespace)
        end

        let_it_be(:ultimate_trial_subscription) do
          create(:gitlab_subscription, :ultimate, :active_trial, namespace: ultimate_trial_namespace)
        end

        before_all do
          [premium_namespace, ultimate_namespace, orbit_only_namespace].each do |namespace|
            create(:knowledge_graph_enabled_namespace, namespace: namespace)
          end

          [premium_namespace, ultimate_namespace, premium_without_orbit_namespace, orbit_only_namespace,
            premium_trial_namespace, ultimate_trial_namespace, free_namespace].each do |namespace|
            namespace.add_developer(user)
          end
        end

        it 'returns only paid premium/ultimate namespaces with Orbit enabled' do
          expect(finder.candidates).to match_array([premium_namespace, ultimate_namespace])
        end

        it 'excludes paid namespaces without Orbit enabled' do
          expect(finder.candidates).not_to include(premium_without_orbit_namespace)
        end

        it 'excludes Orbit-enabled namespaces without a paid plan' do
          expect(finder.candidates).not_to include(orbit_only_namespace)
        end

        it 'excludes trial plan namespaces' do
          expect(finder.candidates).not_to include(premium_trial_namespace, ultimate_trial_namespace)
        end
      end

      context 'when the user role differs across paid namespaces with Orbit enabled' do
        let_it_be(:reporter_namespace) { create_billable_root }
        let_it_be(:guest_namespace) { create_billable_root }
        let_it_be(:planner_namespace) { create_billable_root }
        let_it_be(:project_only_namespace) { create_billable_root }
        let_it_be(:subgroup_only_namespace) { create_billable_root }
        let_it_be(:banned_namespace) { create_billable_root }

        before_all do
          reporter_namespace.add_reporter(user)
          guest_namespace.add_guest(user)
          planner_namespace.add_planner(user)
          create(:project, group: project_only_namespace).add_developer(user)
          create(:group, parent: subgroup_only_namespace).add_reporter(user)
          banned_namespace.add_developer(user)
          create(:namespace_ban, namespace: banned_namespace, user: user)
        end

        it 'returns only the namespaces that give the user Orbit access' do
          expect(finder.candidates).to contain_exactly(reporter_namespace, subgroup_only_namespace)
        end
      end

      it 'is empty when user has no paid plans' do
        expect(finder.candidates).to be_empty
      end
    end

    context 'when Self-Managed' do
      let_it_be(:top_level_group) { create(:group) }

      before_all do
        top_level_group.add_maintainer(user)
        create(:knowledge_graph_enabled_namespace, namespace: top_level_group)
      end

      it 'returns no namespaces' do
        expect(finder.candidates).to be_empty
      end
    end
  end

  describe '#eligible?', :saas do
    let_it_be(:candidate) { create_billable_root(developers: user) }
    let_it_be(:other_namespace) { create(:group, developers: user) }

    before do
      stub_saas_features(gitlab_com_subscriptions: true)
      stub_feature_flags(orbit_promo_access_gate: false)
    end

    it 'returns false when namespace_id is nil' do
      expect(finder.eligible?(nil)).to be false
    end

    it 'returns true when the namespace is a candidate' do
      expect(finder.eligible?(candidate.id)).to be true
    end

    it 'returns false when the namespace is not a candidate' do
      expect(finder.eligible?(other_namespace.id)).to be false
    end

    it 'runs no queries after the first check' do
      finder.eligible?(candidate.id)

      expect { finder.eligible?(other_namespace.id) }.not_to exceed_query_limit(0)
    end
  end

  describe '#single_candidate_fallback', :saas do
    let_it_be(:candidate) { create_billable_root(developers: user) }

    before do
      stub_saas_features(gitlab_com_subscriptions: true)
      stub_feature_flags(orbit_promo_access_gate: false)
    end

    it 'returns the namespace when exactly one candidate exists' do
      expect(finder.single_candidate_fallback).to eq(candidate)
    end

    context 'when multiple candidates exist' do
      before_all do
        create_billable_root(developers: user)
      end

      it 'returns nil' do
        expect(finder.single_candidate_fallback).to be_nil
      end
    end

    it 'returns nil when no candidates exist' do
      expect(described_class.new(create(:user)).single_candidate_fallback).to be_nil
    end
  end

  describe '.for', :request_store do
    it 'returns one finder per user within a request' do
      first_finder = described_class.for(user)

      expect(described_class.for(user)).to be(first_finder)
      expect(described_class.for(create(:user))).not_to be(first_finder)
    end
  end

  def create_billable_root(**members)
    create(:group, **members).tap do |group|
      create(:gitlab_subscription, :premium, namespace: group)
      create(:knowledge_graph_enabled_namespace, namespace: group)
    end
  end
end
