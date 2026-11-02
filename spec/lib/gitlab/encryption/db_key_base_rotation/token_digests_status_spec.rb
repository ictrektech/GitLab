# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Encryption::DbKeyBaseRotation::TokenDigestsStatus, feature_category: :system_access do
  let_it_be(:user) { create(:user) }
  let_it_be(:rotated_at) { 1.day.ago.change(usec: 0) }

  subject(:status) { described_class.new(rotated_at: rotated_at) }

  def pat_result
    status.execute.detect { |result| result.model == 'PersonalAccessToken' }
  end

  describe '.new' do
    it 'raises for a rotation time that is not a time, or in the future', :aggregate_failures do
      [nil, rotated_at.iso8601, Date.yesterday, 1.hour.from_now].each do |invalid|
        expect { described_class.new(rotated_at: invalid) }
          .to raise_error(ArgumentError, 'rotated_at must not be in the future')
      end
    end
  end

  context 'without tokens created before the rotation' do
    before do
      create(:personal_access_token, user: user)
    end

    it 'reports none remaining and allows retiring today' do
      expect(pat_result).to have_attributes(remaining: 0, expired: 0, without_expiry: 0, latest_expiry: nil)
      expect(status.retirement_date).to eq(Date.current)
    end
  end

  context 'with tokens created before the rotation' do
    let_it_be(:unused) do
      create(:personal_access_token, user: user, created_at: 2.days.ago, expires_at: 20.days.from_now)
    end

    before_all do
      create(:personal_access_token, user: user, created_at: 2.days.ago, last_used_at: 1.hour.ago,
        expires_at: 40.days.from_now)
      create(:personal_access_token, :revoked, user: user, created_at: 2.days.ago, expires_at: 60.days.from_now)
      create(:personal_access_token, user: user, created_at: 2.days.ago).update_column(:expires_at, 1.day.ago)
    end

    it 'counts active tokens not used since the rotation, and expired ones apart' do
      expect(pat_result).to have_attributes(remaining: 1, expired: 1, without_expiry: 0,
        latest_expiry: unused.expires_at)
    end

    it 'allows retiring the day after the latest expiry' do
      expect(status.retirement_date).to eq(unused.expires_at.next_day)
    end

    it 'runs the queries once' do
      status.execute

      expect { status.retirement_date }.not_to exceed_query_limit(0)
    end

    it 'combines the counts of every batch' do
      stub_const("#{described_class}::BATCH_SIZE", 1)

      expect(pat_result).to have_attributes(remaining: 1, expired: 1, latest_expiry: unused.expires_at)
    end

    context 'when one never expires' do
      before do
        create(:personal_access_token, user: user, created_at: 2.days.ago).update_column(:expires_at, nil)
      end

      it 'has no retirement date' do
        expect(pat_result).to have_attributes(remaining: 2, without_expiry: 1)
        expect(status.retirement_date).to be_nil
      end
    end
  end

  context 'with a token created or last used exactly at the rotation' do
    before do
      create(:personal_access_token, user: user, created_at: rotated_at, last_used_at: rotated_at)
    end

    it 'counts it as remaining' do
      expect(pat_result).to have_attributes(remaining: 1)
    end
  end
end
