# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::UsersPerIpLimit, :clean_gitlab_redis_rate_limiting, feature_category: :duo_agent_platform do
  let_it_be(:users) { create_list(:user, 5) }
  let_it_be(:user) { create(:user) }

  let(:ip) { '203.0.113.10' }

  def request_for(ip)
    ActionDispatch::Request.new(Rack::MockRequest.env_for('/api/v4/ai', 'REMOTE_ADDR' => ip))
  end

  def throttled?(user, ip: self.ip)
    described_class.new(user: user, request: request_for(ip)).throttled?
  end

  def fill_ip(ip = self.ip, from: users)
    from.each { |u| throttled?(u, ip: ip) }
  end

  describe '#throttled?' do
    context 'when on GitLab.com', :saas_gitlab_com_subscriptions do
      it 'does not throttle up to the limit of distinct users' do
        expect(users.map { |u| throttled?(u) }).to all(be(false))
      end

      it 'throttles once the limit of distinct users is exceeded' do
        fill_ip

        expect(throttled?(user)).to be(true)
      end

      it 'counts a repeat user only once' do
        users.first(4).each { |u| throttled?(u) }
        3.times { throttled?(users.first) }

        expect(throttled?(user)).to be(false)
      end

      it 'counts each IP separately' do
        fill_ip

        expect(throttled?(user, ip: '203.0.113.11')).to be(false)
      end

      it 'logs the throttled request' do
        fill_ip

        expect(Gitlab::AuthLogger).to receive(:error).with(
          hash_including(env: :ai_users_per_ip_request_limit, remote_ip: ip, user_id: user.id)
        )

        throttled?(user)
      end

      context 'with IPv6 addresses' do
        it 'shares a bucket within the same /48 network' do
          fill_ip('2001:db8:abcd:1::1')

          expect(throttled?(user, ip: '2001:db8:abcd:ffff::2')).to be(true)
        end

        it 'uses separate buckets for different /48 networks' do
          fill_ip('2001:db8:abcd:1::1')

          expect(throttled?(user, ip: '2001:db8:abce:1::1')).to be(false)
        end

        it 'shares a bucket between an IPv4 address and its IPv4-mapped form' do
          fill_ip

          expect(throttled?(user, ip: "::ffff:#{ip}")).to be(true)
        end
      end

      context 'with an unusable IP' do
        it 'does not throttle' do
          fill_ip

          expect(throttled?(user, ip: '')).to be(false)
          expect(throttled?(user, ip: 'not-an-ip')).to be(false)
        end
      end

      context 'when the user belongs to a paid namespace' do
        let_it_be(:paid_user) { create(:user) }

        before_all do
          create(:group_with_plan, plan: :ultimate_plan).add_developer(paid_user)
        end

        it 'does not throttle the user' do
          fill_ip

          expect(throttled?(paid_user)).to be(false)
        end

        it 'does not count the user' do
          fill_ip(from: users.first(4))
          throttled?(paid_user)

          expect(throttled?(users.last)).to be(false)
        end
      end

      context 'when the user only belongs to a trial namespace' do
        before_all do
          create(
            :group_with_plan, plan: :ultimate_plan, trial: true,
            trial_starts_on: Date.current, trial_ends_on: 30.days.from_now
          ).add_developer(user)
        end

        it 'throttles the user' do
          fill_ip

          expect(throttled?(user)).to be(true)
        end
      end

      context 'when the user has a non-trial add-on seat' do
        let_it_be(:seat_user) { create(:user) }

        before_all do
          create(
            :gitlab_subscription_user_add_on_assignment,
            user: seat_user,
            add_on_purchase: create(:gitlab_subscription_add_on_purchase, :duo_enterprise, :active)
          )
        end

        it 'does not throttle the user' do
          fill_ip

          expect(throttled?(seat_user)).to be(false)
        end
      end

      context 'when the user has a trial add-on seat' do
        let_it_be(:trial_seat_user) { create(:user) }

        before_all do
          create(
            :gitlab_subscription_user_add_on_assignment,
            user: trial_seat_user,
            add_on_purchase: create(:gitlab_subscription_add_on_purchase, :duo_enterprise, :active_trial)
          )
        end

        it 'throttles the user' do
          fill_ip

          expect(throttled?(trial_seat_user)).to be(true)
        end
      end

      context 'when the user is a bot' do
        let_it_be(:bot) { create(:user, :service_account) }

        it 'does not throttle the user' do
          fill_ip

          expect(throttled?(bot)).to be(false)
        end
      end

      context 'when the request is made by an agent on behalf of the user' do
        let_it_be(:service_account) { create(:user, :service_account, composite_identity_enforced: true) }

        before do
          allow(::Gitlab::Auth::Identity).to receive(:resolve_composite_identity_actor).and_call_original
          allow(::Gitlab::Auth::Identity).to receive(:resolve_composite_identity_actor)
            .with(user).and_return(service_account)
        end

        it 'does not throttle the user' do
          fill_ip

          expect(throttled?(user)).to be(false)
        end

        it 'does not count the user' do
          fill_ip(from: users.first(4))
          throttled?(user)

          expect(throttled?(users.last)).to be(false)
        end
      end

      context 'without a user' do
        it 'does not throttle' do
          fill_ip

          expect(throttled?(nil)).to be(false)
        end
      end

      context 'when the paid status is cached', :use_clean_rails_memory_store_caching do
        it 'checks the paid status once per user' do
          expect(user).to receive(:belongs_to_paid_namespace?).once.and_call_original

          2.times { throttled?(user) }
        end
      end

      context 'when enforce_ai_users_per_ip_limit is disabled' do
        before do
          stub_feature_flags(enforce_ai_users_per_ip_limit: false)
        end

        it 'does not throttle but still logs the request' do
          fill_ip

          expect(Gitlab::AuthLogger).to receive(:error).with(hash_including(env: :ai_users_per_ip_request_limit))

          expect(throttled?(user)).to be(false)
        end
      end

      context 'when ai_users_per_ip_limit is disabled' do
        before do
          stub_feature_flags(ai_users_per_ip_limit: false)
        end

        it 'does not count or throttle users' do
          expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled_request?)

          fill_ip

          expect(throttled?(user)).to be(false)
        end
      end
    end

    context 'when not on GitLab.com' do
      it 'does not count or throttle users' do
        expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled_request?)

        fill_ip

        expect(throttled?(user)).to be(false)
      end
    end
  end
end
