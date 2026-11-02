# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Namespaces::Stateful, feature_category: :groups_and_projects do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:namespace) { create(:namespace) }
  let_it_be(:states) { Namespace.states }

  describe 'enums' do
    subject { namespace }

    it { is_expected.to define_enum_for(:state).with_values(**states).without_instance_methods }
  end

  describe 'state classification constants' do
    it 'partitions all enum states between PROPAGATED_STATES and NON_PROPAGATED_STATES' do
      classified = described_class::PROPAGATED_STATES + described_class::NON_PROPAGATED_STATES

      expect(classified.sort).to eq(states.keys.map(&:to_sym).sort)
    end

    it 'has no overlap between PROPAGATED_STATES and NON_PROPAGATED_STATES' do
      overlap = described_class::PROPAGATED_STATES & described_class::NON_PROPAGATED_STATES

      expect(overlap).to be_empty
    end
  end

  describe '.with_state' do
    let_it_be(:archived_namespace) { create(:namespace, state: :archived) }
    let_it_be(:deletion_scheduled_namespace) { create(:namespace, state: :deletion_scheduled) }
    let_it_be(:ancestor_inherited_namespace) { create(:namespace, state: :ancestor_inherited) }

    it 'filters namespaces by a single state' do
      expect(Namespace.with_state(:archived)).to contain_exactly(archived_namespace)
    end

    it 'filters namespaces by multiple states' do
      expect(Namespace.with_state([:archived, :deletion_scheduled]))
        .to contain_exactly(archived_namespace, deletion_scheduled_namespace)
    end
  end

  describe '.overwrite_state_in_batch' do
    let_it_be_with_reload(:overwritable) { create(:namespace, state: :ancestor_inherited) }
    let_it_be_with_reload(:higher_precedence) { create(:namespace, state: :deletion_scheduled) }
    let_it_be_with_reload(:out_of_batch) { create(:namespace, state: :ancestor_inherited) }

    it 'moves only rows in an overwritable state to the target state', :aggregate_failures do
      Namespace.overwrite_state_in_batch(
        [overwritable.id, higher_precedence.id],
        from: [:ancestor_inherited],
        to: :archived
      )

      expect(overwritable.reload.state).to eq('archived')
      expect(higher_precedence.reload.state).to eq('deletion_scheduled')
    end

    it 'does not touch rows outside the given ids' do
      Namespace.overwrite_state_in_batch([overwritable.id], from: [:ancestor_inherited], to: :archived)

      expect(out_of_batch.reload.state).to eq('ancestor_inherited')
    end

    it 'returns the number of updated rows' do
      updated = Namespace.overwrite_state_in_batch(
        [overwritable.id, higher_precedence.id],
        from: [:ancestor_inherited],
        to: :archived
      )

      expect(updated).to eq(1)
    end

    it 'returns 0 and preserves nothing when no rows are in an overwritable state', :aggregate_failures do
      updated = Namespace.overwrite_state_in_batch(
        [higher_precedence.id], from: [:ancestor_inherited], to: :archived, mode: :preserve, preservation_key: 'archive'
      )

      expect(updated).to eq(0)
      expect(higher_precedence.reload.state).to eq('deletion_scheduled')
      expect(higher_precedence.reload.state_metadata).not_to have_key('preserved_states')
    end

    it 'raises for an unknown mode', :aggregate_failures do
      expect do
        Namespace.overwrite_state_in_batch([overwritable.id], from: [:ancestor_inherited], to: :archived, mode: :bogus)
      end.to raise_error(ArgumentError, 'Unknown overwrite mode: :bogus')

      expect(overwritable.reload.state).to eq('ancestor_inherited')
    end

    def preserved_states(namespace)
      namespace.reload.state_metadata['preserved_states']
    end

    context 'with the preserve mode' do
      subject(:overwrite) do
        Namespace.overwrite_state_in_batch(
          [overwritable.id, higher_precedence.id],
          from: [:ancestor_inherited, :archived],
          to: :deletion_scheduled,
          mode: :preserve,
          preservation_key: 'schedule_deletion'
        )
      end

      it 'preserves the previous state of overwritten rows only', :aggregate_failures do
        overwrite

        expect(preserved_states(overwritable)).to eq('schedule_deletion' => 'ancestor_inherited')
        expect(preserved_states(higher_precedence)).to be_nil
      end

      it 'keeps other preserved states' do
        overwritable.namespace_details.update!(state_metadata: { preserved_states: { schedule_transfer: 'archived' } })

        overwrite

        expect(preserved_states(overwritable))
          .to eq('schedule_transfer' => 'archived', 'schedule_deletion' => 'ancestor_inherited')
      end

      it 'creates a missing namespace_details row' do
        Namespace::Detail.where(namespace_id: overwritable.id).delete_all

        overwrite

        expect(Namespace::Detail.find(overwritable.id).state_metadata['preserved_states'])
          .to eq('schedule_deletion' => 'ancestor_inherited')
      end

      it 'does not create a namespace_details row for rows it does not overwrite' do
        Namespace::Detail.where(namespace_id: higher_precedence.id).delete_all

        overwrite

        expect(Namespace::Detail.exists?(higher_precedence.id)).to be(false)
      end
    end

    context 'with the clear mode' do
      let(:metadata) { { preserved_states: { schedule_deletion: 'archived' } } }

      subject(:overwrite) do
        Namespace.overwrite_state_in_batch(
          [overwritable.id, higher_precedence.id], from: [:archived], to: :ancestor_inherited, mode: :clear
        )
      end

      before do
        overwritable.update!(state: :archived)
        overwritable.namespace_details.update!(state_metadata: metadata)
        higher_precedence.namespace_details.update!(state_metadata: metadata)
      end

      it 'removes preserved states from overwritten rows only', :aggregate_failures do
        overwrite

        expect(overwritable.reload.state_metadata).not_to have_key('preserved_states')
        expect(preserved_states(higher_precedence)).to eq('schedule_deletion' => 'archived')
      end
    end

    context 'with the restore mode' do
      let_it_be_with_reload(:preserved_archived) { create(:namespace, state: :deletion_scheduled) }
      let_it_be_with_reload(:preserved_inherited) { create(:namespace, state: :deletion_scheduled) }
      let_it_be_with_reload(:nothing_preserved) { create(:namespace, state: :deletion_scheduled) }
      let_it_be_with_reload(:not_overwritable) { create(:namespace, state: :maintenance) }

      let(:to) { :ancestor_inherited }

      subject(:restore) do
        Namespace.overwrite_state_in_batch(
          [preserved_archived, preserved_inherited, nothing_preserved, not_overwritable].map(&:id),
          from: [:archived, :deletion_scheduled],
          to: to,
          mode: :restore,
          preservation_key: 'schedule_deletion'
        )
      end

      def preserve(namespace, states)
        namespace.namespace_details.update!(state_metadata: { preserved_states: states })
      end

      before do
        preserve(preserved_archived, { schedule_deletion: 'archived' })
        preserve(preserved_inherited, { schedule_deletion: 'ancestor_inherited' })
        preserve(not_overwritable, { schedule_deletion: 'archived' })
      end

      it 'restores each row to its preserved state, falling back to the target', :aggregate_failures do
        restore

        expect(preserved_archived.reload.state).to eq('archived')
        expect(preserved_inherited.reload.state).to eq('ancestor_inherited')
        expect(nothing_preserved.reload.state).to eq('ancestor_inherited')
        expect(not_overwritable.reload.state).to eq('maintenance')
      end

      it 'returns the number of restored rows' do
        expect(restore).to eq(3)
      end

      context 'when the preserved state has lower precedence than the target' do
        let(:to) { :archived }

        it 'restores to the target instead', :aggregate_failures do
          restore

          expect(preserved_archived.reload.state).to eq('archived')
          expect(preserved_inherited.reload.state).to eq('archived')
          expect(nothing_preserved.reload.state).to eq('archived')
        end
      end

      context 'when a row is already in its restored state' do
        let_it_be_with_reload(:already_archived) { create(:namespace, state: :archived) }

        subject(:restore) do
          Namespace.overwrite_state_in_batch(
            [already_archived.id],
            from: [:archived, :deletion_scheduled],
            to: :archived,
            mode: :restore,
            preservation_key: 'schedule_deletion'
          )
        end

        it 'does not update the row', :aggregate_failures do
          updated = nil
          recorder = ActiveRecord::QueryRecorder.new { updated = restore }

          expect(recorder.log).not_to include(a_string_matching(/UPDATE "namespaces"/))
          expect(updated).to eq(0)
        end
      end

      it 'removes the restored preserved state from overwritten rows only', :aggregate_failures do
        restore

        expect(preserved_archived.reload.state_metadata).not_to have_key('preserved_states')
        expect(preserved_states(not_overwritable)).to eq('schedule_deletion' => 'archived')
      end
    end
  end

  describe 'zero handling' do
    describe 'state reading' do
      it 'treats 0 state as ancestor_inherited' do
        namespace.update_column(:state, 0)
        namespace.reload

        expect(namespace.state).to eq('ancestor_inherited')
        expect(namespace.state_name).to eq(:ancestor_inherited)
      end
    end

    describe 'transitions from ancestor_inherited' do
      where(:event, :to_state) do
        :archive           | :archived
        :schedule_deletion | :deletion_scheduled
        :start_deletion    | :deletion_in_progress
      end

      with_them do
        before do
          namespace.update_column(:state, 0)
          namespace.reload
        end

        it "transitions from 0 to #{params[:to_state]} on #{params[:event]}" do
          expect { namespace.public_send(event, transition_user: user) }
            .to change { namespace.state_name }
                  .from(:ancestor_inherited)
                  .to(to_state)
        end
      end
    end

    describe 'transitions back to ancestor_inherited write 0' do
      it 'writes 0 to the database when transitioning to ancestor_inherited' do
        namespace.update!(state: :archived)

        namespace.unarchive

        raw_state = Namespace.where(id: namespace.id).first.state_before_type_cast
        expect(raw_state).to eq(0)
      end
    end
  end

  describe 'state machine' do
    subject { namespace }

    it "declares all expected states" do
      is_expected.to have_states :ancestor_inherited, :archived, :deletion_scheduled,
        :creation_in_progress, :deletion_in_progress,
        :transfer_in_progress, :maintenance, :transfer_scheduled
    end

    it 'has ancestor_inherited as initial state' do
      expect(namespace.state_name).to eq(:ancestor_inherited)
    end

    describe 'state values' do
      Namespace.states.each_key do |state_name|
        it { is_expected.to have_state state_name.to_sym, value: state_name }
      end
    end

    describe 'event handling' do
      it { is_expected.to handle_events :archive, when: :ancestor_inherited }
      it { is_expected.to handle_events :unarchive, when: :archived }
      it { is_expected.to handle_events :unarchive, when: :ancestor_inherited }
      it { is_expected.to handle_events :schedule_deletion, when: :ancestor_inherited }
      it { is_expected.to handle_events :schedule_deletion, when: :archived }
      it { is_expected.to handle_events :start_deletion, when: :ancestor_inherited }
      it { is_expected.to handle_events :start_deletion, when: :archived }
      it { is_expected.to handle_events :start_deletion, when: :deletion_scheduled }
      it { is_expected.to handle_events :start_deletion, when: :creation_in_progress }
      it { is_expected.to handle_events :start_deletion, when: :transfer_in_progress }
      it { is_expected.to handle_events :start_deletion, when: :transfer_scheduled }
      it { is_expected.to handle_events :start_deletion, when: :maintenance }
      it { is_expected.to handle_events :reschedule_deletion, when: :deletion_in_progress }
      it { is_expected.to handle_events :reschedule_deletion, when: :ancestor_inherited }
      it { is_expected.to handle_events :cancel_deletion, when: :deletion_scheduled }
      it { is_expected.to handle_events :cancel_deletion, when: :deletion_in_progress }
      it { is_expected.to handle_events :cancel_deletion, when: :ancestor_inherited }
      it { is_expected.to handle_events :schedule_transfer, when: :ancestor_inherited }
      it { is_expected.to handle_events :schedule_transfer, when: :archived }
      it { is_expected.to handle_events :start_transfer, when: :transfer_scheduled }
      it { is_expected.to handle_events :complete_transfer, when: :transfer_in_progress }
      it { is_expected.to handle_events :cancel_transfer, when: :transfer_scheduled }
      it { is_expected.to handle_events :cancel_transfer, when: :transfer_in_progress }
      it { is_expected.to reject_events :archive, when: :archived }
      it { is_expected.to reject_events :schedule_deletion, when: :deletion_scheduled }
      it { is_expected.to reject_events :schedule_transfer, when: :transfer_scheduled }
      it { is_expected.to reject_events :start_transfer, when: :transfer_in_progress }
    end

    describe 'transitions' do
      where(:event, :from_state, :to_state) do
        :archive             | :ancestor_inherited   | :archived
        :unarchive           | :archived             | :ancestor_inherited
        :schedule_deletion   | :ancestor_inherited   | :deletion_scheduled
        :schedule_deletion   | :archived             | :deletion_scheduled
        :start_deletion      | :ancestor_inherited   | :deletion_in_progress
        :start_deletion      | :archived             | :deletion_in_progress
        :start_deletion      | :deletion_scheduled   | :deletion_in_progress
        :start_deletion      | :creation_in_progress | :deletion_in_progress
        :start_deletion      | :transfer_in_progress | :deletion_in_progress
        :start_deletion      | :transfer_scheduled   | :deletion_in_progress
        :start_deletion      | :maintenance          | :deletion_in_progress
        :reschedule_deletion | :deletion_in_progress | :deletion_scheduled
        :reschedule_deletion | :ancestor_inherited   | :deletion_scheduled
        :schedule_transfer   | :ancestor_inherited   | :transfer_scheduled
        :schedule_transfer   | :archived             | :transfer_scheduled
        :start_transfer      | :transfer_scheduled   | :transfer_in_progress
        :complete_transfer   | :transfer_in_progress | :ancestor_inherited
        :cancel_transfer     | :transfer_scheduled   | :ancestor_inherited
        :cancel_transfer     | :transfer_in_progress | :ancestor_inherited
      end

      with_them do
        before do
          namespace.state = from_state
        end

        it "transitions from #{params[:from_state]} to #{params[:to_state]} on #{params[:event]}" do
          expect { namespace.public_send(event, transition_user: user) }
            .to change { namespace.state_name }
                  .from(from_state)
                  .to(to_state)
        end

        it 'updates state_metadata with user and timestamp' do
          freeze_time do
            namespace.public_send(event, transition_user: user)
            metadata = namespace.namespace_details.reload.state_metadata

            expect(metadata).to include(
              'last_changed_by_user_id' => user.id,
              'last_error' => nil
            )
            expect(metadata['last_updated_at']).to be_present
          end
        end
      end

      context 'for transitions with state preservation' do
        where(:event, :from_state, :preserve_event, :preserved_state) do
          :cancel_deletion     | :deletion_scheduled   | :schedule_deletion | :ancestor_inherited
          :cancel_deletion     | :deletion_scheduled   | :schedule_deletion | :archived
          :cancel_deletion     | :deletion_in_progress | :schedule_deletion | :ancestor_inherited
          :cancel_deletion     | :deletion_in_progress | :schedule_deletion | :archived
          :reschedule_deletion | :deletion_in_progress | :start_deletion    | :ancestor_inherited
          :reschedule_deletion | :deletion_in_progress | :start_deletion    | :archived
          :reschedule_deletion | :deletion_in_progress | :start_deletion    | :deletion_scheduled
          :complete_transfer   | :transfer_in_progress | :schedule_transfer | :ancestor_inherited
          :complete_transfer   | :transfer_in_progress | :schedule_transfer | :archived
          :cancel_transfer     | :transfer_scheduled   | :schedule_transfer | :ancestor_inherited
          :cancel_transfer     | :transfer_scheduled   | :schedule_transfer | :archived
          :cancel_transfer     | :transfer_in_progress | :schedule_transfer | :archived
        end

        with_them do
          before do
            namespace.update!(state: from_state)
            namespace.namespace_details.update!(
              state_metadata: {
                preserved_states: {
                  preserve_event.to_s => preserved_state.to_s
                }
              }
            )
          end

          it "transitions from #{params[:from_state]} to #{params[:preserved_state]} on #{params[:event]}" do
            expect { namespace.public_send(event, transition_user: user) }
              .to change { namespace.state_name }
                    .from(from_state)
                    .to(preserved_state)
          end
        end
      end
    end

    describe 'system-triggered transitions' do
      it 'updates state_metadata without user' do
        freeze_time do
          namespace.archive
          metadata = namespace.namespace_details.reload.state_metadata

          expect(metadata).to include(
            'last_changed_by_user_id' => nil,
            'last_error' => nil
          )
          expect(metadata['last_updated_at']).to be_present
        end
      end
    end

    describe 'cache invalidation on archive transitions' do
      context 'when namespace is a group' do
        let_it_be_with_reload(:group) { create(:group) }

        it 'expires namespace descendants cache when archiving' do
          expect(Namespaces::Descendants).to receive(:expire_recursive_for).with(group)

          group.archive(transition_user: user)
        end

        it 'expires namespace descendants cache when unarchiving' do
          group.update!(state: :archived)

          expect(Namespaces::Descendants).to receive(:expire_recursive_for).with(group)

          group.unarchive(transition_user: user)
        end
      end

      context 'when namespace is a project namespace' do
        let_it_be_with_reload(:project) { create(:project) }
        # `freeze: false` is required in this spec: one or more `let_it_be` subjects
        # cannot be frozen by default (deep_freeze traversal failure, a non-AR
        # subject, or an in-memory mutation that survives reload/refind). Do not
        # drop these opt-outs or convert them to `let_it_be_with_reload`/`refind`
        # (see gitlab-org/gitlab#602925).
        let_it_be(:project_namespace, freeze: false) { project.project_namespace }

        it 'expires namespace descendants cache for the parent when archiving' do
          expect(Namespaces::Descendants).to receive(:expire_for).with([project_namespace.parent_id])

          project_namespace.archive(transition_user: user)
        end

        it 'expires namespace descendants cache for the parent when unarchiving' do
          project_namespace.update!(state: :archived)

          expect(Namespaces::Descendants).to receive(:expire_for).with([project_namespace.parent_id])

          project_namespace.unarchive(transition_user: user)
        end
      end

      context 'when namespace is a user namespace' do
        it 'does not expire namespace descendants cache' do
          user_namespace = create(:user_namespace)
          user_namespace.update!(state: :archived)

          expect(Namespaces::Descendants).not_to receive(:expire_for)
          expect(Namespaces::Descendants).not_to receive(:expire_recursive_for)

          user_namespace.unarchive(transition_user: user)
        end
      end

      context 'when transitioning from archived via non-archive events' do
        let_it_be_with_reload(:group) { create(:group) }

        it 'expires cache when scheduling deletion from archived state' do
          group.update!(state: :archived)

          expect(Namespaces::Descendants).to receive(:expire_recursive_for).with(group)

          group.schedule_deletion(transition_user: user)
        end

        it 'expires cache when cancel_deletion restores to archived' do
          group.update!(state: :deletion_scheduled)
          group.namespace_details.update!(
            state_metadata: { preserved_states: { 'schedule_deletion' => 'archived' } }
          )

          expect(Namespaces::Descendants).to receive(:expire_recursive_for).with(group)

          group.cancel_deletion(transition_user: user)
        end
      end
    end

    describe 'rejected transitions' do
      where(:event, :current_state) do
        :archive             | :archived
        :archive             | :deletion_scheduled
        :archive             | :deletion_in_progress
        :archive             | :creation_in_progress
        :archive             | :transfer_in_progress
        :archive             | :transfer_scheduled
        :archive             | :maintenance
        :unarchive           | :deletion_scheduled
        :unarchive           | :deletion_in_progress
        :unarchive           | :creation_in_progress
        :unarchive           | :transfer_in_progress
        :unarchive           | :transfer_scheduled
        :unarchive           | :maintenance
        :schedule_deletion   | :deletion_scheduled
        :schedule_deletion   | :deletion_in_progress
        :schedule_deletion   | :creation_in_progress
        :schedule_deletion   | :transfer_in_progress
        :schedule_deletion   | :transfer_scheduled
        :schedule_deletion   | :maintenance
        :reschedule_deletion | :archived
        :reschedule_deletion | :deletion_scheduled
        :reschedule_deletion | :creation_in_progress
        :reschedule_deletion | :transfer_in_progress
        :reschedule_deletion | :transfer_scheduled
        :reschedule_deletion | :maintenance
        :cancel_deletion     | :archived
        :cancel_deletion     | :creation_in_progress
        :cancel_deletion     | :transfer_in_progress
        :cancel_deletion     | :transfer_scheduled
        :cancel_deletion     | :maintenance
        :schedule_transfer   | :deletion_scheduled
        :schedule_transfer   | :deletion_in_progress
        :schedule_transfer   | :creation_in_progress
        :schedule_transfer   | :transfer_in_progress
        :schedule_transfer   | :transfer_scheduled
        :schedule_transfer   | :maintenance
        :start_transfer      | :ancestor_inherited
        :start_transfer      | :archived
        :start_transfer      | :deletion_scheduled
        :start_transfer      | :deletion_in_progress
        :start_transfer      | :creation_in_progress
        :start_transfer      | :transfer_in_progress
        :start_transfer      | :maintenance
        :complete_transfer   | :ancestor_inherited
        :complete_transfer   | :archived
        :complete_transfer   | :deletion_scheduled
        :complete_transfer   | :deletion_in_progress
        :complete_transfer   | :creation_in_progress
        :complete_transfer   | :transfer_scheduled
        :complete_transfer   | :maintenance
        :cancel_transfer     | :ancestor_inherited
        :cancel_transfer     | :archived
        :cancel_transfer     | :deletion_scheduled
        :cancel_transfer     | :deletion_in_progress
        :cancel_transfer     | :creation_in_progress
        :cancel_transfer     | :maintenance
      end

      with_them do
        it "does not transition from #{params[:current_state]} on #{params[:event]}" do
          namespace.state = current_state

          expect { namespace.public_send(event, transition_user: user) }
            .not_to change { namespace.state_name }
        end
      end
    end

    describe 'state propagation outbox' do
      let_it_be_with_reload(:namespace) { create(:group) }
      let(:outbox_rows) { Namespaces::StatePropagation.where(namespace_id: namespace.id) }

      before do
        allow(Namespaces::StatePropagationWorker).to receive(:perform_async)
      end

      shared_examples 'creates a pending outbox record and enqueues the worker' do
        it 'creates a pending outbox record and enqueues the worker after commit' do
          expect { namespace.public_send(event, transition_user: user) }.to change { outbox_rows.count }.by(1)

          expect(outbox_rows.last).to have_attributes(
            source_state: source_state.to_s,
            target_state: to_state.to_s,
            status: 'pending'
          )
          expect(Namespaces::StatePropagationWorker)
            .to have_received(:perform_async).with(namespace.id, to_state.to_s).once
        end
      end

      context 'when transitioning to a propagated state' do
        where(:event, :from_state, :to_state, :source_state) do
          :archive             | :ancestor_inherited   | :archived           | :ancestor_inherited
          :unarchive           | :archived             | :ancestor_inherited | :archived
          :schedule_deletion   | :ancestor_inherited   | :deletion_scheduled | :ancestor_inherited
          :schedule_deletion   | :archived             | :deletion_scheduled | :archived
          :cancel_deletion     | :deletion_scheduled   | :ancestor_inherited | :deletion_scheduled
          :reschedule_deletion | :deletion_in_progress | :deletion_scheduled | :deletion_in_progress
          :reschedule_deletion | :ancestor_inherited   | :deletion_scheduled | :ancestor_inherited
        end

        with_them do
          before do
            namespace.update!(state: from_state)
          end

          it_behaves_like 'creates a pending outbox record and enqueues the worker'
        end
      end

      context 'when transitioning with a preserved state' do
        # rubocop:disable Layout/LineLength -- table rows
        where(:event, :from_state, :preserve_event, :preserved_state, :to_state, :source_state) do
          :cancel_deletion     | :deletion_scheduled   | :schedule_deletion | :archived           | :archived           | :deletion_scheduled
          :cancel_deletion     | :deletion_in_progress | :start_deletion    | :deletion_scheduled | :ancestor_inherited | :deletion_scheduled
        end
        # rubocop:enable Layout/LineLength

        with_them do
          before do
            namespace.update!(state: from_state)
            namespace.namespace_details.update!(
              state_metadata: { preserved_states: { preserve_event.to_s => preserved_state.to_s } }
            )
          end

          it_behaves_like 'creates a pending outbox record and enqueues the worker'
        end
      end

      context 'when the propagation worker runs inline' do
        let_it_be_with_reload(:parent) { create(:group) }
        let_it_be_with_reload(:child) { create(:group, parent: parent) }

        before do
          allow(Namespaces::StatePropagationWorker).to receive(:perform_async) do |namespace_id, target_state|
            Namespaces::StatePropagationWorker.new.perform(namespace_id, target_state)
          end
        end

        it 'restores descendants that inherited the scheduled deletion when deletion is cancelled while in progress' do
          parent.schedule_deletion(transition_user: user)
          expect(child.reload.state_name).to eq(:deletion_scheduled)

          parent.start_deletion(transition_user: user)
          parent.cancel_deletion(transition_user: user)

          expect(child.reload.state_name).to eq(:ancestor_inherited)
        end

        it 'schedules descendants for deletion when deletion is rescheduled without a preserved state' do
          parent.update!(state: :deletion_in_progress)

          parent.reschedule_deletion(transition_user: user)

          expect(child.reload.state_name).to eq(:deletion_scheduled)
        end

        it 'preserves the archived state of descendants when an archived parent is scheduled for deletion' do
          parent.archive(transition_user: user)
          expect(child.reload.state_name).to eq(:archived)

          parent.schedule_deletion(transition_user: user)

          expect(child.reload.state_name).to eq(:deletion_scheduled)
          expect(child.reload.state_metadata['preserved_states']).to eq('schedule_deletion' => 'archived')
        end

        it 'clears the preserved states of descendants when the parent is unarchived' do
          parent.archive(transition_user: user)
          child.namespace_details.update!(state_metadata: { preserved_states: { 'schedule_deletion' => 'archived' } })

          parent.unarchive(transition_user: user)

          expect(child.reload.state_name).to eq(:ancestor_inherited)
          expect(child.reload.state_metadata['preserved_states']).to be_nil
        end
      end

      context 'when the transition does not change the state descendants inherit' do
        where(:event, :from_state, :preserve_event, :preserved_state) do
          :reschedule_deletion | :deletion_in_progress | :start_deletion    | :deletion_scheduled
          :reschedule_deletion | :deletion_in_progress | :start_deletion    | :archived
          :reschedule_deletion | :deletion_in_progress | :start_deletion    | :ancestor_inherited
          :complete_transfer   | :transfer_in_progress | :schedule_transfer | :ancestor_inherited
          :complete_transfer   | :transfer_in_progress | :schedule_transfer | :archived
          :cancel_transfer     | :transfer_scheduled   | :schedule_transfer | :ancestor_inherited
          :cancel_transfer     | :transfer_in_progress | :schedule_transfer | :archived
          :cancel_deletion     | :deletion_in_progress | nil                | nil
          :complete_transfer   | :transfer_in_progress | nil                | nil
          :cancel_transfer     | :transfer_scheduled   | nil                | nil
          :cancel_transfer     | :transfer_in_progress | nil                | nil
        end

        with_them do
          before do
            namespace.update!(state: from_state)

            if preserve_event
              namespace.namespace_details.update!(
                state_metadata: { preserved_states: { preserve_event.to_s => preserved_state.to_s } }
              )
            end
          end

          it 'transitions without creating an outbox record or enqueueing the worker' do
            expect { namespace.public_send(event, transition_user: user) }
              .to change { namespace.state_name }
              .and not_change { outbox_rows.count }

            expect(Namespaces::StatePropagationWorker).not_to have_received(:perform_async)
          end
        end
      end

      context 'when transitioning to a non-propagated state' do
        where(:event, :from_state) do
          :start_deletion    | :ancestor_inherited
          :schedule_transfer | :ancestor_inherited
          :start_transfer    | :transfer_scheduled
        end

        with_them do
          before do
            namespace.update!(state: from_state)
          end

          it 'does not create an outbox record or enqueue the worker' do
            expect { namespace.public_send(event, transition_user: user) }.not_to change { outbox_rows.count }

            expect(Namespaces::StatePropagationWorker).not_to have_received(:perform_async)
          end
        end
      end

      context 'when the transition is a loopback' do
        before do
          stub_feature_flags(remove_group_ancestor_inherited_transitions: false)
        end

        where(event: %i[unarchive cancel_deletion])

        with_them do
          it 'does not create an outbox record or enqueue the worker' do
            expect { namespace.public_send(event, transition_user: user) }.not_to change { outbox_rows.count }

            expect(namespace.state_name).to eq(:ancestor_inherited)
            expect(Namespaces::StatePropagationWorker).not_to have_received(:perform_async)
          end
        end
      end

      context 'when namespace is a project namespace' do
        let_it_be_with_reload(:project) { create(:project) }
        let(:project_namespace) { project.project_namespace }

        it 'does not create an outbox record or enqueue the worker' do
          expect { project_namespace.archive(transition_user: user) }
            .not_to change { Namespaces::StatePropagation.where(namespace_id: project_namespace.id).count }

          expect(project_namespace.state_name).to eq(:archived)
          expect(Namespaces::StatePropagationWorker).not_to have_received(:perform_async)
        end
      end

      context 'when the namespace_state_propagation_outbox flag is disabled' do
        before do
          stub_feature_flags(namespace_state_propagation_outbox: false)
        end

        it 'transitions without creating an outbox record or enqueueing the worker' do
          expect { namespace.archive(transition_user: user) }.not_to change { outbox_rows.count }

          expect(namespace.reload.state_name).to eq(:archived)
          expect(Namespaces::StatePropagationWorker).not_to have_received(:perform_async)
        end
      end

      context 'when the flag is enabled only for the root ancestor of a subgroup' do
        let_it_be(:root_group) { create(:group) }
        let_it_be_with_reload(:subgroup) { create(:group, parent: root_group) }

        before do
          stub_feature_flags(namespace_state_propagation_outbox: root_group)
        end

        it 'creates an outbox record for the subgroup' do
          expect { subgroup.archive(transition_user: user) }
            .to change { Namespaces::StatePropagation.where(namespace_id: subgroup.id).count }.by(1)
        end
      end

      context 'when an in-flight outbox record exists for the same target state' do
        where(status: %i[pending processing])

        with_them do
          before do
            create(:namespace_state_propagation, status, namespace: namespace,
              source_state: :ancestor_inherited, target_state: :archived)
          end

          it 'transitions without creating a second record and still enqueues the worker' do
            expect { namespace.archive(transition_user: user) }.not_to change { outbox_rows.count }

            expect(namespace.reload.state_name).to eq(:archived)
            expect(Namespaces::StatePropagationWorker)
              .to have_received(:perform_async).with(namespace.id, 'archived').once
          end
        end
      end

      context 'when the surrounding transaction is rolled back' do
        it 'does not persist the outbox record or enqueue the worker' do
          Namespace.transaction do
            namespace.archive(transition_user: user)
            expect(outbox_rows.count).to eq(1)

            raise ActiveRecord::Rollback
          end

          expect(namespace.reload.state_name).to eq(:ancestor_inherited)
          expect(outbox_rows).to be_empty
          expect(Namespaces::StatePropagationWorker).not_to have_received(:perform_async)
        end
      end

      context 'when the transition fails after the outbox record is inserted' do
        it 'rolls back the outbox record together with the state change' do
          allow(Namespaces::StatePropagation).to receive(:insert).and_wrap_original do |original, *args, **kwargs|
            original.call(*args, **kwargs)
            raise StandardError, 'boom'
          end

          expect { namespace.archive(transition_user: user) }.to raise_error(StandardError, 'boom')

          expect(namespace.reload.state_name).to eq(:ancestor_inherited)
          expect(outbox_rows).to be_empty
          expect(Namespaces::StatePropagationWorker).not_to have_received(:perform_async)
        end
      end

      it 'does not enqueue the worker before the transaction commits' do
        Namespace.transaction do
          namespace.archive(transition_user: user)

          expect(outbox_rows.count).to eq(1)
          expect(Namespaces::StatePropagationWorker).not_to have_received(:perform_async)
        end

        expect(Namespaces::StatePropagationWorker).to have_received(:perform_async).with(namespace.id, 'archived')
      end
    end
  end
end
