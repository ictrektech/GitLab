# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::InventoryFilters::TriageCapabilitiesUpdateService, feature_category: :security_asset_inventories do
  let_it_be(:group) { create(:group) }
  let_it_be(:project1) { create(:project, namespace: group) }
  let_it_be(:namespace1) { project1.namespace }

  describe '.execute' do
    let(:project_to_capabilities) do
      { project1 => { triage_capabilities_on: 0b1, triage_capabilities_auto: 0b1 } }
    end

    it 'creates a new instance and calls execute' do
      instance = instance_double(described_class)
      expect(described_class).to receive(:new).with(project_to_capabilities).and_return(instance)
      expect(instance).to receive(:execute)

      described_class.execute(project_to_capabilities)
    end

    context 'when project_to_capabilities is blank' do
      it 'does not upsert anything' do
        expect(Security::InventoryFilter).not_to receive(:upsert_all)

        described_class.execute({})
      end
    end

    context 'when no project attributes match the given projects' do
      it 'does not upsert anything' do
        service = described_class.new(project_to_capabilities)
        allow(service).to receive(:project_attributes).and_return({})

        expect(Security::InventoryFilter).not_to receive(:upsert_all)

        service.execute
      end
    end

    context 'with a single project and no existing inventory filter' do
      it 'creates a row with the capability masks and project attributes, without touching analyzer columns',
        :aggregate_failures do
        expect(Security::InventoryFilter).not_to receive(:recompute_aggregate_booleans)

        expect { described_class.execute(project_to_capabilities) }
          .to change { Security::InventoryFilter.count }.by(1)

        filter = Security::InventoryFilter.find_by(project: project1)
        expect(filter).to have_attributes(
          project_name: project1.name,
          traversal_ids: namespace1.traversal_ids,
          archived: false,
          triage_capabilities_on: 0b1,
          triage_capabilities_auto: 0b1,
          has_scanners: false,
          has_failed_or_warning: false,
          has_stale: false
        )
      end
    end

    context 'when an inventory filter already exists' do
      let!(:existing_filter) do
        create(:security_inventory_filters, project: project1, sast: :success,
          triage_capabilities_on: 0, triage_capabilities_auto: 0)
      end

      it 'updates only the triage capability columns, preserving analyzer statuses' do
        expect { described_class.execute(project_to_capabilities) }
          .not_to change { Security::InventoryFilter.count }

        existing_filter.reload
        expect(existing_filter).to have_attributes(
          sast: "success",
          triage_capabilities_on: 0b1,
          triage_capabilities_auto: 0b1
        )
      end
    end

    context 'when an error occurs during execution' do
      let_it_be(:project2) { create(:project, namespace: group) }

      let(:project_to_capabilities) do
        {
          project1 => { triage_capabilities_on: 0b1, triage_capabilities_auto: 0b1 },
          project2 => { triage_capabilities_on: 0b10, triage_capabilities_auto: 0b0 }
        }
      end

      before do
        allow(Security::InventoryFilter).to receive(:upsert_all).and_raise(StandardError.new('Database error'))
      end

      it 'tracks the exception with the batch size and re-raises it, so the worker retries' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(an_instance_of(StandardError), project_count: 2)

        expect { described_class.execute(project_to_capabilities) }
          .to raise_error(StandardError, 'Database error')
      end
    end
  end
end
