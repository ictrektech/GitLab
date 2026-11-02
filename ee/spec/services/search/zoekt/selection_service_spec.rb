# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::Zoekt::SelectionService, feature_category: :global_search do
  describe '.execute' do
    subject(:resource_pool) { described_class.execute }

    let_it_be(:_) { create(:application_setting) }
    let_it_be(:ns_1) { create(:group) }
    let_it_be(:ns_2) { create(:group) }

    context 'with basic resource pool structure' do
      it 'returns a resource pool responding to :enabled_namespaces and :nodes' do
        expect(resource_pool).to respond_to(:enabled_namespaces)
        expect(resource_pool).to respond_to(:nodes)
      end
    end

    context 'with enabled namespaces selection' do
      let_it_be(:namespace_with_too_many) { create(:group) }
      let_it_be(:namespace_with_too_few) { create(:group) }
      let_it_be(:namespace_with_exact) { create(:group) }
      let_it_be(:namespace_failed) { create(:group) }

      let_it_be(:eligible_namespace_too_many) do
        create(:zoekt_enabled_namespace, namespace: namespace_with_too_many, number_of_replicas_override: 2)
      end

      let_it_be(:eligible_namespace_too_few) do
        create(:zoekt_enabled_namespace, namespace: namespace_with_too_few)
      end

      let_it_be(:namespace_with_exact_replicas) do
        create(:zoekt_enabled_namespace, namespace: namespace_with_exact)
      end

      let_it_be(:failed_namespace) do
        create(:zoekt_enabled_namespace, namespace: namespace_failed, last_rollout_failed_at: Time.current.iso8601,
          number_of_replicas_override: 2)
      end

      before do
        stub_const('Search::Zoekt::Settings', Class.new)
        allow(Search::Zoekt::Settings).to receive_messages(default_number_of_replicas: 2, rollout_retry_interval: 1.day)
      end

      before_all do
        # eligible_namespace_too_many has 3 replicas but needs only 2
        create_list(:zoekt_replica, 3, zoekt_enabled_namespace: eligible_namespace_too_many)

        # eligible_namespace_too_few has 1 replica but needs 2 (default)
        create(:zoekt_replica, zoekt_enabled_namespace: eligible_namespace_too_few)

        # namespace_with_exact_replicas has 2 replicas and needs 2 (default) - should be excluded
        create_list(:zoekt_replica, 2, zoekt_enabled_namespace: namespace_with_exact_replicas)

        # failed_namespace has 3 replicas but needs 2, but should be excluded due to rollout failure
        create_list(:zoekt_replica, 3, zoekt_enabled_namespace: failed_namespace)
      end

      it 'includes namespaces with mismatched replicas' do
        expect(resource_pool.enabled_namespaces).to include(eligible_namespace_too_many, eligible_namespace_too_few)
      end

      it 'excludes namespaces with exact number of replicas' do
        expect(resource_pool.enabled_namespaces).not_to include(namespace_with_exact_replicas)
      end

      it 'excludes namespaces with rollout blocked flag' do
        expect(resource_pool.enabled_namespaces).not_to include(failed_namespace)
      end

      it 'calls each_batch_with_mismatched_replicas' do
        rollout_allowed_relation = Search::Zoekt::EnabledNamespace.with_rollout_allowed
        allow(Search::Zoekt::EnabledNamespace).to receive(:with_rollout_allowed).and_return(rollout_allowed_relation)
        expect(rollout_allowed_relation).to receive(:each_batch_with_mismatched_replicas).and_call_original

        described_class.execute
      end

      context 'when testing specific scopes' do
        it 'with_rollout_blocked scope finds namespaces with last_rollout_failed_at' do
          namespaces = Search::Zoekt::EnabledNamespace.with_rollout_blocked
          expect(namespaces).to include(failed_namespace)
          expect(namespaces).not_to include(eligible_namespace_too_many)
        end

        it 'with_rollout_allowed scope finds namespaces without last_rollout_failed_at' do
          namespaces = Search::Zoekt::EnabledNamespace.with_rollout_allowed
          expect(namespaces).to include(eligible_namespace_too_many)
          expect(namespaces).not_to include(failed_namespace)
        end
      end
    end

    context 'with max batch size enforcement' do
      let(:max_batch_size) { 2 }

      subject(:resource_pool) { described_class.new(max_batch_size: max_batch_size).execute }

      before do
        stub_const('Search::Zoekt::Settings', Class.new)
        allow(Search::Zoekt::Settings).to receive_messages(default_number_of_replicas: 2, rollout_retry_interval: 1.day)
      end

      before_all do
        # Create more eligible namespaces with mismatched replicas than the max batch size.
        3.times do
          enabled_ns = create(:zoekt_enabled_namespace)
          create(:zoekt_replica, zoekt_enabled_namespace: enabled_ns) # Only 1 replica, needs 2
        end
      end

      it 'limits the number of selected namespaces to the max batch size' do
        expect(resource_pool.enabled_namespaces.size).to eq(max_batch_size)
      end
    end

    context 'with namespaces without replicas' do
      let_it_be(:without_replicas) { create_list(:zoekt_enabled_namespace, 2) }
      let_it_be(:too_many_replicas) { create(:zoekt_enabled_namespace) }

      subject(:enabled_namespaces) { described_class.new(max_batch_size: max_batch_size).execute.enabled_namespaces }

      before_all do
        create_list(:zoekt_replica, 2, zoekt_enabled_namespace: too_many_replicas)
      end

      context 'when they fill the batch' do
        let(:max_batch_size) { 2 }

        it 'selects them oldest first without the full scan' do
          expect(Search::Zoekt::EnabledNamespace).not_to receive(:each_batch_with_mismatched_replicas)

          expect(enabled_namespaces).to eq(without_replicas)
        end
      end

      context 'when the batch has room left' do
        let(:max_batch_size) { 3 }

        it 'also selects namespaces with other replica mismatches' do
          expect(enabled_namespaces).to contain_exactly(*without_replicas, too_many_replicas)
        end
      end

      context 'when namespaces need more than one replica' do
        let(:max_batch_size) { 2 }

        before do
          allow(Search::Zoekt::Settings).to receive(:default_number_of_replicas).and_return(2)
        end

        it 'selects namespaces without a replica before those short of one' do
          short_of_replica = create(:zoekt_enabled_namespace)
          create(:zoekt_replica, zoekt_enabled_namespace: short_of_replica)

          expect(enabled_namespaces).to eq(without_replicas)
        end
      end

      context 'with the cursor', :use_clean_rails_memory_store_caching do
        let(:max_batch_size) { 2 }

        it 'starts the next run at the first namespace it selected' do
          expect(enabled_namespaces).to eq(without_replicas)

          create(:zoekt_replica, zoekt_enabled_namespace: without_replicas.first)
          newer = create(:zoekt_enabled_namespace)

          expect(described_class.new(max_batch_size: max_batch_size).execute.enabled_namespaces)
            .to eq([without_replicas.second, newer])
        end

        it 'skips namespaces at or below the cursor until the key rotates' do
          create(:zoekt_replica, zoekt_enabled_namespace: without_replicas.first)
          create(:zoekt_replica, zoekt_enabled_namespace: without_replicas.second)
          expect(enabled_namespaces).to contain_exactly(too_many_replicas)

          Search::Zoekt::Replica.where(zoekt_enabled_namespace: without_replicas.first).delete_all

          expect(Search::Zoekt::EnabledNamespace).to receive(:without_replicas)
            .with(after_id: Search::Zoekt::EnabledNamespace.maximum(:id))
            .and_call_original
          described_class.new(max_batch_size: 1).execute

          expect(Search::Zoekt::EnabledNamespace).to receive(:without_replicas).with(after_id: 0).and_call_original
          travel_to(described_class::CURSOR_CACHE_TTL.from_now) do
            expect(described_class.new(max_batch_size: 1).execute.enabled_namespaces).to eq([without_replicas.first])
          end
        end
      end
    end

    context 'with paid namespaces enabled after trials', :saas do
      let_it_be(:trial_namespaces) do
        Array.new(2) do
          create(:zoekt_enabled_namespace, namespace: create(:gitlab_subscription, :ultimate, :active_trial).namespace)
        end
      end

      let_it_be(:paid_namespace) do
        create(:zoekt_enabled_namespace, namespace: create(:gitlab_subscription, :ultimate).namespace)
      end

      subject(:enabled_namespaces) { described_class.new(max_batch_size: max_batch_size).execute.enabled_namespaces }

      context 'when exact code search is available' do
        let(:max_batch_size) { 1 }

        it 'selects the paid namespace ahead of older trials' do
          expect(enabled_namespaces).to eq([paid_namespace])
        end

        context 'when the batch has room for trials' do
          let(:max_batch_size) { 3 }

          it 'fills the rest with trials, without selecting the paid namespace twice' do
            expect(enabled_namespaces.first).to eq(paid_namespace)
            expect(enabled_namespaces).to contain_exactly(paid_namespace, *trial_namespaces)
          end
        end
      end

      context 'when exact code search is not a SaaS feature' do
        let(:max_batch_size) { 3 }

        before do
          stub_saas_features(exact_code_search: false)
        end

        it 'skips the paid-first query' do
          expect(Search::Zoekt::EnabledNamespace).not_to receive(:with_paid_subscription)

          expect(enabled_namespaces).to contain_exactly(paid_namespace, *trial_namespaces)
        end
      end
    end

    context 'with available nodes selection' do
      let_it_be(:eligible_node) { create(:zoekt_node, :enough_free_space) }
      let_it_be(:eligible_node2) { create(:zoekt_node, :not_enough_free_space) }
      let_it_be(:offline_node) { create(:zoekt_node, :offline, :enough_free_space) }
      # Node with no unclaimed storage.
      let_it_be(:no_storage_node) { create(:zoekt_node, total_bytes: 100.gigabytes, used_bytes: 100.gigabytes) }

      it 'returns only online zoekt nodes with positive unclaimed storage ordered by unclaimed_storage_bytes' do
        expect(resource_pool.nodes.to_a).to eq([eligible_node, eligible_node2])
        expect(resource_pool.nodes).not_to include(no_storage_node, offline_node)
      end
    end

    context 'when no eligible namespaces exist' do
      before do
        stub_const('Search::Zoekt::Settings', Class.new)
        allow(Search::Zoekt::Settings).to receive_messages(default_number_of_replicas: 2, rollout_retry_interval: 1.day)
      end

      before_all do
        # Create namespaces with exact replica counts (not mismatched)
        2.times do
          enabled_ns = create(:zoekt_enabled_namespace)
          create_list(:zoekt_replica, 2, zoekt_enabled_namespace: enabled_ns) # Exactly 2 replicas, matching default
        end

        # Create a failed namespace with mismatched replicas
        failed_ns = create(:zoekt_enabled_namespace, last_rollout_failed_at: Time.current.iso8601)
        create(:zoekt_replica, zoekt_enabled_namespace: failed_ns) # Only 1 replica but blocked
      end

      it 'returns an empty array for namespaces' do
        expect(resource_pool.enabled_namespaces).to be_empty
      end
    end

    context 'when no eligible nodes exist' do
      before do
        Search::Zoekt::Node.update_all(last_seen_at: (Search::Zoekt::Node::ONLINE_DURATION_THRESHOLD + 1.minute).ago)
      end

      it 'returns an empty array for nodes' do
        expect(resource_pool.nodes).to eq([])
      end
    end
  end
end
