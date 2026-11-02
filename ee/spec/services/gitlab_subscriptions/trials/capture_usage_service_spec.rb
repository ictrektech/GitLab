# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::Trials::CaptureUsageService, :saas, :freeze_time, feature_category: :acquisition do
  let_it_be(:group) { create(:group) }
  let_it_be(:ultimate_trial_plan) { create(:ultimate_trial_plan) }

  let_it_be_with_reload(:gitlab_subscription) do
    create(
      :gitlab_subscription, :active_trial,
      namespace: group, hosted_plan: ultimate_trial_plan, max_seats_used: 4,
      trial_starts_on: Date.new(2026, 9, 15), trial_ends_on: Date.new(2026, 10, 15)
    )
  end

  let(:now) { Time.utc(2026, 10, 13, 1) }

  let(:cdot_response) do
    { success: true, trialUsage: { usersUsage: { creditsUsed: 12.5, totalUsersUsingCredits: 2 } } }
  end

  subject(:execute) { described_class.new(gitlab_subscription).execute }

  before_all do
    create(:ci_namespace_monthly_usage, namespace: group, amount_used: 250, date: Date.new(2026, 10, 1))
    create(:ci_namespace_monthly_usage, namespace: group, amount_used: 999, date: Date.new(2026, 9, 1))
  end

  before do
    travel_to(now)

    allow_next_instance_of(Gitlab::SubscriptionPortal::SubscriptionUsageClient) do |client|
      allow(client).to receive(:get_trial_usage).and_return(cdot_response)
    end
  end

  def snapshot
    GitlabSubscriptions::TrialUsage.find_by(namespace: group, trial_ends_on: gitlab_subscription.trial_ends_on)
  end

  it 'stores one snapshot built from the subscription, compute usage and CustomersDot', :aggregate_failures do
    expect { execute }.to change { GitlabSubscriptions::TrialUsage.count }.by(1)

    expect(execute).to be_success
    expect(snapshot).to have_attributes(
      trial_starts_on: gitlab_subscription.trial_starts_on,
      trial_ends_on: gitlab_subscription.trial_ends_on,
      trial_type: GitlabSubscriptions::Trials::FREE_TRIAL_TYPE_V2,
      max_seats_used: 4,
      compute_minutes_used: 625,
      compute_minutes_month: Date.new(2026, 10, 1),
      credits_used: 12.5
    )
  end

  it 'queries CustomersDot for the trial namespace' do
    client = instance_double(Gitlab::SubscriptionPortal::SubscriptionUsageClient, get_trial_usage: cdot_response)
    expect(Gitlab::SubscriptionPortal::SubscriptionUsageClient)
      .to receive(:new).with(namespace_id: group.id).and_return(client)

    execute
  end

  it 'is idempotent and refreshes the existing snapshot instead of adding a row', :aggregate_failures do
    described_class.new(gitlab_subscription).execute
    gitlab_subscription.update_column(:max_seats_used, 7)

    expect { execute }.not_to change { GitlabSubscriptions::TrialUsage.count }
    expect(snapshot.max_seats_used).to eq(7)
  end

  context 'when the trial covers fewer than 7 days of its end month' do
    let(:now) { Time.utc(2026, 11, 1, 1) }

    before do
      gitlab_subscription.update!(trial_starts_on: Date.new(2026, 10, 4), trial_ends_on: Date.new(2026, 11, 3))
    end

    it 'extrapolates the month before instead', :aggregate_failures do
      execute

      expect(snapshot).to have_attributes(compute_minutes_used: 242, compute_minutes_month: Date.new(2026, 10, 1))
    end
  end

  context 'when the namespace used no compute minutes in the measured month' do
    let(:now) { Time.utc(2026, 8, 13, 1) }

    before do
      gitlab_subscription.update!(trial_starts_on: Date.new(2026, 7, 15), trial_ends_on: Date.new(2026, 8, 15))
    end

    it 'stores zero without dividing by the elapsed days' do
      execute

      expect(snapshot).to have_attributes(compute_minutes_used: 0, compute_minutes_month: Date.new(2026, 8, 1))
    end
  end

  context 'when CustomersDot fails on a refresh' do
    before do
      create(:gitlab_subscription_trial_usage, namespace: group,
        trial_starts_on: gitlab_subscription.trial_starts_on, trial_ends_on: gitlab_subscription.trial_ends_on,
        credits_used: 12.5, max_seats_used: 2)

      allow_next_instance_of(Gitlab::SubscriptionPortal::SubscriptionUsageClient) do |client|
        allow(client).to receive(:get_trial_usage)
          .and_raise(Gitlab::SubscriptionPortal::SubscriptionUsageClient::ResponseError)
      end
    end

    it 'keeps the stored credits and refreshes the rest', :aggregate_failures do
      expect { execute }.not_to change { GitlabSubscriptions::TrialUsage.count }
      expect(snapshot).to have_attributes(credits_used: 12.5, max_seats_used: 4, compute_minutes_used: 625)
    end
  end

  context 'when the trial started from a Premium plan' do
    let_it_be(:paid_customer_plan) { create(:ultimate_trial_paid_customer_plan) }

    before do
      gitlab_subscription.update!(hosted_plan: paid_customer_plan)
    end

    it 'records the premium trial type' do
      execute

      expect(snapshot.trial_type).to eq(GitlabSubscriptions::Trials::PREMIUM_TRIAL_TYPE_V2)
    end
  end

  context 'when CustomersDot returns an error response' do
    before do
      allow_next_instance_of(Gitlab::SubscriptionPortal::SubscriptionUsageClient) do |client|
        allow(client).to receive(:get_trial_usage)
          .and_raise(Gitlab::SubscriptionPortal::SubscriptionUsageClient::ResponseError)
      end
    end

    it 'still stores the snapshot with unknown credits', :aggregate_failures do
      expect(execute).to be_success
      expect(snapshot).to have_attributes(max_seats_used: 4, compute_minutes_used: 625, credits_used: nil)
    end
  end

  context 'when CustomersDot is unreachable' do
    before do
      allow_next_instance_of(Gitlab::SubscriptionPortal::SubscriptionUsageClient) do |client|
        allow(client).to receive(:get_trial_usage).and_raise(Errno::ECONNREFUSED)
      end
    end

    it 'tracks the failure and stores the snapshot with unknown credits', :aggregate_failures do
      expect(Gitlab::ErrorTracking)
        .to receive(:track_exception).with(instance_of(Errno::ECONNREFUSED), namespace_id: group.id)

      expect(execute).to be_success
      expect(snapshot.credits_used).to be_nil
    end
  end

  context 'when the subscription is not a trial' do
    before do
      gitlab_subscription.update!(trial: false)
    end

    it 'does not store anything', :aggregate_failures do
      expect { execute }.not_to change { GitlabSubscriptions::TrialUsage.count }
      expect(execute).to be_error
      expect(execute.reason).to eq(:not_a_trial)
    end
  end

  context 'when the trial does not end after it starts' do
    before do
      gitlab_subscription.update_columns(trial_ends_on: gitlab_subscription.trial_starts_on)
    end

    it 'does not store anything instead of hitting the check constraint', :aggregate_failures do
      expect { execute }.not_to change { GitlabSubscriptions::TrialUsage.count }
      expect(execute).to be_error
      expect(execute.reason).to eq(:not_a_trial)
    end
  end
end
