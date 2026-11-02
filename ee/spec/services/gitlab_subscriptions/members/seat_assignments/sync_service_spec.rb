# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSubscriptions::Members::SeatAssignments::SyncService, feature_category: :seat_cost_management do
  describe '#execute' do
    let_it_be(:user) { create(:user) }
    let_it_be(:root_namespace) { create(:group) }

    context 'when on saas', :saas do
      it 'returns success response' do
        result = described_class.new([user.id], root_namespace).execute

        expect(result).to be_success
      end

      context 'when the user has a membership in the namespace hierarchy' do
        before_all do
          root_namespace.add_developer(user)
        end

        context 'when the user has an existing seat assignment' do
          let!(:existing_seat_assignment) do
            create(:gitlab_subscription_seat_assignment,
              user: user,
              namespace: root_namespace,
              organization_id: root_namespace.organization_id
            )
          end

          it 'does not create a new seat assignment' do
            expect { described_class.new([user.id], root_namespace).execute }
              .not_to change { GitlabSubscriptions::SeatAssignment.count }
          end

          it 'updates the existing seat assignment' do
            existing_seat_assignment.update!(seat_type: nil)

            described_class.new([user.id], root_namespace).execute

            expect(existing_seat_assignment.reload).to have_attributes(
              user: user,
              seat_type: 'base',
              namespace: root_namespace,
              organization_id: root_namespace.organization_id
            )
          end
        end

        context 'when the user does not have a seat assignment' do
          it 'creates a seat assignment' do
            expect { described_class.new([user.id], root_namespace).execute }
              .to change { GitlabSubscriptions::SeatAssignment.count }.by(1)
          end
        end
      end

      context 'when the user has no memberships in the namespace hierarchy' do
        context 'with an existing seat' do
          let!(:existing_seat_assignment) do
            create(:gitlab_subscription_seat_assignment,
              user: user,
              seat_type: :base,
              namespace: root_namespace,
              organization_id: root_namespace.organization_id
            )
          end

          it 'retains the seat assignment' do
            expect { described_class.new([user.id], root_namespace).execute }
              .not_to change { existing_seat_assignment.reload.seat_type }
          end

          it 'returns success response' do
            expect(described_class.new([user.id], root_namespace).execute).to be_success
          end
        end
      end

      context 'with multiple users' do
        let_it_be(:user_2) { create(:user) }

        it 'returns success response' do
          result = described_class.new([user.id, user_2.id], root_namespace).execute

          expect(result).to be_success
        end

        it 'handles seat assignments' do
          root_namespace.add_developer(user)
          create(:gitlab_subscription_seat_assignment, user: user, namespace: root_namespace)

          create(:gitlab_subscription_seat_assignment, user: user_2, namespace: root_namespace)

          user_3 = create(:user, organization: root_namespace.organization)
          subgroup = create(:group, parent: root_namespace)

          subgroup.add_maintainer(user_3)

          user_4 = create(:user)

          described_class.new([user.id, user_2.id, user_3.id, user_4.id], root_namespace).execute

          expect(GitlabSubscriptions::SeatAssignment.all.pluck(:user_id)).to contain_exactly(
            user.id,
            user_2.id,
            user_3.id
          )
        end
      end

      context 'when user_ids contains nil values' do
        it 'handles seat assignments for valid user ids only' do
          root_namespace.add_developer(user)

          expect { described_class.new([user.id, nil], root_namespace).execute }
            .to change { GitlabSubscriptions::SeatAssignment.count }.by(1)
        end
      end

      context 'when duplicate user ids are provided' do
        it 'handles seat assignment for the deduplicated user once' do
          root_namespace.add_developer(user)
          service = described_class.new([user.id, user.id], root_namespace)

          expect(service).to receive(:upsert_seat_assignments).with({ user.id => :base }).once

          service.execute
        end
      end

      context 'when user_ids is empty' do
        it 'returns success response' do
          expect(described_class.new([], root_namespace).execute).to be_success
        end
      end

      context 'when the namespace is not a root group' do
        let(:error_message) { 'Seat assignments require a root group namespace on GitLab.com' }

        it 'returns an error for a user namespace' do
          result = described_class.new([user.id], create(:user_namespace)).execute

          expect(result).to be_error
          expect(result.message).to eq(error_message)
        end

        it 'returns an error for a subgroup' do
          result = described_class.new([user.id], create(:group, parent: root_namespace)).execute

          expect(result).to be_error
          expect(result.message).to eq(error_message)
        end

        it 'does not create seat assignments for a user namespace' do
          user_namespace = create(:user_namespace)
          create(:project, namespace: user_namespace).add_developer(user)

          expect { described_class.new([user.id], user_namespace).execute }
            .not_to change { GitlabSubscriptions::SeatAssignment.count }
        end

        it 'does not create seat assignments for a subgroup' do
          subgroup = create(:group, parent: root_namespace)
          subgroup.add_developer(user)

          expect { described_class.new([user.id], subgroup).execute }
            .not_to change { GitlabSubscriptions::SeatAssignment.count }
        end
      end
    end

    context 'when on self-managed' do
      it 'returns nil' do
        expect(described_class.new([user.id], root_namespace).execute).to be_nil
      end
    end
  end
end
