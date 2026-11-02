# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Analytics::Orbit::DisableEndedTrialsWorker, feature_category: :knowledge_graph do
  let_it_be(:ended_group) { create(:group) }
  let_it_be(:other_ended_group) { create(:group) }
  let_it_be(:active_group) { create(:group) }
  let_it_be(:beta_group) { create(:group) }
  let_it_be(:flag_off_group) { create(:group) }
  let_it_be(:turned_back_on_group) { create(:group) }
  let_it_be(:outside_range_group) { create(:group) }

  let(:job_args) { [ended_group.id, turned_back_on_group.id] }
  let(:worker) { described_class.new }

  before_all do
    [ended_group, other_ended_group, active_group, flag_off_group, outside_range_group].each do |group|
      create(:orbit_namespace_enrollment, namespace: group)
    end
    create(:orbit_namespace_enrollment, :beta, namespace: beta_group)
    create(:orbit_namespace_enrollment, namespace: turned_back_on_group, trial_ended_at: 1.day.ago)

    [ended_group, other_ended_group, active_group, beta_group, flag_off_group, turned_back_on_group,
      outside_range_group].each do |group|
      create(:knowledge_graph_enabled_namespace, namespace: group)
    end
  end

  before do
    stub_saas_features(gitlab_com_subscriptions: true)
    stub_feature_flags(orbit_trial: [ended_group, other_ended_group, active_group, beta_group, turned_back_on_group,
      outside_range_group], orbit_promo_access_gate: false)
    allow(::Analytics::Orbit::Trial).to receive(:status_for) do |group|
      instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_ended?: group != active_group)
    end
  end

  def orbit_on?(group)
    group.reload.knowledge_graph_enabled_namespace.present?
  end

  it_behaves_like 'an idempotent worker'

  it 'turns off Orbit for the ended trials in the range' do
    worker.perform(*job_args)

    expect(orbit_on?(ended_group)).to be(false)
    expect(orbit_on?(other_ended_group)).to be(false)
  end

  it 'logs the disabled count' do
    expect(worker).to receive(:log_extra_metadata_on_done).with(:disabled_count, 2)

    worker.perform(*job_args)
  end

  describe 'groups that keep Orbit on' do
    before do
      worker.perform(*job_args)
    end

    it('keeps an active trial') { expect(orbit_on?(active_group)).to be(true) }
    it('keeps a beta group') { expect(orbit_on?(beta_group)).to be(true) }
    it('keeps a group with the orbit_trial flag off') { expect(orbit_on?(flag_off_group)).to be(true) }
    it('keeps an ended trial that was turned back on') { expect(orbit_on?(turned_back_on_group)).to be(true) }
    it('keeps a group outside the range') { expect(orbit_on?(outside_range_group)).to be(true) }
  end

  context 'with the Orbit promo access gate on for a group with the orbit_trial flag off' do
    before do
      stub_feature_flags(orbit_promo_access_gate: flag_off_group)
    end

    it 'turns off Orbit for its ended trial' do
      worker.perform(*job_args)

      expect(orbit_on?(flag_off_group)).to be(false)
    end
  end

  describe 'a gated group without access' do
    let_it_be(:orbit_promo_add_on) { create(:gitlab_subscription_add_on, :orbit_promo) }
    let_it_be(:lapsed_group) { create(:group) }
    let_it_be(:active_add_on_group) { create(:group) }
    let_it_be(:opted_out_group) { create(:group) }
    let_it_be(:lapsed_after_trial_group) { create(:group) }
    let_it_be(:active_after_trial_group) { create(:group) }
    let_it_be(:beta_group) { create(:group) }

    let(:gated_groups) do
      [lapsed_group, active_add_on_group, lapsed_after_trial_group, active_after_trial_group, beta_group]
    end

    let(:range) { [lapsed_group.id, beta_group.id] }

    before_all do
      [lapsed_group, active_add_on_group, opted_out_group].each do |group|
        create(:orbit_namespace_enrollment, source: :direct, namespace: group)
      end
      [lapsed_after_trial_group, active_after_trial_group].each do |group|
        create(:orbit_namespace_enrollment, source: :trial, trial_ended_at: 1.day.ago, namespace: group)
      end
      create(:orbit_namespace_enrollment, :beta, namespace: beta_group)
      [lapsed_group, active_add_on_group, opted_out_group, lapsed_after_trial_group,
        active_after_trial_group, beta_group].each do |group|
        create(:knowledge_graph_enabled_namespace, namespace: group)
      end
    end

    before do
      stub_feature_flags(orbit_promo_access_gate: gated_groups)
      [lapsed_group, opted_out_group, lapsed_after_trial_group].each do |group|
        create(:gitlab_subscription_add_on_purchase, :expired, add_on: orbit_promo_add_on, namespace: group)
      end
      [active_add_on_group, active_after_trial_group].each do |group|
        create(:gitlab_subscription_add_on_purchase, add_on: orbit_promo_add_on, namespace: group)
      end
    end

    it 'turns off only the gated non-beta groups that lost their access, without asking CDot' do
      expect(::Analytics::Orbit::Trial).not_to receive(:status_for)

      worker.perform(*range)

      expect(orbit_on?(lapsed_group)).to be(false)
      expect(orbit_on?(lapsed_after_trial_group)).to be(false)
      expect(orbit_on?(beta_group)).to be(true)
      expect(orbit_on?(active_add_on_group)).to be(true)
      expect(orbit_on?(active_after_trial_group)).to be(true)
      expect(orbit_on?(opted_out_group)).to be(true)
    end
  end

  context 'when CDot returns an unexpected response for one group' do
    before do
      allow(::Analytics::Orbit::Trial).to receive(:status_for).with(ended_group)
        .and_raise(::Gitlab::SubscriptionPortal::ProductTrialResponse::Error)
    end

    it 'still checks the other groups' do
      worker.perform(*job_args)

      expect(orbit_on?(ended_group)).to be(true)
      expect(orbit_on?(other_ended_group)).to be(false)
    end
  end

  context 'when CDot is down and then recovers' do
    it 'keeps Orbit on during the outage, then turns it off on the next run' do
      allow(::Analytics::Orbit::Trial).to receive(:status_for)
        .and_raise(::Gitlab::SubscriptionPortal::ProductTrialResponse::UnavailableError)

      worker.perform(*job_args)

      expect(orbit_on?(ended_group)).to be(true)

      allow(::Analytics::Orbit::Trial).to receive(:status_for)
        .and_return(instance_double(::Gitlab::SubscriptionPortal::ProductTrialResponse, trial_ended?: true))

      worker.perform(*job_args)

      expect(orbit_on?(ended_group)).to be(false)
    end
  end

  shared_examples 'stops the batch' do
    before do
      allow(::Analytics::Orbit::Trial).to receive(:status_for).and_raise(error)
    end

    it 'stops the batch at the first group and tracks the error once for the batch' do
      expect(::Analytics::Orbit::Trial).to receive(:status_for).once
      expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(error).once
      expect(worker).to receive(:log_extra_metadata_on_done).with(:disabled_count, 0)

      worker.perform(*job_args)
    end
  end

  context 'when CDot does not answer' do
    let(:error) { ::Gitlab::SubscriptionPortal::ProductTrialResponse::UnavailableError.new }

    it_behaves_like 'stops the batch'
  end

  context 'when CDot is shedding load' do
    let(:error) { ::Gitlab::SubscriptionPortal::ProductTrialResponse::Error.new(cdot_status: 429) }

    it_behaves_like 'stops the batch'
  end
end
