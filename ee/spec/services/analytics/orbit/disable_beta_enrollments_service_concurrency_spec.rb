# frozen_string_literal: true

require 'spec_helper'

# Needs real concurrent connections, so it uses the :delete strategy and no let_it_be.
RSpec.describe Analytics::Orbit::DisableBetaEnrollmentsService, :delete, feature_category: :knowledge_graph do
  let!(:group) { create(:group) }

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
    stub_feature_flags(orbit_promo_access_gate: true)
    allow(Analytics::Orbit::Trial).to receive(:request_status_for)
      .and_return(instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_active?: false))
    create(:orbit_namespace_enrollment, :beta, namespace: group)
    create(:knowledge_graph_enabled_namespace, namespace: group)
  end

  # Without the row lock the cleanup reads the stale beta row and waits at its delete instead.
  def wait_until_a_session_is_blocked_by(pid)
    Timeout.timeout(10) do
      sleep 0.01 until ApplicationRecord.connection.select_value(<<~SQL).present?
        SELECT 1 FROM pg_stat_activity WHERE pg_blocking_pids(pid) @> ARRAY[#{pid.to_i}] LIMIT 1
      SQL
    end
  end

  it 'waits for a concurrent beta-to-trial conversion and then keeps the trial enrollment' do
    converted = Queue.new
    release = Queue.new

    starter = Thread.new do
      ApplicationRecord.transaction do
        Analytics::Orbit::NamespaceEnrollment.convert_beta_to_trial(group.id)
        converted << ApplicationRecord.connection.select_value('SELECT pg_backend_pid()')
        release.pop(timeout: 10)
      end
    end
    starter_pid = converted.pop(timeout: 10)
    raise 'the conversion did not start' unless starter_pid

    cron = Thread.new { described_class.new.execute }
    wait_until_a_session_is_blocked_by(starter_pid)
    release << true
    starter.join(10)

    expect(cron.value.payload[:disabled_count]).to eq(0)
    expect(group.reload.orbit_namespace_enrollment).to be_trial
    expect(group.knowledge_graph_enabled_namespace).to be_present
  ensure
    release << true
    [starter, cron].compact.each { |thread| thread.join(10) }
  end
end
