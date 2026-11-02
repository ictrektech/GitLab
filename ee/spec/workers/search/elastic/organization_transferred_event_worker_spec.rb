# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Search::Elastic::OrganizationTransferredEventWorker, feature_category: :global_search do
  let(:event) { ::Organizations::GroupTransferredEvent.new(data: data) }

  before do
    stub_ee_application_setting(elasticsearch_search: true, elasticsearch_indexing: true)
  end

  it_behaves_like 'subscribes to event' do
    let(:data) do
      { group_id: 1, old_organization_id: 1, new_organization_id: 2 }
    end
  end

  it 'has until_executed deduplication strategy and if_deduplicated: :reschedule_once as options' do
    expect(described_class.get_deduplicate_strategy).to eq(:until_executed)
    expect(described_class.get_deduplication_options).to include({ if_deduplicated: :reschedule_once })
  end

  context 'when elasticsearch indexing is disabled' do
    let_it_be(:group) { create(:group) }
    let(:data) do
      { group_id: group.id, old_organization_id: 1, new_organization_id: 2 }
    end

    before do
      stub_ee_application_setting(elasticsearch_indexing: false)
    end

    it 'does nothing' do
      expect(::Elastic::ProcessBookkeepingService).not_to receive(:track!)

      consume_event(subscriber: described_class, event: event)
    end
  end

  context 'when the group no longer exists' do
    let(:data) do
      { group_id: non_existing_record_id, old_organization_id: 1, new_organization_id: 2 }
    end

    it 'does not traverse the hierarchy' do
      expect(Project).not_to receive(:by_project_namespace)

      consume_event(subscriber: described_class, event: event)
    end
  end

  it_behaves_like 'an idempotent worker' do
    let_it_be(:old_organization) { create(:organization) }
    let_it_be(:new_organization) { create(:organization) }
    # The transfer commits before the event is published, so by the time the worker runs
    # the rows that moved already carry the new organization.
    let_it_be(:group) { create(:group, organization: new_organization) }
    let_it_be(:subgroup) { create(:group, parent: group, organization: new_organization) }
    let_it_be(:project) { create(:project, group: group, organization: new_organization) }
    let_it_be(:subgroup_project) { create(:project, group: subgroup, organization: new_organization) }

    let(:data) do
      { group_id: group.id, old_organization_id: old_organization.id, new_organization_id: new_organization.id }
    end

    def tracked_records
      records = []
      allow(::Elastic::ProcessBookkeepingService).to receive(:track!) { |*args| records.concat(args) }

      consume_event(subscriber: described_class, event: event)

      records
    end

    it 'tracks the group and every descendant group for re-indexing' do
      expect(tracked_records).to include(group, subgroup)
    end

    it 'tracks every project under the group for re-indexing' do
      expect(tracked_records).to include(project, subgroup_project)
    end

    it 'enqueues the project-owned associations that carry organization fields' do
      allow(ElasticAssociationIndexerWorker).to receive(:perform_async)

      consume_event(subscriber: described_class, event: event)

      expect(ElasticAssociationIndexerWorker).to have_received(:perform_async)
        .with('Project', project.id, described_class::PROJECT_ASSOCIATIONS)
      expect(ElasticAssociationIndexerWorker).to have_received(:perform_async)
        .with('Project', subgroup_project.id, described_class::PROJECT_ASSOCIATIONS)
    end

    it 'enqueues the group-owned associations that carry organization fields' do
      allow(::Elastic::ProcessBookkeepingService).to receive(:maintain_indexed_namespace_associations!)

      consume_event(subscriber: described_class, event: event)

      expect(::Elastic::ProcessBookkeepingService).to have_received(:maintain_indexed_namespace_associations!)
        .with(group, subgroup, associations_to_index: described_class::GROUP_ASSOCIATIONS)
    end

    context 'when no group under the transferred tree is indexed' do
      before do
        allow_next_found_instance_of(Group) do |g|
          allow(g).to receive(:use_elasticsearch?).and_return(false)
        end
      end

      it 'tracks no groups and enqueues no group associations' do
        expect(::Elastic::ProcessBookkeepingService)
          .not_to receive(:maintain_indexed_namespace_associations!)

        expect(tracked_records).not_to include(group, subgroup)
      end

      it 'still tracks the projects, which are indexed regardless of limited indexing' do
        expect(tracked_records).to include(project, subgroup_project)
      end
    end

    # The indexer only re-reads files changed since the last indexed commit, and a transfer
    # changes none, so these documents keep their old organization unless the reindex is forced.
    # TopLevelGroupService moves the root group row alone and publishes immediately;
    # descendants follow under their own event. Re-indexing them on the first event would
    # rewrite the organization they already have, then do it all again on the second.
    context 'when only the root group has moved so far' do
      before do
        # update_all, as the real services use: parent_organization_match rejects this
        # intermediate state, and the records are frozen by let_it_be.
        ::Namespace.id_in([subgroup.id]).update_all(organization_id: old_organization.id)
        ::Project.id_in([project.id, subgroup_project.id])
          .update_all(organization_id: old_organization.id)
      end

      it 'tracks the root group only, leaving the tree for the event that moves it' do
        records = tracked_records

        expect(records).to include(group)
        expect(records).not_to include(subgroup, project, subgroup_project)
      end

      it 'forces no repository re-index for projects that have not moved' do
        expect(::Search::Elastic::CommitIndexerWorker).not_to receive(:perform_async)

        consume_event(subscriber: described_class, event: event)
      end
    end

    describe 'repository content' do
      it 'forces a commit reindex for every project' do
        allow(::Search::Elastic::CommitIndexerWorker).to receive(:perform_async)

        consume_event(subscriber: described_class, event: event)

        expect(::Search::Elastic::CommitIndexerWorker).to have_received(:perform_async)
          .with(project.id, { 'force' => true })
        expect(::Search::Elastic::CommitIndexerWorker).to have_received(:perform_async)
          .with(subgroup_project.id, { 'force' => true })
      end

      it 'forces a wiki reindex for every project and group' do
        allow(ElasticWikiIndexerWorker).to receive(:perform_in)

        consume_event(subscriber: described_class, event: event)

        [[project, 'Project'], [subgroup_project, 'Project'], [group, 'Group'], [subgroup, 'Group']]
          .each do |container, class_name|
            expect(ElasticWikiIndexerWorker).to have_received(:perform_in)
              .with(anything, container.id, class_name, { 'force' => true })
          end
      end

      # A per-batch offset restarts at zero every BATCH_SIZE namespaces, piling a whole
      # tree into the first BATCH_SIZE seconds. One namespace per batch makes that visible.
      context 'when the tree spans several batches' do
        before do
          stub_const("#{described_class}::BATCH_SIZE", 1)
        end

        it 'keeps spreading wiki jobs across batches rather than restarting the offset' do
          intervals = []
          allow(ElasticWikiIndexerWorker).to receive(:perform_in) { |interval, *_rest| intervals << interval }

          consume_event(subscriber: described_class, event: event)

          expect(intervals.size).to eq(4)
          expect(intervals).to eq(intervals.uniq)
          expect(intervals).to match_array([0, 1, 2, 3])
        end
      end

      context 'when the project is not indexed' do
        before do
          allow_next_found_instance_of(Project) do |p|
            allow(p).to receive(:use_elasticsearch?).and_return(false)
          end
        end

        it 'leaves its repository alone, since repository content follows limited indexing' do
          expect(::Search::Elastic::CommitIndexerWorker).not_to receive(:perform_async)

          consume_event(subscriber: described_class, event: event)
        end
      end
    end

    it 'does not have N+1 queries' do
      control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
        consume_event(subscriber: described_class, event: event)
      end

      create(:project, group: subgroup, organization: new_organization)

      expect { consume_event(subscriber: described_class, event: event) }.not_to exceed_all_query_limit(control)
    end
  end
end
