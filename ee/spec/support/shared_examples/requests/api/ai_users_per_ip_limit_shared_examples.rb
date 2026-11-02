# frozen_string_literal: true

# Requires `subject` to perform the API call as `user`.
RSpec.shared_examples 'an endpoint with the AI users per IP limit' do
  context 'when the AI users per IP limit is exceeded' do
    before do
      allow_next_instance_of(Ai::UsersPerIpLimit) do |limit|
        allow(limit).to receive(:throttled?).and_return(true)
      end
    end

    it 'returns 429 with the rate limit headers' do
      subject

      expect(response).to have_gitlab_http_status(:too_many_requests)
      expect(response.headers['RateLimit-Name']).to eq('ai_users_per_ip')
      expect(response.headers['Retry-After'].to_i).to eq(1.day.to_i)
      expect(json_response.dig('message', 'error')).to eq(Gitlab::ApplicationRateLimiter.throttled_error_message)
    end
  end

  context 'when the AI users per IP limit is not exceeded' do
    it 'checks the limit for the current user' do
      expect(Ai::UsersPerIpLimit).to receive(:new)
        .with(hash_including(user: user)).and_call_original

      subject

      expect(response).not_to have_gitlab_http_status(:too_many_requests)
    end
  end
end
