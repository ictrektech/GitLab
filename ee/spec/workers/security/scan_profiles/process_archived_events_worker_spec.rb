# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanProfiles::ProcessArchivedEventsWorker,
  feature_category: :security_testing_configuration, type: :job do
  let_it_be_with_reload(:group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: group) }
  let_it_be(:scan_profile) { create(:security_scan_profile, namespace: group) }

  let_it_be_with_reload(:project) { create(:project, group: group) }
  let_it_be(:project_in_subgroup) { create(:project, group: subgroup) }
  let_it_be(:unattached_project) { create(:project, group: group) }

  let_it_be_with_reload(:association) do
    create(:security_scan_profile_project, scan_profile: scan_profile, project: project)
  end

  let_it_be_with_reload(:subgroup_association) do
    create(:security_scan_profile_project, scan_profile: scan_profile, project: project_in_subgroup)
  end

  it_behaves_like 'worker with data consistency', described_class, data_consistency: :sticky

  describe '#handle_event' do
    subject(:use_event) { consume_event(subscriber: described_class, event: event) }

    context 'with Projects::ProjectArchivedEvent' do
      let(:event) do
        ::Projects::ProjectArchivedEvent.new(data: {
          project_id: project.id,
          namespace_id: group.id,
          root_namespace_id: group.id
        })
      end

      before do
        project.update!(archived: true)
      end

      it_behaves_like 'subscribes to event'

      it_behaves_like 'an idempotent worker' do
        it 'flags the attached project as archived' do
          expect { perform_idempotent_work }.to change { association.reload.archived }.from(false).to(true)
        end
      end

      it 'leaves projects outside the event alone' do
        expect { use_event }.not_to change { subgroup_association.reload.archived }
      end

      context 'when the project no longer exists' do
        let(:event) do
          ::Projects::ProjectArchivedEvent.new(data: {
            project_id: non_existing_record_id,
            namespace_id: group.id,
            root_namespace_id: group.id
          })
        end

        it 'writes nothing' do
          expect(Security::ScanProfileProject).not_to receive(:sync_archived_for)

          use_event
        end
      end
    end

    context 'with Namespaces::Groups::GroupArchivedEvent' do
      let(:event) do
        ::Namespaces::Groups::GroupArchivedEvent.new(data: {
          group_id: group.id,
          root_namespace_id: group.id
        })
      end

      before do
        group.namespace_settings.update!(archived: true)
      end

      it_behaves_like 'subscribes to event'

      it_behaves_like 'an idempotent worker' do
        it 'flags attached projects across the group and its subgroups as archived' do
          expect { perform_idempotent_work }
            .to change { association.reload.archived }.from(false).to(true)
            .and change { subgroup_association.reload.archived }.from(false).to(true)
        end
      end

      # Guards the `resolver:` narrowing: without it the job would load and update
      # every project in the group, not just the ones with a scan profile attached.
      it 'only considers projects that have a scan profile attached' do
        expect(Security::ScanProfileProject).to receive(:sync_archived_for) do |project_ids|
          expect(project_ids).to contain_exactly(project.id, project_in_subgroup.id)
        end

        use_event
      end

      it 'clears the flag when the group is no longer archived' do
        association.update!(archived: true)
        group.namespace_settings.update!(archived: false)

        expect { use_event }.to change { association.reload.archived }.from(true).to(false)
      end

      context 'when the group no longer exists' do
        let(:event) do
          ::Namespaces::Groups::GroupArchivedEvent.new(data: {
            group_id: non_existing_record_id,
            root_namespace_id: non_existing_record_id
          })
        end

        it 'writes nothing' do
          expect(Security::ScanProfileProject).not_to receive(:sync_archived_for)

          use_event
        end
      end
    end

    context 'with an event the worker does not subscribe to' do
      let(:event) do
        ::Projects::ProjectDeletedEvent.new(data: {
          project_id: project.id,
          namespace_id: group.id,
          root_namespace_id: group.id
        })
      end

      it 'writes nothing' do
        expect(Security::ScanProfileProject).not_to receive(:sync_archived_for)

        use_event
      end
    end
  end
end
