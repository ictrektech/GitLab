# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Achievements::AchievementPolicy, feature_category: :user_profile do
  let_it_be_with_reload(:current_user) { create(:user) }

  subject { described_class.new(current_user, achievement) }

  context 'in a private group' do
    let_it_be(:group) { create(:group, :private) }
    let_it_be(:achievement) { create(:achievement, namespace: group) }

    it { is_expected.to delegate_to(GroupPolicy) }
    it { is_expected.to be_disallowed(:read_achievement) }

    context 'when the user has received the achievement' do
      let_it_be(:user_achievement) { create(:user_achievement, user: current_user, achievement: achievement) }

      it { is_expected.to be_allowed(:read_achievement) }
    end
  end
end
