# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'User achievementCounts', feature_category: :user_profile do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:group) { create(:group, :public) }
  let_it_be(:achievement) { create(:achievement, namespace: group) }
  let_it_be(:other_achievement) { create(:achievement, namespace: group) }

  let_it_be(:first_award) do
    create(:user_achievement, achievement: achievement, user: user, show_on_profile: true, created_at: 2.days.ago)
  end

  let_it_be(:latest_award) do
    create(:user_achievement, achievement: achievement, user: user, show_on_profile: true, award_message: 'Thanks!')
  end

  let_it_be(:other_award) do
    create(:user_achievement, achievement: other_achievement, user: user, show_on_profile: true, priority: 0)
  end

  let_it_be(:revoked_award) do
    create(:user_achievement, :revoked, achievement: achievement, user: user, show_on_profile: true)
  end

  let_it_be(:hidden_award) do
    create(:user_achievement, achievement: achievement, user: user, show_on_profile: false)
  end

  let(:current_user) { user }

  let(:fields) do
    <<~GRAPHQL
      achievementCounts {
        nodes {
          count
          firstAwardedAt
          achievement { id }
          latestUserAchievement { id awardMessageHtml }
        }
      }
    GRAPHQL
  end

  let(:query) { graphql_query_for('user', { username: user.username }, fields) }
  let(:nodes) { graphql_data_at(:user, :achievementCounts, :nodes) }

  def counts_by_achievement
    nodes.to_h { |node| [node.dig('achievement', 'id'), node['count']] }
  end

  before do
    post_graphql(query, current_user: current_user)
  end

  it_behaves_like 'a working graphql query'

  it 'returns one row per achievement, ordered by priority, without revoked or hidden awards' do
    expect(nodes.map { |node| node.dig('achievement', 'id') }).to eq([
      other_achievement.to_global_id.to_s,
      achievement.to_global_id.to_s
    ])
    expect(counts_by_achievement).to eq(
      other_achievement.to_global_id.to_s => 1,
      achievement.to_global_id.to_s => 2
    )
  end

  it 'returns the first award date and the latest award' do
    node = nodes.find { |n| n.dig('achievement', 'id') == achievement.to_global_id.to_s }

    expect(Time.zone.parse(node['firstAwardedAt'])).to be_within(1.second).of(first_award.created_at)
    expect(node['latestUserAchievement']).to match(
      a_graphql_entity_for(latest_award, award_message_html: a_string_including('Thanks!'))
    )
  end

  context 'when the user has a private profile' do
    let_it_be(:private_user) { create(:user, private_profile: true) }

    let(:query) { graphql_query_for('user', { username: private_user.username }, fields) }

    before_all do
      create(:user_achievement, achievement: achievement, user: private_user, show_on_profile: true)
    end

    context 'when current_user is someone else' do
      let(:current_user) { create(:user) }

      it 'returns no achievements' do
        expect(nodes).to be_empty
      end
    end

    context 'when current_user is the profile owner' do
      let(:current_user) { private_user }

      it 'returns the achievements' do
        expect(nodes).not_to be_empty
      end
    end
  end

  context 'when the achievement belongs to a private group' do
    let_it_be(:private_group) { create(:group, :private) }
    let_it_be(:private_achievement) { create(:achievement, namespace: private_group) }

    before_all do
      create(:user_achievement, achievement: private_achievement, user: user, show_on_profile: true)
    end

    context 'when current_user cannot read the group' do
      let(:current_user) { create(:user) }

      it 'does not return the achievement' do
        expect(counts_by_achievement.keys).not_to include(private_achievement.to_global_id.to_s)
      end
    end

    context 'when current_user is the recipient' do
      it 'returns the achievement' do
        expect(counts_by_achievement[private_achievement.to_global_id.to_s]).to eq(1)
      end
    end
  end

  it 'avoids N+1 queries', :use_clean_rails_memory_store_caching do
    control_user, other_user = create_list(:user, 2)

    control = ActiveRecord::QueryRecorder.new(skip_cached: false) do
      post_graphql(query, current_user: control_user)
    end

    create_list(:achievement, 2, namespace: group).each do |new_achievement|
      create_list(:user_achievement, 2, achievement: new_achievement, user: user, show_on_profile: true)
    end

    expect { post_graphql(query, current_user: other_user) }.not_to exceed_all_query_limit(control)
  end
end
