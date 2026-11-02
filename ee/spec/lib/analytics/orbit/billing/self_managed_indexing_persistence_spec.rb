# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Orbit self-managed indexing persistence', feature_category: :knowledge_graph do
  let_it_be(:groups) { create_list(:group, 2) }

  before do
    stub_saas_features(gitlab_com_subscriptions: false)
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_promo_access_gate: true, orbit_trial: true)
    create_current_license(cloud_licensing_enabled: true)

    groups.each { |group| create(:knowledge_graph_enabled_namespace, namespace: group) }
  end

  def end_instance_trial_via_cron
    allow(::Analytics::Orbit::Trial).to receive(:status_for_instance).and_return(
      instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_ended?: true, trial_active?: false)
    )

    ::Analytics::Orbit::ScheduleDisableEndedTrialsWorker.new.perform
  end

  def stub_ended_instance_trial_read
    allow(::Analytics::Orbit::Trial).to receive(:request_instance_status).and_return(
      instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: false)
    )
  end

  context 'when the instance trial ends without a purchase (M3.2)' do
    it 'keeps indexing on for every group' do
      end_instance_trial_via_cron

      expect(::Analytics::KnowledgeGraph::EnabledNamespace.count).to eq(groups.size)
    end

    it 'still lets an Owner turn indexing on' do
      end_instance_trial_via_cron

      expect(::Analytics::Orbit::Billing::InstanceAccount.new.turn_on(create(:group))).to be_allowed
    end

    it 'blocks queries' do
      stub_ended_instance_trial_read

      expect(::Analytics::Orbit::Billing::InstanceAccount.new.entitled?).to be(false)
    end
  end

  context 'when the add-on is bought after the instance trial ended (M4.2b)' do
    it 'keeps indexing on' do
      end_instance_trial_via_cron
      create(:gitlab_subscription_add_on_purchase, :orbit_promo, :self_managed)

      expect(::Analytics::KnowledgeGraph::EnabledNamespace.count).to eq(groups.size)
    end
  end

  context 'when the add-on lapses after an instance trial ended earlier (M4.3b)' do
    before do
      create(:gitlab_subscription_add_on_purchase, :orbit_promo, :expired, :self_managed)
    end

    it 'blocks queries' do
      stub_ended_instance_trial_read

      expect(::Analytics::Orbit::Billing::InstanceAccount.new.entitled?).to be(false)
    end

    it 'keeps indexing on through the trial-end cron' do
      end_instance_trial_via_cron

      expect(::Analytics::KnowledgeGraph::EnabledNamespace.count).to eq(groups.size)
    end
  end
end
