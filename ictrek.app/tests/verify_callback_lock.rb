# frozen_string_literal: true

# Uses only short-lived Redis leases; creates no users or database records.
load ENV.fetch('VOS_CALLBACK_SOURCE')
mutex = Mutex.new
active = 0
maximum = 0
calls = 0
probe = Class.new do
  include Gitlab::Auth::Vos::Callbacks
  attr_accessor :identity, :flow
  define_method(:current_user) { nil }
  define_method(:oauth) { { 'uid' => identity } }
  define_method(:sign_in_user_flow) { |_klass| flow.call }
end
identity = "callback-check-#{SecureRandom.hex(16)}"
start = Queue.new
threads = 2.times.map do
  Thread.new do
    controller = probe.new
    controller.identity = identity
    controller.flow = lambda do
      mutex.synchronize { active += 1; maximum = [maximum, active].max; calls += 1 }
      sleep 0.1
      mutex.synchronize { active -= 1 }
    end
    start.pop
    controller.vos
  end
end
2.times { start << true }
threads.each(&:value)
raise 'Concurrent provisioning was not serialized' unless calls == 2 && maximum == 1
puts 'PASS: same-identity callbacks serialize the full native sign-in flow across threads'
