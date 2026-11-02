# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::Users::TwoFactorGroupsFinder, feature_category: :system_access do
  let_it_be(:user) { create(:user) }

  describe '#execute' do
    subject(:execute) { described_class.new(user).execute }

    context 'with a minimal access membership in a group requiring 2FA' do
      context 'when :minimal_access_role is not licensed' do
        let!(:group) { create(:group, require_two_factor_authentication: true) }
        let!(:membership) { create(:group_member, :minimal_access, source: group, user: user) }

        it { is_expected.to be_empty }
      end

      context 'when :minimal_access_role is licensed' do
        before do
          stub_licensed_features(minimal_access_role: true)
        end

        let!(:group) { create(:group, require_two_factor_authentication: true, minimal_access: user) }

        it 'returns the group' do
          is_expected.to contain_exactly(group)
        end
      end
    end

    context 'with a minimal access membership in a group whose child requires 2FA' do
      before do
        stub_licensed_features(minimal_access_role: true)
      end

      let!(:group) { create(:group, minimal_access: user) }
      let!(:child_group) { create(:group, require_two_factor_authentication: true, parent: group) }

      it 'returns the child group' do
        is_expected.to contain_exactly(child_group)
      end
    end

    context 'with a regular membership in a group requiring 2FA' do
      let_it_be(:group) { create(:group, require_two_factor_authentication: true, developers: user) }

      before do
        stub_licensed_features(minimal_access_role: true)
      end

      it 'still returns groups collected by the CE implementation' do
        is_expected.to contain_exactly(group)
      end
    end

    context 'with source_only: true' do
      subject(:execute) { described_class.new(user, source_only: true).execute }

      before do
        stub_licensed_features(minimal_access_role: true)
      end

      context 'with a minimal access membership in a group requiring 2FA' do
        let!(:group) { create(:group, require_two_factor_authentication: true, minimal_access: user) }

        it 'returns the group' do
          is_expected.to contain_exactly(group)
        end
      end

      context 'with a minimal access membership in a sub-group whose parent requires 2FA' do
        let!(:parent_group) { create(:group, require_two_factor_authentication: true) }
        let!(:group) { create(:group, parent: parent_group, minimal_access: user) }

        it { is_expected.to be_empty }
      end

      context 'when :minimal_access_role is not licensed' do
        before do
          stub_licensed_features(minimal_access_role: false)
        end

        let!(:group) { create(:group, require_two_factor_authentication: true) }
        let!(:membership) { create(:group_member, :minimal_access, source: group, user: user) }

        it { is_expected.to be_empty }
      end
    end
  end
end
