# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::Users::UpdateTwoFactorRequirementService, feature_category: :system_access do
  let_it_be_with_reload(:user) { create(:user) }

  let(:service) { described_class.new(user) }

  describe '#execute' do
    subject(:execute) { service.execute }

    context 'with a regular membership in a group requiring 2FA' do
      let_it_be(:group) do
        create(:group, require_two_factor_authentication: true, two_factor_grace_period: 23, developers: user)
      end

      before_all do
        # Membership creation callbacks already set the truthful value on a
        # separate instance, so reload before planting the stale value
        user.reload.update!(require_two_factor_authentication_from_group: false)
      end

      before do
        stub_licensed_features(minimal_access_role: true)
      end

      it 'still counts memberships collected by the CE implementation' do
        expect { execute }.to change { user.require_two_factor_authentication_from_group }.from(false).to(true)
      end
    end

    context 'with a minimal access role' do
      context 'when user is a direct member of a top-level-group requiring 2FA' do
        let!(:group) { create(:group, require_two_factor_authentication: true, two_factor_grace_period: 23) }
        let!(:membership) { create(:group_member, :minimal_access, source: group, user: user) }

        it 'does not require 2FA' do
          execute

          expect(user.reload.require_two_factor_authentication_from_group).to be(false)
        end

        it 'keeps the default two_factor_grace_period' do
          execute

          expect(user.reload.two_factor_grace_period).to be(48)
        end
      end

      context 'when user is a member of a sub-group, with a parent requires 2FA' do
        let!(:parent_group) { create(:group, require_two_factor_authentication: true, two_factor_grace_period: 23) }
        let!(:group) { create :group, parent: parent_group, minimal_access: user }

        it 'does not update the requirement' do
          expect { execute }.not_to change { user.require_two_factor_authentication_from_group }
        end

        it 'does not update the two_factor_grace_period' do
          expect { execute }.not_to change { user.two_factor_grace_period }
        end
      end

      context 'when :minimal_access_role is enabled' do
        before do
          stub_licensed_features(minimal_access_role: true)
        end

        context 'when user is a direct member of a top-level-group requiring 2FA' do
          let!(:group) do
            create(:group, require_two_factor_authentication: true, two_factor_grace_period: 23, minimal_access: user)
          end

          it 'updates the requirement' do
            expect { execute }
            .to change { user.require_two_factor_authentication_from_group }.from(false).to(true)
          end

          context 'with user in another top-level-group with a lower 2FA grace period' do
            let!(:group2) do
              create(:group, require_two_factor_authentication: true, two_factor_grace_period: 5, minimal_access: user)
            end

            it 'updates the requirement with the minimum grace period' do
              expect { execute }.to change { user.two_factor_grace_period }.to(5)
            end
          end

          context 'with pending access to the group (requested_at IS NOT NULL)' do
            let!(:group) { create(:group, require_two_factor_authentication: true) }

            it 'does not require 2FA', :freeze_time do
              create(:group_member, :minimal_access, source: group, user: user, requested_at: Time.current)

              execute

              expect(user.reload.require_two_factor_authentication_from_group).to be(false)
            end
          end
        end

        context 'when user is a member of a sub-group, with a parent requires 2FA' do
          let!(:parent_group) { create(:group, require_two_factor_authentication: true, two_factor_grace_period: 23) }
          let!(:group) { create :group, parent: parent_group, minimal_access: user }

          it 'does not update the requirement' do
            expect { execute }.not_to change { user.require_two_factor_authentication_from_group }
          end

          it 'does not update the two_factor_grace_period' do
            expect { execute }.not_to change { user.two_factor_grace_period }
          end
        end
      end
    end
  end
end
