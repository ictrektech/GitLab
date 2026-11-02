# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Orbit GitLab.com add-on lapse', feature_category: :knowledge_graph do
  let_it_be_with_reload(:group) { create(:group) }

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
    stub_licensed_features(orbit: true)
    stub_feature_flags(orbit_promo_access_gate: true, orbit_trial: true)

    create(:orbit_namespace_enrollment, namespace: group, source: :direct)
    create(:knowledge_graph_enabled_namespace, namespace: group)
    create(:gitlab_subscription_add_on_purchase, :orbit_promo, :expired, namespace: group)
  end

  it 'stops queries' do
    expect(::Analytics::KnowledgeGraph::OrbitLicense.entitled?(group)).to be(false)
  end

  it 'stops indexing after the ended-trials cron runs', :sidekiq_inline do
    ::Analytics::Orbit::ScheduleDisableEndedTrialsWorker.new.perform

    expect(group.reload.knowledge_graph_enabled_namespace).to be_nil
  end
end
