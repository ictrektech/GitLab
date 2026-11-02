# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Scim::GroupSyncPatchService, feature_category: :system_access do
  let(:scim_group_uid) { SecureRandom.uuid }
  let(:service) { described_class.new(scim_group_uid: scim_group_uid, operations: operations) }

  describe '#execute' do
    context 'with add operation' do
      let_it_be(:user) { create(:user) }
      let_it_be(:identity) { create(:scim_identity, user: user, group: nil) }
      let(:operations) do
        [
          {
            op: 'Add',
            path: 'members',
            value: [{ value: identity.extern_uid }]
          }
        ]
      end

      it 'schedules the worker to add members' do
        expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
          .with(scim_group_uid, [user.id], 'add')

        service.execute
      end

      it 'returns success' do
        allow(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)

        result = service.execute

        expect(result).to be_success
      end

      context 'with case-insensitive operation' do
        let(:operations) do
          [
            {
              op: 'ADD',
              path: 'MEMBERS',
              value: [{ value: identity.extern_uid }]
            }
          ]
        end

        it 'schedules the worker correctly' do
          expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
            .with(scim_group_uid, [user.id], 'add')

          service.execute
        end
      end

      context 'with non-existent user identity' do
        let(:operations) do
          [
            {
              op: 'Add',
              path: 'members',
              value: [{ value: 'non-existent' }]
            }
          ]
        end

        it 'does not schedule the worker' do
          expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

          service.execute
        end
      end

      context 'with externalId operation' do
        let(:operations) do
          [
            {
              op: 'Add',
              path: 'externalId',
              value: 'new-external-id'
            }
          ]
        end

        it 'does not schedule the worker' do
          expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

          service.execute
        end

        it 'returns success' do
          result = service.execute

          expect(result).to be_success
        end
      end
    end

    context 'with remove operation' do
      let_it_be(:user) { create(:user) }
      let_it_be(:identity) { create(:scim_identity, user: user, group: nil) }
      let(:operations) do
        [
          {
            op: 'Remove',
            path: 'members',
            value: [{ value: identity.extern_uid }]
          }
        ]
      end

      it 'schedules the worker to remove members' do
        expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
          .with(scim_group_uid, [user.id], 'remove')

        service.execute
      end

      it 'returns success' do
        allow(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)

        result = service.execute

        expect(result).to be_success
      end

      context 'with filter expression path' do
        let(:operations) do
          [
            {
              op: 'Remove',
              path: "members[value eq \"#{identity.extern_uid}\"]"
            }
          ]
        end

        it 'schedules the worker to remove the member' do
          expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
            .with(scim_group_uid, [user.id], 'remove')

          service.execute
        end

        context 'with case-insensitive path' do
          let(:operations) do
            [
              {
                op: 'Remove',
                path: "Members[VALUE EQ \"#{identity.extern_uid}\"]"
              }
            ]
          end

          it 'schedules the worker to remove the member' do
            expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
              .with(scim_group_uid, [user.id], 'remove')

            service.execute
          end
        end

        context 'with non-existent user identity' do
          let(:operations) do
            [
              {
                op: 'Remove',
                path: 'members[value eq "non-existent"]'
              }
            ]
          end

          it 'does not schedule the worker' do
            expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

            service.execute
          end
        end

        context 'with unsupported filter attribute' do
          let(:operations) do
            [
              {
                op: 'Remove',
                path: "members[display eq \"#{identity.extern_uid}\"]"
              }
            ]
          end

          it 'does not schedule the worker' do
            expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

            service.execute
          end
        end
      end
    end

    context 'with replace operation' do
      let(:operations) do
        [
          {
            op: 'Replace',
            value: { id: scim_group_uid, displayName: 'engineering' }
          }
        ]
      end

      it 'does not schedule the worker' do
        expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

        service.execute
      end

      it 'returns success' do
        expect(service.execute).to be_success
      end

      context 'with displayName path' do
        let(:operations) { [{ op: 'Replace', path: 'displayName', value: 'engineering' }] }

        it 'does not schedule the worker' do
          expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

          service.execute
        end

        it 'returns success' do
          expect(service.execute).to be_success
        end
      end

      context 'with members path' do
        let_it_be(:user) { create(:user) }
        let_it_be(:identity) { create(:scim_identity, user: user, group: nil) }
        let(:operations) do
          [
            {
              op: 'Replace',
              path: 'members',
              value: [{ value: identity.extern_uid }]
            }
          ]
        end

        it 'schedules the worker to replace members' do
          expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
            .with(scim_group_uid, [user.id], 'replace')

          service.execute
        end

        it 'returns success' do
          allow(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)

          expect(service.execute).to be_success
        end

        context 'with case-insensitive path' do
          let(:operations) do
            [
              {
                op: 'REPLACE',
                path: 'MEMBERS',
                value: [{ value: identity.extern_uid }]
              }
            ]
          end

          it 'schedules the worker to replace members' do
            expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
              .with(scim_group_uid, [user.id], 'replace')

            service.execute
          end
        end

        context 'with an empty members list' do
          let(:operations) { [{ op: 'Replace', path: 'members', value: [] }] }

          it 'schedules the worker to replace members with no users' do
            expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
              .with(scim_group_uid, [], 'replace')

            service.execute
          end
        end

        context 'with a non-array value' do
          let(:operations) { [{ op: 'Replace', path: 'members', value: 'invalid' }] }

          it 'does not schedule the worker' do
            expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

            service.execute
          end
        end
      end

      context 'with members in a value without a path' do
        let_it_be(:user) { create(:user) }
        let_it_be(:identity) { create(:scim_identity, user: user, group: nil) }
        let(:operations) do
          [{ op: 'Replace', value: { displayName: 'engineering', members: [{ value: identity.extern_uid }] } }]
        end

        it 'schedules the worker to replace members' do
          expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
            .with(scim_group_uid, [user.id], 'replace')

          service.execute
        end

        context 'with a differently cased key' do
          let(:operations) { [{ op: 'Replace', value: { 'Members' => [] } }] }

          it 'schedules the worker to replace members with no users' do
            expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
              .with(scim_group_uid, [], 'replace')

            service.execute
          end
        end
      end

      context 'without a path and with a value that is not an object' do
        let(:operations) { [{ op: 'Replace', value: 'engineering' }] }

        it 'does not schedule the worker' do
          expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

          service.execute
        end

        it 'returns success' do
          expect(service.execute).to be_success
        end
      end

      shared_examples 'rejects replacing members with a filter path' do
        it 'returns an error' do
          result = service.execute

          expect(result).to be_error
          expect(result.message).to eq('Replacing group members with a filter path is not supported')
        end

        it 'does not schedule the worker' do
          expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

          service.execute
        end
      end

      context 'with a members filter path' do
        let(:operations) { [{ op: 'Replace', path: 'members[value eq "abc"]', value: {} }] }

        it_behaves_like 'rejects replacing members with a filter path'
      end

      context 'when another operation in the same request uses a members filter path' do
        let_it_be(:identity) { create(:scim_identity, user: create(:user), group: nil) }
        let(:operations) do
          [
            { op: 'Add', path: 'members', value: [{ value: identity.extern_uid }] },
            { op: 'Replace', path: 'members[value eq "abc"]', value: {} }
          ]
        end

        it_behaves_like 'rejects replacing members with a filter path'
      end

      context 'when the members replace is combined with another member change' do
        let_it_be(:identity) { create(:scim_identity, user: create(:user), group: nil) }

        shared_examples 'rejects combining a members replace' do
          it 'returns an error' do
            result = service.execute

            expect(result).to be_error
            expect(result.message).to eq(
              "Replacing group members can't be combined with other member changes in the same request"
            )
          end

          it 'does not schedule the worker' do
            expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

            service.execute
          end
        end

        context 'with an add on members' do
          let(:operations) do
            [
              { op: 'Replace', path: 'members', value: [{ value: identity.extern_uid }] },
              { op: 'Add', path: 'members', value: [{ value: identity.extern_uid }] }
            ]
          end

          it_behaves_like 'rejects combining a members replace'
        end

        context 'with a remove using a filter path' do
          let(:operations) do
            [
              { op: 'Remove', path: "members[value eq \"#{identity.extern_uid}\"]" },
              { op: 'Replace', path: 'members', value: [] }
            ]
          end

          it_behaves_like 'rejects combining a members replace'
        end

        context 'with a second members replace' do
          let(:operations) do
            [
              { op: 'Replace', path: 'members', value: [] },
              { op: 'Replace', value: { members: [{ value: identity.extern_uid }] } }
            ]
          end

          it_behaves_like 'rejects combining a members replace'
        end

        context 'with an operation that does not change members' do
          let(:operations) do
            [
              { op: 'Replace', path: 'displayName', value: 'engineering' },
              { op: 'Replace', path: 'members', value: [{ value: identity.extern_uid }] }
            ]
          end

          it 'schedules the worker to replace members' do
            expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
              .with(scim_group_uid, [identity.user_id], 'replace')

            expect(service.execute).to be_success
          end
        end
      end
    end

    context 'with multiple operations' do
      let_it_be(:user1) { create(:user) }
      let_it_be(:user2) { create(:user) }
      let_it_be(:identity1) { create(:scim_identity, user: user1, group: nil) }
      let_it_be(:identity2) { create(:scim_identity, user: user2, group: nil) }
      let(:operations) do
        [
          {
            op: 'Add',
            path: 'members',
            value: [{ value: identity1.extern_uid }]
          },
          {
            op: 'Remove',
            path: 'members',
            value: [{ value: identity2.extern_uid }]
          }
        ]
      end

      it 'schedules workers for each operation' do
        expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
          .with(scim_group_uid, [user1.id], 'add')
        expect(Authn::SyncScimGroupMembersWorker).to receive(:perform_async)
          .with(scim_group_uid, [user2.id], 'remove')

        service.execute
      end
    end

    context 'with empty or invalid values' do
      let(:operations) do
        [
          {
            op: 'Add',
            path: 'members',
            value: []
          }
        ]
      end

      it 'does not schedule the worker' do
        expect(Authn::SyncScimGroupMembersWorker).not_to receive(:perform_async)

        service.execute
      end
    end
  end
end
