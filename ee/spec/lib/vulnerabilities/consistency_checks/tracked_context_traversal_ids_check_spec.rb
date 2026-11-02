# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::ConsistencyChecks::TrackedContextTraversalIdsCheck,
  feature_category: :vulnerability_management do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, namespace: group) }
  let_it_be_with_reload(:default_context) { create(:security_project_tracked_context, :default, project: project) }
  let_it_be_with_reload(:non_default_context) { create(:security_project_tracked_context, project: project) }

  subject(:check) { described_class.new(project) }

  it 'runs asynchronously' do
    expect(described_class).not_to be_synchronous
  end

  describe '.enqueue' do
    subject(:enqueue) { described_class.enqueue(project) }

    it 'enqueues the consistency check' do
      expect(Vulnerabilities::ConsistencyCheckWorker).to receive(:perform_async).with(described_class.name, project.id)

      enqueue
    end

    context 'when sync_drifted_tracked_context_traversal_ids is disabled' do
      before do
        stub_feature_flags(sync_drifted_tracked_context_traversal_ids: false)
      end

      it 'does not enqueue the consistency check' do
        expect(Vulnerabilities::ConsistencyCheckWorker).not_to receive(:perform_async)

        enqueue
      end
    end
  end

  describe '#consistent?' do
    subject(:consistent?) { check.consistent? }

    context 'when all tracked contexts match the project namespace' do
      it { is_expected.to be(true) }
    end

    context 'when the default context has drifted traversal_ids' do
      before do
        default_context.update_column(:traversal_ids, [non_existing_record_id])
      end

      it { is_expected.to be(false) }
    end

    context 'when only a non-default context has drifted traversal_ids' do
      before do
        non_default_context.update_column(:traversal_ids, [non_existing_record_id])
      end

      it { is_expected.to be(false) }
    end

    context 'when a tracked context has empty traversal_ids' do
      before do
        default_context.update_column(:traversal_ids, [])
      end

      it { is_expected.to be(false) }
    end

    context 'when only a tracked context of another project has drifted traversal_ids' do
      let_it_be(:other_project_context) do
        create(:security_project_tracked_context).tap { |context| context.update_column(:traversal_ids, []) }
      end

      it { is_expected.to be(true) }
    end

    context 'when sync_drifted_tracked_context_traversal_ids is disabled' do
      before do
        stub_feature_flags(sync_drifted_tracked_context_traversal_ids: false)
        default_context.update_column(:traversal_ids, [non_existing_record_id])
      end

      it 'still reports drift, because the flag gates #execute and not the predicate' do
        expect(consistent?).to be(false)
      end
    end
  end

  describe '#execute' do
    subject(:execute) { check.execute }

    context 'when tracked contexts are consistent' do
      it 'does not enqueue a traversal_ids sync' do
        expect(Security::SyncTrackedContextTraversalIdsWorker).not_to receive(:perform_async)

        execute
      end
    end

    context 'when tracked contexts have drifted traversal_ids' do
      before do
        default_context.update_column(:traversal_ids, [non_existing_record_id])
      end

      it 'enqueues a traversal_ids sync for the project' do
        expect(Security::SyncTrackedContextTraversalIdsWorker).to receive(:perform_async).with(project.id)

        execute
      end

      context 'when sync_drifted_tracked_context_traversal_ids is disabled' do
        before do
          stub_feature_flags(sync_drifted_tracked_context_traversal_ids: false)
        end

        it 'does not check consistency or enqueue a traversal_ids sync', :aggregate_failures do
          expect(check).not_to receive(:consistent?)
          expect(check).not_to receive(:fix!)
          expect(Security::SyncTrackedContextTraversalIdsWorker).not_to receive(:perform_async)

          execute
        end
      end

      it 'logs the detected drift' do
        allow(Gitlab::AppLogger).to receive(:info)

        execute

        expect(Gitlab::AppLogger).to have_received(:info).with(
          hash_including(
            message: 'Detected drifted tracked context traversal_ids, scheduling a resync',
            project_id: project.id,
            job: described_class.name
          )
        )
      end
    end
  end
end
