# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::ConsistencyChecks::Orchestrator, feature_category: :vulnerability_management do
  let_it_be(:project) { build_stubbed(:project) }

  describe 'CONSISTENCY_CHECKS' do
    subject(:consistency_checks) { described_class::CONSISTENCY_CHECKS }

    it 'includes TriggerParityCheck' do
      expect(consistency_checks).to include(Vulnerabilities::ConsistencyChecks::TriggerParityCheck)
    end

    it 'includes DuplicateDefaultTrackedContextsCheck' do
      expect(consistency_checks).to include(
        Vulnerabilities::ConsistencyChecks::DuplicateDefaultTrackedContextsCheck
      )
    end

    it 'includes all expected checks' do
      expect(consistency_checks).to match_array([
        Vulnerabilities::ConsistencyChecks::HasVulnerabilitiesIsCorrectCheck,
        Vulnerabilities::ConsistencyChecks::BackfillIssueLinkOccurrenceIdCheck,
        Vulnerabilities::ConsistencyChecks::BackfillMergeRequestLinkOccurrenceIdCheck,
        Vulnerabilities::ConsistencyChecks::TriggerParityCheck,
        Vulnerabilities::ConsistencyChecks::TrackedContextTraversalIdsCheck,
        Vulnerabilities::ConsistencyChecks::DuplicateDefaultTrackedContextsCheck
      ])
    end
  end

  describe '#execute' do
    subject(:execute) { described_class.new(project).execute }

    let(:synchronous_check) { Vulnerabilities::ConsistencyChecks::HasVulnerabilitiesIsCorrectCheck }
    let(:asynchronous_checks) do
      [
        Vulnerabilities::ConsistencyChecks::BackfillIssueLinkOccurrenceIdCheck,
        Vulnerabilities::ConsistencyChecks::BackfillMergeRequestLinkOccurrenceIdCheck,
        Vulnerabilities::ConsistencyChecks::TriggerParityCheck,
        Vulnerabilities::ConsistencyChecks::DuplicateDefaultTrackedContextsCheck
      ]
    end

    context 'on the first run', :clean_gitlab_redis_shared_state do
      it 'enqueues every consistency check on the project' do
        expect(described_class::CONSISTENCY_CHECKS).to all(receive(:enqueue).with(project))

        execute
      end
    end

    context 'with the per-project cooldown throttle', :clean_gitlab_redis_shared_state do
      it 'runs the synchronous check every time but throttles the async checks' do
        expect(synchronous_check).to receive(:enqueue).with(project).twice
        expect(asynchronous_checks).to all(receive(:enqueue).with(project).once)

        described_class.new(project).execute
        # Second run within the cooldown: sync check runs again, async checks do not
        described_class.new(project).execute
      end

      it 'does not burn the cooldown when a synchronous check raises' do
        allow(synchronous_check).to receive(:enqueue).and_raise(StandardError)

        expect { described_class.new(project).execute }.to raise_error(StandardError)

        # Cooldown key must not be set, so async checks still enqueue on the next run
        allow(synchronous_check).to receive(:enqueue)
        expect(asynchronous_checks).to all(receive(:enqueue).with(project).once)

        described_class.new(project).execute
      end

      it 'sets the cooldown key with the configured expiry' do
        execute

        ttl = Gitlab::Redis::SharedState.with { |redis| redis.ttl(Vulnerabilities::ConsistencyChecks.cooldown_key(project)) }

        expect(ttl).to be > 0
        expect(ttl).to be <= Vulnerabilities::ConsistencyChecks::COOLDOWN_PERIOD.to_i
      end
    end
  end
end
