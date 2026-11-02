# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::Groups::UpdateTwoFactorRequirementService, feature_category: :system_access do
  before do
    stub_licensed_features(minimal_access_role: true)
  end

  describe '#execute' do
    subject(:execute) { described_class.new(group: group).execute }

    context 'when the group no longer requires two-factor authentication' do
      let_it_be_with_reload(:group) { create(:group, require_two_factor_authentication: false) }
      let_it_be_with_reload(:minimal_access_user) { create(:user) }

      before_all do
        create(:group_member, :minimal_access, source: group, user: minimal_access_user)

        # A stale requirement cannot be produced through factories or callbacks,
        # since those recalculate the truthful value, so it is planted directly
        minimal_access_user.update!(require_two_factor_authentication_from_group: true, two_factor_grace_period: 23)
      end

      it 'recalculates the requirement for members with the Minimal Access role' do
        expect { execute }
          .to change { minimal_access_user.reload.require_two_factor_authentication_from_group }
          .from(true).to(false)
      end
    end

    context 'when a subgroup requires two-factor authentication' do
      let_it_be_with_reload(:group) { create(:group) }
      let_it_be_with_reload(:minimal_access_user) { create(:user) }

      let_it_be(:subgroup) do
        create(:group, parent: group, require_two_factor_authentication: true, two_factor_grace_period: 23)
      end

      before_all do
        create(:group_member, :minimal_access, source: group, user: minimal_access_user)

        # The membership is created before the license stub applies, so the
        # starting value is planted explicitly rather than left to hook order
        minimal_access_user.update!(require_two_factor_authentication_from_group: false)
      end

      it 'enforces the requirement on root members with the Minimal Access role via the descendant chain' do
        expect { execute }
          .to change { minimal_access_user.reload.require_two_factor_authentication_from_group }
          .from(false).to(true)
      end
    end

    context 'when the group requires two-factor authentication' do
      let_it_be_with_reload(:group) { create(:group, require_two_factor_authentication: true) }
      let_it_be_with_reload(:blocked_user) { create(:user) }
      let_it_be_with_reload(:requesting_user) { create(:user) }

      before_all do
        create(:group_member, :developer, :blocked, source: group, user: blocked_user)
        create(:group_member, :developer, :access_request, source: group, user: requesting_user)
        create(:group_member, :developer, :invited, source: group)

        # Membership creation callbacks recalculate the requirement before the
        # user is blocked, so the starting value is planted explicitly
        blocked_user.update!(require_two_factor_authentication_from_group: false)
      end

      it 'does not recalculate the requirement for members of blocked users' do
        expect { execute }
          .not_to change { blocked_user.reload.require_two_factor_authentication_from_group }.from(false)
      end

      it 'does not recalculate the requirement for access requests' do
        expect { execute }
          .not_to change { requesting_user.reload.require_two_factor_authentication_from_group }.from(false)
      end

      it 'skips invited members, which have no user to recalculate' do
        expect { execute }.not_to raise_error
      end
    end
  end
end
