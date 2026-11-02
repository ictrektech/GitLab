# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Achievements::Achievement, feature_category: :user_profile do
  describe 'associations' do
    it { is_expected.to belong_to(:namespace).inverse_of(:achievements).required }

    it { is_expected.to have_many(:user_achievements).inverse_of(:achievement) }
    it { is_expected.to have_many(:users).through(:user_achievements).inverse_of(:achievements) }
  end

  describe 'validations' do
    subject { create(:achievement) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).case_insensitive.scoped_to([:namespace_id]) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }
    it { is_expected.to validate_length_of(:description).is_at_most(1024) }
  end

  describe '#name' do
    it 'strips name' do
      achievement = build(:achievement, name: '  AchievementTest  ')

      achievement.valid?

      expect(achievement.name).to eq('AchievementTest')
    end

    it 'is invalid when it contains HTML' do
      achievement = build(:achievement, name: '<script>alert(1)</script>')

      expect(achievement).not_to be_valid
      expect(achievement.errors[:name]).to include(HtmlSafetyValidator.error_message)
    end
  end

  describe '#description' do
    it 'is invalid when it contains HTML' do
      achievement = build(:achievement, description: '<script>alert(1)</script>')

      expect(achievement).not_to be_valid
      expect(achievement.errors[:description]).to include(HtmlSafetyValidator.error_message)
    end
  end

  it_behaves_like Avatarable do
    let(:model) { create(:achievement, :with_avatar) }
  end

  describe '#uploads_sharding_key' do
    it 'returns namespace_id' do
      namespace = build_stubbed(:namespace)
      achievement = build_stubbed(:achievement, namespace: namespace)

      expect(achievement.uploads_sharding_key).to eq(namespace_id: namespace.id)
    end
  end

  describe '.with_user_achievement_counts' do
    let_it_be(:user) { create(:user) }
    let_it_be(:mixed) { create(:achievement) }
    let_it_be(:single) { create(:achievement, namespace: mixed.namespace) }

    let(:user_achievements) { Achievements::UserAchievement.where(user: user) }

    subject(:counts) { described_class.with_user_achievement_counts(user_achievements) }

    before_all do
      create(:user_achievement, achievement: mixed, user: user, priority: nil)
      create(:user_achievement, achievement: single, user: user, priority: 1)
      create(:user_achievement, achievement: mixed, user: user, priority: 0)
    end

    it 'counts awards per achievement' do
      expect(counts.to_h { |achievement| [achievement.id, achievement.user_achievement_count] })
        .to eq(mixed.id => 2, single.id => 1)
    end

    # The profile lists awards one by one, so its first award of `mixed` has no priority and sorts last.
    it 'orders an achievement with mixed priorities by its lowest award priority' do
      expect(counts.map(&:id)).to eq([mixed.id, single.id])
    end

    it 'works with a relation that joins achievements' do
      joined = user_achievements.for_namespaces([mixed.namespace_id])

      expect(described_class.with_user_achievement_counts(joined).map(&:id)).to eq([mixed.id, single.id])
    end
  end

  describe '#unique_users' do
    let_it_be(:achievement) { create(:achievement) }

    subject(:unique_users) { achievement.unique_users }

    it 'returns unique users even when a user has multiple awards' do
      user1 = create(:user)
      user2 = create(:user)

      create(:user_achievement, achievement: achievement, user: user1)
      create(:user_achievement, achievement: achievement, user: user1)
      create(:user_achievement, achievement: achievement, user: user2)

      expect(unique_users).to contain_exactly(user1, user2)
    end

    it 'returns empty when no users have been awarded' do
      expect(unique_users).to be_empty
    end
  end
end
