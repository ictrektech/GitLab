# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Users::UserMemberRole, feature_category: :system_access do
  describe 'associations' do
    it { is_expected.to belong_to(:member_role) }
    it { is_expected.to belong_to(:user) }
  end

  describe 'validation' do
    subject(:user_member_role) { build(:user_member_role) }

    it { is_expected.to validate_presence_of(:member_role) }
    it { is_expected.to validate_presence_of(:user) }
    it { is_expected.to validate_uniqueness_of(:user) }
  end

  describe '.ldap_synced' do
    let_it_be(:user_member_role) { create(:user_member_role) }
    let_it_be(:user_member_role_ldap) { create(:user_member_role, ldap: true) }

    subject(:ldap_synced_user_roles) do
      described_class.ldap_synced
    end

    it 'returns only records with ldap true' do
      expect(ldap_synced_user_roles).to eq([user_member_role_ldap])
    end
  end

  describe '.with_identity_provider' do
    let_it_be(:provider) { 'ldapmain' }

    let_it_be(:user) { create(:user) }
    let_it_be(:user_member_role) { create(:user_member_role, user: user) }

    subject(:with_identity_provider) { described_class.with_identity_provider(provider) }

    context 'when the user has an identity for the provider' do
      before do
        create(:identity, user: user, provider: provider)
      end

      it 'returns the record' do
        expect(with_identity_provider).to eq([user_member_role])
      end
    end

    context 'when the user has an identity for a different provider' do
      before do
        create(:identity, user: user, provider: 'jwt', extern_uid: 'jwt-uid')
      end

      it 'returns an empty array' do
        expect(with_identity_provider).to eq([])
      end
    end
  end

  describe '.create_or_update' do
    let_it_be(:user) { create(:user) }
    let_it_be(:member_role) { create(:member_role, :admin) }
    let_it_be(:other_member_role) { create(:member_role, :admin) }

    subject(:create_or_update) do
      described_class.create_or_update(user: user, member_role: member_role, ldap: true)
    end

    context 'when a user has join record' do
      let!(:join_record) { create(:user_member_role, user: user, member_role: other_member_role) }

      it 'updates the existing record with the new role and attributes' do
        expect { create_or_update }.to change { join_record.reload.member_role_id }
          .from(other_member_role.id).to(member_role.id)
          .and change { join_record.reload.ldap }.from(false).to(true)
      end

      it 'does not create a new join record' do
        expect { create_or_update }.not_to change { described_class.count }
      end
    end

    context 'when a user has no join record' do
      it 'creates a new join record with the correct role' do
        expect { create_or_update }.to change { described_class.count }.by(1)

        expect(described_class.find_by(user: user)).to have_attributes(member_role_id: member_role.id, ldap: true)
      end
    end
  end

  describe '.preload_user' do
    let_it_be(:user_member_role) { create(:user_member_role) }

    subject(:relation) { described_class.preload_user }

    it 'loads user association' do
      expect(relation.first.association(:user)).to be_loaded
    end
  end
end
