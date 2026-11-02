# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::DisableBetaEnrollmentsWorker, feature_category: :knowledge_graph do
  let_it_be(:group) { create(:group) }
  let(:worker) { described_class.new }

  before_all do
    create(:orbit_namespace_enrollment, :beta, namespace: group)
    create(:knowledge_graph_enabled_namespace, namespace: group)
  end

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
    Feature.enable(:orbit_promo_access_gate)
    allow(::Analytics::Orbit::Trial).to receive(:request_status_for)
      .and_return(instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: false))
  end

  it_behaves_like 'an idempotent worker'

  it 'disables Orbit for beta groups' do
    expect { worker.perform }
      .to change { Analytics::KnowledgeGraph::EnabledNamespace.count }.by(-1)
      .and change { Analytics::Orbit::NamespaceEnrollment.count }.by(-1)
  end

  it 'logs the number of disabled and converted groups, and whether the run hit the runtime limit' do
    expect(worker).to receive(:log_extra_metadata_on_done).with(:disabled_count, 1)
    expect(worker).to receive(:log_extra_metadata_on_done).with(:converted_count, 0)
    expect(worker).to receive(:log_extra_metadata_on_done).with(:over_time, false)

    worker.perform
  end

  it 'does nothing on a second run' do
    worker.perform

    expect(worker).to receive(:log_extra_metadata_on_done).with(:disabled_count, 0)
    expect(worker).to receive(:log_extra_metadata_on_done).with(:converted_count, 0)
    expect(worker).to receive(:log_extra_metadata_on_done).with(:over_time, false)

    worker.perform
  end

  shared_examples 'does not disable Orbit' do
    it 'keeps the rows' do
      expect { worker.perform }.not_to change { Analytics::KnowledgeGraph::EnabledNamespace.count }
      expect(group.reload.orbit_namespace_enrollment).to be_beta
    end
  end

  context 'when not on GitLab.com' do
    before do
      stub_saas_features(gitlab_com_subscriptions: false)
    end

    it_behaves_like 'does not disable Orbit'
  end

  context 'when the flag is enabled for one group only' do
    before do
      Feature.disable(:orbit_promo_access_gate)
      Feature.enable(:orbit_promo_access_gate, group)
    end

    it_behaves_like 'does not disable Orbit'
  end

  context 'when the flag is enabled for a percentage of actors' do
    before do
      Feature.disable(:orbit_promo_access_gate)
      Feature.enable_percentage_of_actors(:orbit_promo_access_gate, 99)
    end

    it_behaves_like 'does not disable Orbit'
  end

  context 'when the flag is disabled' do
    before do
      Feature.disable(:orbit_promo_access_gate)
    end

    it_behaves_like 'does not disable Orbit'
  end
end
