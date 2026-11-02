# frozen_string_literal: true

# Exercises short-lived Redis challenges without creating accounts.
load ENV.fetch('VOS_CHALLENGE_SOURCE')
strategy_class = OmniAuth::Strategies::Vos
session = { '_csrf_token' => SecureRandom.hex(32) }
other_session = { '_csrf_token' => SecureRandom.hex(32) }
states = 2.times.map do
  strategy = strategy_class.new(nil)
  strategy.instance_variable_set(:@env, { 'rack.session' => session, 'SCRIPT_NAME' => '/app/com.ictrek.gitlab',
                   'REQUEST_METHOD' => 'POST', 'rack.input' => StringIO.new('') })
  response = strategy.request_phase
  location = response[1]['location'] || response[1]['Location']
  URI.decode_www_form(URI.parse(location).query).to_h.fetch('state')
end
raise 'Flows reused a challenge' unless states.uniq.size == 2
states.each do |state|
  raise 'Parallel challenge disappeared' unless strategy_class.pending_challenge(state, session)
end
raise 'Cross-session callback was accepted' if strategy_class.pending_challenge(states.first, other_session, consume: true)
raise 'Cross-session attempt consumed the challenge' unless strategy_class.pending_challenge(states.first, session)
puts 'PASS: parallel request phases retain independent session-bound challenges'

start = Queue.new
results = 2.times.map do
  Thread.new do
    start.pop
    strategy_class.pending_challenge(states.first, session, consume: true)
  end
end
2.times { start << true }
raise 'Concurrent replay was accepted' unless results.map(&:value).count(&:itself) == 1
raise 'A different flow was consumed' unless strategy_class.pending_challenge(states.last, session)
puts 'PASS: atomic consumption permits one callback without invalidating another flow'
Gitlab::Redis::SharedState.with { |redis| redis.expire("#{strategy_class::CHALLENGE_PREFIX}:#{states.last}", 0) }
raise 'Expired challenge was accepted' if strategy_class.pending_challenge(states.last, session)
raise 'Malformed challenge was accepted' if strategy_class.pending_challenge('../invalid', session)
puts 'PASS: expired and malformed challenges are rejected'
