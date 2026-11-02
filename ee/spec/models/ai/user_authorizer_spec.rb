# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::UserAuthorizer, feature_category: :ai_abstraction_layer do
  describe '#eligible_for_self_managed_gitlab_duo_pro?' do
    using RSpec::Parameterized::TableSyntax

    let_it_be(:active_user) { create(:user) }
    let_it_be(:bot) { create(:user, :bot) }
    let_it_be(:ghost) { create(:user, :ghost) }
    let_it_be(:blocked_user) { create(:user, :blocked) }
    let_it_be(:banned_user) { create(:user, :banned) }
    let_it_be(:pending_approval_user) { create(:user, :blocked_pending_approval) }
    let_it_be(:group) { create(:group) }
    let_it_be(:guest_user) { create(:group_member, :guest, source: group).user }

    subject { described_class.new(user).eligible_for_self_managed_gitlab_duo_pro? }

    context 'when on gitlab.com' do
      let(:user) { active_user }

      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it { is_expected.to be(false) }
    end

    context 'when on self managed' do
      before do
        stub_saas_features(gitlab_com_subscriptions: false)
      end

      # True for human users, excluding bots, blocked, banned, and pending_approval users.
      where(:user, :result) do
        ref(:bot)                     | false
        ref(:ghost)                   | false
        ref(:blocked_user)            | false
        ref(:banned_user)             | false
        ref(:pending_approval_user)   | false
        ref(:active_user)             | true
        ref(:guest_user)              | true
      end

      with_them do
        it { is_expected.to eq(result) }
      end
    end
  end
end
