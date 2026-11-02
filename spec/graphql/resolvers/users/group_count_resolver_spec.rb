# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Users::GroupCountResolver do
  include GraphqlHelpers

  describe '#resolve' do
    let_it_be(:user1) { create(:user) }
    let_it_be(:user2) { create(:user) }
    let_it_be(:group1) { create(:group) }
    let_it_be(:group2) { create(:group) }
    let_it_be(:project) { create(:project, group: create(:group)) }
    let_it_be(:group_member1) { create(:group_member, source: group1, user_id: user1.id, access_level: Gitlab::Access::OWNER) }
    let_it_be(:project_member1) { create(:project_member, source: project, user_id: user1.id, access_level: Gitlab::Access::DEVELOPER) }
    let_it_be(:group_member2) { create(:group_member, source: group2, user_id: user2.id, access_level: Gitlab::Access::DEVELOPER) }

    it 'resolves group count for users' do
      current_user = user1

      result = batch_sync do
        [user1, user2].map { |user| resolve_group_count(user, current_user) }
      end

      expect(result).to eq([2, nil])
    end

    it 'resolves the unscoped group count when organizationId is null' do
      result = batch_sync do
        resolve(described_class, obj: user1, args: { organization_id: nil }, ctx: { current_user: user1 })
      end

      expect(result).to eq(2)
    end

    context 'permissions' do
      context 'when current_user is an admin', :enable_admin_mode do
        let_it_be(:admin) { create(:admin) }

        it 'resolves the group count for every user' do
          result = batch_sync do
            [user1, user2].map { |user| resolve_group_count(user, admin) }
          end

          expect(result).to eq([2, 1])
        end
      end

      context 'when current_user does not have access to the requested resource' do
        it 'returns nil instead of the group count' do
          result = batch_sync { resolve_group_count(user1, user2) }

          expect(result).to be_nil
        end
      end

      context 'when current_user does not exist' do
        it 'returns nil instead of the group count' do
          result = batch_sync { resolve_group_count(user1, nil) }

          expect(result).to be_nil
        end
      end

      context 'when an organization is given' do
        let_it_be(:organization) { create(:organization) }
        let_it_be(:organization_owner) { create(:user) }

        before_all do
          create(:organization_user, :owner, organization: organization, user: organization_owner)
          create(:group, organization: organization, developers: user2)
        end

        it 'resolves group count within the organization for an organization owner' do
          result = batch_sync { resolve_group_count(user2, organization_owner, organization) }

          expect(result).to eq(1)
        end

        it 'resolves group count within the organization for the current user' do
          result = batch_sync { resolve_group_count(user2, user2, organization) }

          expect(result).to eq(1)
        end

        it 'does not resolve group count for a user without groups in the organization' do
          result = batch_sync { resolve_group_count(user1, organization_owner, organization) }

          expect(result).to be_nil
        end

        it 'does not resolve group count for another user' do
          result = batch_sync { resolve_group_count(user2, user1, organization) }

          expect(result).to be_nil
        end

        it 'loads the organization once for several users', :request_store do
          args = { organization_id: organization.to_global_id }

          recorder = ActiveRecord::QueryRecorder.new do
            batch_sync do
              [user1, user2].map do |target|
                resolve(described_class, obj: target, args: args, ctx: { current_user: organization_owner })
              end
            end
          end

          expect(recorder.log.grep(/FROM "organizations"/).size).to eq(1)
        end

        it 'does not resolve group count for an organization that does not exist' do
          missing_organization = build(:organization, id: non_existing_record_id)

          result = batch_sync { resolve_group_count(user2, user2, missing_organization) }

          expect(result).to be_nil
        end

        context 'when current_user is an admin', :enable_admin_mode do
          let_it_be(:admin) { create(:admin) }

          it 'resolves group count within the organization' do
            result = batch_sync { resolve_group_count(user2, admin, organization) }

            expect(result).to eq(1)
          end
        end

        context 'when current_user owns a different organization' do
          it 'does not resolve the group count' do
            result = batch_sync { resolve_group_count(user2, organization_owner, create(:organization)) }

            expect(result).to be_nil
          end
        end
      end

      context 'when current_user is an organization owner and no organization is given' do
        let_it_be(:organization_owner) { create(:user) }

        before_all do
          create(:organization_user, :owner, organization: create(:organization), user: organization_owner)
        end

        it 'does not resolve the group count' do
          result = batch_sync { resolve_group_count(user2, organization_owner) }

          expect(result).to be_nil
        end
      end
    end
  end

  def resolve_group_count(user, current_user, organization = nil)
    args = organization ? { organization_id: organization.to_global_id } : {}

    resolve(described_class, obj: user, args: args, ctx: { current_user: current_user })
  end
end
