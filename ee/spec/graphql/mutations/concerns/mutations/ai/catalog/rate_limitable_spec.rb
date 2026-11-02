# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Ai::Catalog::RateLimitable, :clean_gitlab_redis_rate_limiting, :freeze_time,
  feature_category: :ai_catalog_curation do
  let_it_be(:user) { create(:user) }

  # Registered at 30 requests per minute per user.
  let(:key) { :ai_catalog_item_consumer_create }
  let(:limit) { 30 }
  let(:request) { ActionDispatch::Request.new(Rack::MockRequest.env_for('/api/graphql', method: 'POST')) }
  let(:context) { { current_user: user, request: request } }

  let(:rate_limited_class) do
    mod = described_class

    Class.new do
      include mod

      attr_reader :context

      def initialize(context)
        @context = context
      end

      def current_user
        context[:current_user]
      end

      def check(...)
        rate_limited?(...)
      end
    end
  end

  def limited_for?(user)
    rate_limited_class.new(context.merge(current_user: user)).check(key, scope: { user: user })
  end

  describe '#rate_limited?' do
    context 'when the context has a request' do
      it 'is false until the limit is reached, then logs the throttled request to the auth log' do
        expect(Gitlab::AuthLogger).to receive(:error).once.with(
          hash_including(
            message: 'Application_Rate_Limiter_Request',
            env: :ai_catalog_item_consumer_create_request_limit,
            user_id: user.id,
            username: user.username,
            method: 'POST',
            path: '/api/graphql'
          )
        )

        limit.times { expect(limited_for?(user)).to be(false) }
        expect(limited_for?(user)).to be(true)
      end
    end

    context 'when the context has no request' do
      # GraphqlChannel executes mutations without a Rack request.
      let(:context) { { current_user: user } }

      it 'still applies the limit without logging the request' do
        expect(Gitlab::AuthLogger).not_to receive(:error)

        limit.times { expect(limited_for?(user)).to be(false) }
        expect(limited_for?(user)).to be(true)
      end
    end

    context 'when another user is over the limit' do
      let_it_be(:other_user) { create(:user) }

      before do
        (limit + 1).times { limited_for?(other_user) }
      end

      it 'does not limit the current user' do
        expect(limited_for?(user)).to be(false)
      end
    end
  end
end
