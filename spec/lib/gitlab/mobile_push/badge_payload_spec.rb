# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::MobilePush::BadgePayload, feature_category: :notifications do
  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }

  subject(:payload) { described_class.new(user) }

  it 'carries no alert content' do
    expect(payload.title).to be_nil
    expect(payload.subtitle).to be_nil
    expect(payload.body).to be_nil
    expect(payload.thread_id).to be_nil
    expect(payload.mutable_content?).to be(false)
  end

  describe '#badge' do
    it 'is the pending, not snoozed to-do count' do
      create_list(:todo, 2, user: user, project: project)
      create(:todo, :done, user: user, project: project)
      create(:todo, user: user, project: project, snoozed_until: 1.day.from_now)

      expect(payload.badge).to eq(2)
    end

    it 'bypasses a stale count cache and rewrites it', :use_clean_rails_memory_store_caching do
      create(:todo, user: user, project: project)
      Rails.cache.write(['users', user.id, 'todos_pending_count'], 42)

      expect(user.todos_pending_count).to eq(42)
      expect(payload.badge).to eq(1)
      expect(Rails.cache.read(['users', user.id, 'todos_pending_count'])).to eq(1)
    end

    it 'reads the count once for several devices' do
      expect(user).to receive(:todos_pending_count).once.and_return(3)

      2.times { expect(payload.badge).to eq(3) }
    end
  end

  it 'collapses per user' do
    expect(payload.collapse_id).to eq("badge-#{user.id}")
  end

  it 'restricts the gitlab dict to identifiers' do
    expect(payload.gitlab_data).to eq(version: 1, type: 'badge', user_id: user.id)
  end
end
