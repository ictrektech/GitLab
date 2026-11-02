# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::Trials::CaptureUsageWorker, :saas, feature_category: :acquisition do
  it_behaves_like 'worker with data consistency', described_class, data_consistency: :sticky

  it { expect(described_class.get_feature_category).to eq(:acquisition) }
  it { expect(described_class.worker_has_external_dependencies?).to be(true) }
  it { expect(described_class.get_urgency).to eq(:low) }

  describe '#perform' do
    let_it_be(:group) { create(:group) }
    let_it_be(:gitlab_subscription) do
      create(:gitlab_subscription, :active_trial, hosted_plan: create(:ultimate_trial_plan),
        namespace: group, trial_ends_on: Date.current + 1)
    end

    before do
      allow_next_instance_of(Gitlab::SubscriptionPortal::SubscriptionUsageClient) do |client|
        allow(client).to receive(:get_trial_usage)
          .and_return({ success: true, trialUsage: { usersUsage: { creditsUsed: 3.0 } } })
      end
    end

    it_behaves_like 'an idempotent worker' do
      let(:job_args) { [gitlab_subscription.id] }

      it 'stores exactly one snapshot for the subscription' do
        perform_idempotent_work

        expect(GitlabSubscriptions::TrialUsage.where(namespace: group).count).to eq(1)
      end
    end

    it 'captures usage through the service and logs the outcome' do
      worker = described_class.new

      expect_next_instance_of(GitlabSubscriptions::Trials::CaptureUsageService, gitlab_subscription) do |service|
        expect(service).to receive(:execute).and_call_original
      end
      expect(worker).to receive(:log_extra_metadata_on_done).with(:capture_status, :success)
      expect(worker).not_to receive(:log_extra_metadata_on_done).with(:capture_reason, anything)

      worker.perform(gitlab_subscription.id)
    end

    context 'when the service skips the capture' do
      let_it_be(:paid_subscription) { create(:gitlab_subscription, :ultimate, namespace: create(:group)) }

      it 'logs the skip reason instead of storing a snapshot' do
        worker = described_class.new

        expect(worker).to receive(:log_extra_metadata_on_done).with(:capture_status, :error)
        expect(worker).to receive(:log_extra_metadata_on_done).with(:capture_reason, :not_a_trial)

        expect { worker.perform(paid_subscription.id) }.not_to change { GitlabSubscriptions::TrialUsage.count }
      end
    end

    context 'when the subscription no longer exists' do
      it 'does nothing' do
        expect(GitlabSubscriptions::Trials::CaptureUsageService).not_to receive(:new)

        described_class.new.perform(non_existing_record_id)
      end
    end
  end
end
