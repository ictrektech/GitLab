# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::Trials::ScheduleUsageCaptureWorker, :saas, :clean_gitlab_redis_queues,
  :clean_gitlab_redis_shared_state, feature_category: :acquisition do
  it_behaves_like 'worker with data consistency', described_class, data_consistency: :sticky

  it { is_expected.to include_module(CronjobQueue) }
  it { expect(described_class.get_feature_category).to eq(:acquisition) }

  describe '#perform' do
    let_it_be(:ultimate_trial_plan) { create(:ultimate_trial_plan) }

    let_it_be(:ending_soon) do
      create(:gitlab_subscription, :active_trial, hosted_plan: ultimate_trial_plan,
        namespace: create(:group), trial_ends_on: Date.current + 1)
    end

    let_it_be(:ending_later) do
      create(:gitlab_subscription, :active_trial, hosted_plan: ultimate_trial_plan,
        namespace: create(:group), trial_ends_on: Date.current + 10)
    end

    let_it_be(:captured_yesterday) do
      create(:gitlab_subscription, :active_trial, hosted_plan: ultimate_trial_plan,
        namespace: create(:group), trial_ends_on: Date.current + 2)
    end

    before_all do
      create(:gitlab_subscription_trial_usage, namespace: captured_yesterday.namespace,
        trial_starts_on: captured_yesterday.trial_starts_on, trial_ends_on: captured_yesterday.trial_ends_on)
    end

    before do
      allow_next_instance_of(Gitlab::SubscriptionPortal::SubscriptionUsageClient) do |client|
        allow(client).to receive(:get_trial_usage)
          .and_return({ success: true, trialUsage: { usersUsage: { creditsUsed: 3.0 } } })
      end
    end

    def scheduled_subscription_ids
      GitlabSubscriptions::Trials::CaptureUsageWorker.jobs.map { |job| job['args'] }.uniq
    end

    it_behaves_like 'an idempotent worker' do
      it 'schedules capture for every trial ending inside the window' do
        scheduled = []
        allow(GitlabSubscriptions::Trials::CaptureUsageWorker)
          .to receive(:bulk_perform_async_with_contexts) { |subscriptions, **| scheduled.concat(subscriptions) }

        perform_idempotent_work

        expect(scheduled.uniq).to contain_exactly(ending_soon, captured_yesterday)
      end
    end

    it 'enqueues one child job per trial ending inside the window, refreshing existing snapshots' do
      described_class.new.perform

      expect(scheduled_subscription_ids).to contain_exactly([ending_soon.id], [captured_yesterday.id])
    end

    it 'sets the namespace as the job context' do
      described_class.new.perform

      namespaces = GitlabSubscriptions::Trials::CaptureUsageWorker.jobs.map { |job| job['meta.root_namespace'] }

      expect(namespaces).to contain_exactly(ending_soon.namespace.full_path, captured_yesterday.namespace.full_path)
    end

    context 'when the feature flag is disabled' do
      before do
        stub_feature_flags(trial_usage_capture: false)
      end

      it 'schedules nothing' do
        described_class.new.perform

        expect(GitlabSubscriptions::Trials::CaptureUsageWorker.jobs).to be_empty
      end
    end

    context 'when not on GitLab.com' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      it 'schedules nothing' do
        described_class.new.perform

        expect(GitlabSubscriptions::Trials::CaptureUsageWorker.jobs).to be_empty
      end
    end
  end
end
