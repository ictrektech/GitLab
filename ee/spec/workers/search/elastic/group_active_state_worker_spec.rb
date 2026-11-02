# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::Elastic::GroupActiveStateWorker, feature_category: :global_search do
  let_it_be(:parent) { create(:group) }
  let_it_be(:child) { create(:group, parent: parent) }
  let_it_be(:grandchild) { create(:group, parent: child) }
  let_it_be(:unrelated) { create(:group) }

  subject(:worker) { described_class.new }

  before do
    stub_ee_application_setting(elasticsearch_indexing: true)
  end

  it 'tracks the group and every descendant' do
    expect(::Elastic::ProcessBookkeepingService).to receive(:track!) do |*refs|
      expect(refs).to include(parent, child, grandchild)
      expect(refs).not_to include(unrelated)
    end

    worker.perform(parent.id)
  end

  context 'when indexing is disabled' do
    before do
      stub_ee_application_setting(elasticsearch_indexing: false)
    end

    it 'does nothing' do
      expect(::Elastic::ProcessBookkeepingService).not_to receive(:track!)

      worker.perform(parent.id)
    end
  end

  context 'when the group no longer exists' do
    it 'does nothing' do
      expect(::Elastic::ProcessBookkeepingService).not_to receive(:track!)

      worker.perform(non_existing_record_id)
    end
  end

  context 'when the group is not indexed' do
    before do
      allow_next_found_instance_of(Group) do |group|
        allow(group).to receive(:use_elasticsearch?).and_return(false)
      end
    end

    it 'does nothing' do
      expect(::Elastic::ProcessBookkeepingService).not_to receive(:track!)

      worker.perform(parent.id)
    end
  end

  # Under limited indexing a subgroup can be indexed while its parent is not. The parent's
  # change is exactly what makes the subgroup's document stale, so the check has to run per
  # descendant rather than once on the group that changed.
  context 'with limited indexing' do
    before do
      stub_ee_application_setting(elasticsearch_limit_indexing: true)
      # Redis-backed and keyed by namespace id, which let_it_be reuses across examples.
      ::Search::Elastic::ElasticsearchEnabledCache.delete(:namespace)
    end

    it 'tracks indexed descendants even when the changed group is not indexed' do
      create(:elasticsearch_indexed_namespace, namespace: child)

      expect(::Elastic::ProcessBookkeepingService).to receive(:track!) do |*refs|
        expect(refs).to include(child, grandchild)
        expect(refs).not_to include(parent)
      end

      worker.perform(parent.id)
    end

    it 'does nothing when no group in the hierarchy is indexed' do
      expect(::Elastic::ProcessBookkeepingService).not_to receive(:track!)

      worker.perform(parent.id)
    end
  end

  it_behaves_like 'an idempotent worker' do
    let(:job_args) { [parent.id] }
  end
end
