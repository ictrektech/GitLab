# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::DependencyFirewall::ScheduleGroupPreventedStatsRefreshWorker, feature_category: :dependency_firewall do
  let_it_be(:old_root) { create(:group) }
  let_it_be(:old_sub) { create(:group, parent: old_root) }
  let_it_be(:new_root) { create(:group) }
  let_it_be(:new_sub) { create(:group, parent: new_root) }
  let_it_be(:project) { create(:project, group: new_sub) }

  let(:refresh_worker) { Security::DependencyFirewall::RefreshGroupPreventedStatsWorker }

  let(:scheduled_group_ids) { [] }

  before do
    stub_feature_flags(dependency_firewall_group_prevented_stats: [old_root, new_root])
    allow(refresh_worker).to receive(:schedule) { |group_ids| scheduled_group_ids.concat(group_ids) }
  end

  describe 'event subscriptions' do
    context 'with Projects::ProjectTransferedEvent' do
      it_behaves_like 'subscribes to event' do
        let(:event) do
          Projects::ProjectTransferedEvent.new(data: {
            project_id: project.id,
            old_namespace_id: old_sub.id,
            old_root_namespace_id: old_root.id,
            new_namespace_id: new_sub.id,
            new_root_namespace_id: new_root.id
          })
        end
      end
    end

    context 'with Projects::ProjectDeletedEvent' do
      it_behaves_like 'subscribes to event' do
        let(:event) do
          Projects::ProjectDeletedEvent.new(data: {
            project_id: project.id,
            namespace_id: new_sub.id,
            root_namespace_id: new_root.id
          })
        end
      end
    end

    context 'with Groups::GroupTransferedEvent' do
      it_behaves_like 'subscribes to event' do
        let(:event) do
          Groups::GroupTransferedEvent.new(data: {
            group_id: new_sub.id,
            old_root_namespace_id: old_root.id,
            new_root_namespace_id: new_root.id
          })
        end
      end
    end

    context 'with Groups::GroupDeletedEvent' do
      it_behaves_like 'subscribes to event' do
        let(:event) do
          Groups::GroupDeletedEvent.new(data: {
            group_id: non_existing_record_id,
            root_namespace_id: new_root.id,
            parent_namespace_id: new_sub.id
          })
        end
      end
    end

    context 'when the flag is off for every root in the event' do
      before do
        stub_feature_flags(dependency_firewall_group_prevented_stats: false)
      end

      it_behaves_like 'ignores the published event' do
        let(:event) do
          Projects::ProjectDeletedEvent.new(data: {
            project_id: project.id,
            namespace_id: new_sub.id,
            root_namespace_id: new_root.id
          })
        end
      end
    end
  end

  describe '.dispatch?' do
    subject(:dispatch?) { described_class.dispatch?(event) }

    let_it_be(:off_root) { create(:group) }

    context 'with Projects::ProjectTransferedEvent' do
      let(:event) do
        Projects::ProjectTransferedEvent.new(data: {
          project_id: project.id,
          old_namespace_id: old_root_id,
          old_root_namespace_id: old_root_id,
          new_namespace_id: new_root_id,
          new_root_namespace_id: new_root_id
        })
      end

      context 'when only the old root has the flag' do
        let(:old_root_id) { old_root.id }
        let(:new_root_id) { off_root.id }

        it { is_expected.to be(true) }
      end

      context 'when only the new root has the flag' do
        let(:old_root_id) { off_root.id }
        let(:new_root_id) { new_root.id }

        it { is_expected.to be(true) }
      end

      context 'when neither root has the flag' do
        let(:old_root_id) { off_root.id }
        let(:new_root_id) { off_root.id }

        it { is_expected.to be(false) }
      end
    end

    context 'with Groups::GroupTransferedEvent' do
      let(:event) do
        Groups::GroupTransferedEvent.new(data: {
          group_id: new_sub.id, old_root_namespace_id: off_root.id, new_root_namespace_id: new_root_id
        })
      end

      context 'when the new root has the flag' do
        let(:new_root_id) { new_root.id }

        it { is_expected.to be(true) }
      end

      context 'when neither root has the flag' do
        let(:new_root_id) { off_root.id }

        it { is_expected.to be(false) }
      end
    end

    context 'with Groups::GroupDeletedEvent' do
      let(:event) do
        Groups::GroupDeletedEvent.new(data: { group_id: non_existing_record_id, root_namespace_id: root_id })
      end

      context 'when the root has the flag' do
        let(:root_id) { new_root.id }

        it { is_expected.to be(true) }
      end

      context 'when the root does not have the flag' do
        let(:root_id) { off_root.id }

        it { is_expected.to be(false) }
      end
    end

    context 'with Projects::ProjectDeletedEvent' do
      context 'when the root does not have the flag' do
        let(:event) do
          Projects::ProjectDeletedEvent.new(data: {
            project_id: project.id, namespace_id: off_root.id, root_namespace_id: off_root.id
          })
        end

        it { is_expected.to be(false) }
      end

      context 'when the event has no root namespace id' do
        let(:event) do
          Projects::ProjectDeletedEvent.new(data: { project_id: project.id, namespace_id: new_sub.id })
        end

        it { is_expected.to be(false) }
      end
    end
  end

  describe '#handle_event' do
    subject(:handle_event) { described_class.new.handle_event(event) }

    context 'with Projects::ProjectTransferedEvent' do
      let(:event) do
        Projects::ProjectTransferedEvent.new(data: {
          project_id: project.id,
          old_namespace_id: old_sub.id,
          old_root_namespace_id: old_root.id,
          new_namespace_id: new_sub.id,
          new_root_namespace_id: new_root.id
        })
      end

      it 'schedules the ancestors of the old and the new namespace' do
        handle_event

        expect(scheduled_group_ids).to contain_exactly(old_root.id, old_sub.id, new_root.id, new_sub.id)
      end

      it 'schedules nothing when the flag is disabled' do
        stub_feature_flags(dependency_firewall_group_prevented_stats: false)

        handle_event

        expect(scheduled_group_ids).to be_empty
      end

      it 'ignores a namespace that does not exist and a personal namespace' do
        personal_namespace = create(:user, :with_namespace).namespace
        event = Projects::ProjectTransferedEvent.new(data: {
          project_id: project.id,
          old_namespace_id: personal_namespace.id,
          old_root_namespace_id: personal_namespace.id,
          new_namespace_id: non_existing_record_id,
          new_root_namespace_id: non_existing_record_id
        })

        expect { described_class.new.handle_event(event) }.not_to raise_error
        expect(scheduled_group_ids).to be_empty
      end

      it 'schedules an ancestor shared by both namespaces once' do
        event = Projects::ProjectTransferedEvent.new(data: {
          project_id: project.id,
          old_namespace_id: new_sub.id, old_root_namespace_id: new_root.id,
          new_namespace_id: new_root.id, new_root_namespace_id: new_root.id
        })

        described_class.new.handle_event(event)

        expect(scheduled_group_ids).to contain_exactly(new_root.id, new_sub.id)
      end
    end

    context 'with Projects::ProjectDeletedEvent' do
      let(:event) do
        Projects::ProjectDeletedEvent.new(data: {
          project_id: project.id,
          namespace_id: new_sub.id,
          root_namespace_id: new_root.id
        })
      end

      it 'schedules the ancestors of the project namespace' do
        handle_event

        expect(scheduled_group_ids).to contain_exactly(new_root.id, new_sub.id)
      end

      it 'ignores a namespace that does not exist' do
        event = Projects::ProjectDeletedEvent.new(data: {
          project_id: project.id,
          namespace_id: non_existing_record_id
        })

        expect { described_class.new.handle_event(event) }.not_to raise_error
        expect(scheduled_group_ids).to be_empty
      end
    end

    context 'with Groups::GroupTransferedEvent' do
      let(:event) do
        Groups::GroupTransferedEvent.new(data: {
          group_id: new_sub.id,
          old_root_namespace_id: old_root.id,
          new_root_namespace_id: new_root.id
        })
      end

      it 'schedules the moved group, its new ancestors and the old root' do
        handle_event

        expect(scheduled_group_ids).to contain_exactly(old_root.id, new_root.id, new_sub.id)
      end

      context 'when only the old root has the flag' do
        before do
          stub_feature_flags(dependency_firewall_group_prevented_stats: old_root)
        end

        it 'schedules only the old root' do
          handle_event

          expect(scheduled_group_ids).to contain_exactly(old_root.id)
        end
      end
    end

    context 'with Groups::GroupDeletedEvent' do
      it 'schedules the ancestors of the parent group' do
        event = Groups::GroupDeletedEvent.new(data: {
          group_id: non_existing_record_id,
          root_namespace_id: new_root.id,
          parent_namespace_id: new_sub.id
        })

        described_class.new.handle_event(event)

        expect(scheduled_group_ids).to contain_exactly(new_root.id, new_sub.id)
      end

      it 'schedules nothing when the deleted group had no parent' do
        event = Groups::GroupDeletedEvent.new(data: {
          group_id: non_existing_record_id,
          root_namespace_id: non_existing_record_id
        })

        expect { described_class.new.handle_event(event) }.not_to raise_error
        expect(scheduled_group_ids).to be_empty
      end
    end

    context 'with an event the worker does not handle' do
      let(:event) do
        Projects::ProjectCreatedEvent.new(data: {
          project_id: project.id, namespace_id: new_sub.id, root_namespace_id: new_root.id
        })
      end

      it 'schedules nothing' do
        handle_event

        expect(scheduled_group_ids).to be_empty
      end
    end
  end
end
