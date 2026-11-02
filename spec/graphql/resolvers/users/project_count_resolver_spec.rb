# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Resolvers::Users::ProjectCountResolver, feature_category: :user_management do
  include GraphqlHelpers

  describe '#resolve' do
    let_it_be(:organization) { create(:organization) }
    let_it_be(:user) { create(:user) }
    let_it_be(:other_user) { create(:user) }
    let_it_be(:organization_project) { create(:project, group: create(:group, organization: organization)) }
    let_it_be(:other_organization_project) { create(:project) }

    before_all do
      organization_project.add_developer(user)
      other_organization_project.add_developer(user)
    end

    it 'resolves project count for the current user' do
      expect(resolve_project_count(user, user)).to eq(2)
    end

    it 'resolves project count within the given organization for the current user' do
      expect(resolve_project_count(user, user, organization)).to eq(1)
    end

    it 'resolves the unscoped project count when organizationId is null' do
      result = batch_sync do
        resolve(described_class, obj: user, args: { organization_id: nil }, ctx: { current_user: user })
      end

      expect(result).to eq(2)
    end

    it 'stops counting projects within the given organization past the limit' do
      stub_const('Users::ProjectsCounter::COUNT_LIMIT', 1)
      create_list(:project, 2, group: organization_project.group).each { |project| project.add_developer(user) }

      expect(resolve_project_count(user, user, organization)).to eq(2)
    end

    it 'does not resolve project count for another user within the given organization' do
      expect(resolve_project_count(user, other_user, organization)).to be_nil
    end

    it 'does not resolve project count for an organization that does not exist' do
      missing_organization = build(:organization, id: non_existing_record_id)

      expect(resolve_project_count(user, user, missing_organization)).to be_nil
    end

    it 'does not resolve project count for another user' do
      expect(resolve_project_count(user, other_user)).to be_nil
    end

    it 'does not resolve project count without a current user' do
      expect(resolve_project_count(user, nil)).to be_nil
    end

    context 'when current_user is an admin', :enable_admin_mode do
      let_it_be(:admin) { create(:admin) }

      it 'resolves project count across organizations' do
        expect(resolve_project_count(user, admin)).to eq(2)
      end

      it 'resolves project count within the given organization' do
        expect(resolve_project_count(user, admin, organization)).to eq(1)
      end
    end

    context 'when current_user is an organization owner' do
      let_it_be(:organization_owner) { create(:user) }

      before_all do
        create(:organization_user, :owner, organization: organization, user: organization_owner)
      end

      it 'resolves project count within the given organization' do
        expect(resolve_project_count(user, organization_owner, organization)).to eq(1)
      end

      it 'resolves zero for a user without projects in the given organization' do
        expect(resolve_project_count(other_user, organization_owner, organization)).to eq(0)
      end

      it 'does not resolve project count without an organization' do
        expect(resolve_project_count(user, organization_owner)).to be_nil
      end

      it 'does not resolve project count for a different organization' do
        expect(resolve_project_count(user, organization_owner, create(:organization))).to be_nil
      end

      it 'loads the organization once for several users', :request_store do
        args = { organization_id: organization.to_global_id }

        recorder = ActiveRecord::QueryRecorder.new do
          batch_sync do
            [user, other_user].map do |target|
              resolve(described_class, obj: target, args: args, ctx: { current_user: organization_owner })
            end
          end
        end

        expect(recorder.log.grep(/FROM "organizations"/).size).to eq(1)
      end
    end
  end

  def resolve_project_count(user, current_user, organization = nil)
    args = organization ? { organization_id: organization.to_global_id } : {}

    batch_sync do
      resolve(described_class, obj: user, args: args, ctx: { current_user: current_user })
    end
  end
end
