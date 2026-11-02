# frozen_string_literal: true

# Run with gitlab-rails runner in an isolated development container only.
raise 'Set VOS_AUTH_TEST_ISOLATED=1 for the disposable test instance' unless ENV['VOS_AUTH_TEST_ISOLATED'] == '1'
$stdout.sync = true

def assert(condition, message)
  raise message unless condition
end

endpoint = ENV.fetch('VOS_OIDC_ENDPOINT')
client = Gitlab::Auth::Vos::Client.new(endpoint: endpoint, client_id: 'com.ictrek.gitlab')
alice = client.verify('alice')
bob = client.verify('bob')
assert(alice[:uid] != bob[:uid], 'Different subjects must remain separate despite identical display names')
assert(client.verify('renamed')[:uid] == alice[:uid], 'Renames must retain the identity')
%w[revoked wrong-aud expired wrong-scope disabled].each do |token|
  rejected = false
  begin
    client.verify(token)
  rescue Gitlab::Auth::Vos::Client::InvalidIdentity
    rejected = true
  end
  assert(rejected, "Failed to reject #{token} credential")
end

organization = Organizations::Organization.default_organization
provision = lambda do |identity|
  auth = OmniAuth::AuthHash.new(provider: 'vos', uid: identity[:uid], info: identity.except(:uid))
  user = Gitlab::Auth::Vos::User.new(auth, organization_id: organization.id)
  user.find_and_update!
  assert(user.valid_sign_in?, "Could not provision account: #{user.gl_user&.errors&.full_messages}")
  user.gl_user
end
first = provision.call(alice)
second = provision.call(bob)
assert(first.id != second.id, 'Accounts were incorrectly linked')
assert(!first.admin? && !second.admin?, 'VOS login must not grant administrator privileges')
assert(provision.call(client.verify('renamed')).id == first.id, 'Login created a duplicate account')
first.block
auth = OmniAuth::AuthHash.new(provider: 'vos', uid: alice[:uid], info: alice.except(:uid))
assert(!Gitlab::Auth::Vos::User.new(auth, organization_id: organization.id).valid_sign_in?, 'Blocked GitLab user was accepted')
first.activate
puts 'PASS: online verification, separate accounts, rename stability, repeated login, and blocked-user rejection'

# Exercise the real OmniAuth middleware, callback controller, CSRF, and Devise session.
base = '/app/com.ictrek.gitlab'
browser = ActionDispatch::Integration::Session.new(Rack::URLMap.new(base => Rails.application))
browser.host!('gitlab.test')
browser.get("#{base}/-/vos/fastpath.js")
assert(browser.response.status == 200, "Bridge script failed: #{browser.response.status}")
assert(browser.response.media_type == 'application/javascript', 'Bridge script has the wrong content type')
puts 'PASS: public bridge script is available to a native script tag'
browser.get("#{base}/-/vos/sign_in")
assert(browser.response.status == 200, "Bootstrap failed: #{browser.response.status} #{browser.response.location}")
doc = Nokogiri::HTML(browser.response.body)
csrf = doc.at_css('input[name="authenticity_token"]')&.[]('value')
assert(csrf.present?, 'Bootstrap did not provide a CSRF token')
browser.post("#{base}/users/auth/vos", params: { authenticity_token: csrf })
assert(browser.response.redirect?, "OmniAuth request failed: #{browser.response.status}")
browser.follow_redirect!
doc = Nokogiri::HTML(browser.response.body)
state = doc.at_css('input[name="state"]')&.[]('value')
csrf = doc.at_css('input[name="authenticity_token"]')&.[]('value')
assert(state.present? && csrf.present?, 'Missing callback challenge')
browser.post("#{base}/users/auth/vos/callback", params: { authenticity_token: csrf, state: state, access_token: 'alice' })
assert(browser.response.redirect?, "Callback failed: #{browser.response.status}")
assert(browser.request.env['warden'].user(:user)&.id == first.id, 'Callback did not establish the correct native session')
puts 'PASS: native request/callback flow establishes the mapped GitLab session'

# Start a second login in the same browser to exercise account switching rather than identity linking.
browser.get("#{base}/-/vos/sign_in")
doc = Nokogiri::HTML(browser.response.body)
csrf = doc.at_css('input[name="authenticity_token"]')&.[]('value')
browser.post("#{base}/users/auth/vos", params: { authenticity_token: csrf })
browser.follow_redirect!
doc = Nokogiri::HTML(browser.response.body)
state = doc.at_css('input[name="state"]')&.[]('value')
csrf = doc.at_css('input[name="authenticity_token"]')&.[]('value')
browser.post("#{base}/users/auth/vos/callback", params: { authenticity_token: csrf, state: state, access_token: 'bob' })
assert(browser.request.env['warden'].user(:user)&.id == second.id, 'VOS user switch kept the previous account')
assert(Identity.with_extern_uid('vos', bob[:uid]).take.user_id == second.id, 'VOS identity was linked to the wrong account')
puts 'PASS: account switching establishes a separate native session without linking identities'

# A fresh CSRF token must not make an already-consumed callback challenge reusable.
browser.get("#{base}/-/vos/sign_in")
doc = Nokogiri::HTML(browser.response.body)
csrf = doc.at_css('input[name="authenticity_token"]')&.[]('value')
browser.post("#{base}/users/auth/vos/callback", params: { authenticity_token: csrf, state: state, access_token: 'alice' })
assert(browser.request.env['omniauth.error.type'] == :csrf_detected, 'Consumed callback state was accepted')
assert(browser.request.env['omniauth.auth'].nil?, 'Replayed callback created a verified identity')
puts 'PASS: callback state is single-use'

scope = { ip: "vos-auth-test-#{SecureRandom.hex(8)}" }
30.times { assert(!Gitlab::ApplicationRateLimiter.throttled?(:vos_authentication_ip, scope: scope), 'Rate limit fired too soon') }
assert(Gitlab::ApplicationRateLimiter.throttled?(:vos_authentication_ip, scope: scope), 'Rate limit did not fire')
assert(!Gitlab::ApplicationRateLimiter.throttled?(:vos_authentication_ip, scope: { ip: 'another-fixture' }), 'Rate limit crossed IP scopes')
puts 'PASS: native rate limiter enforces the configured threshold with isolated scopes'
subject_scope = { user: "vos-auth-subject-test-#{SecureRandom.hex(8)}" }
10.times { assert(!Gitlab::ApplicationRateLimiter.throttled?(:vos_authentication_user, scope: subject_scope), 'Subject rate limit fired too soon') }
assert(Gitlab::ApplicationRateLimiter.throttled?(:vos_authentication_user, scope: subject_scope), 'Subject rate limit did not fire')
puts 'PASS: verified-subject rate limit is independent of client IP and token rotation'

connection = ActiveRecord::Base.connection
assert(connection.select_value('SELECT current_database()') == 'gitlabhq_production', 'Wrong GitLab database')
assert(connection.select_value('SELECT current_user') == 'gitlab', 'GitLab used an administrator database role')
assert(connection.select_value("SELECT rolsuper FROM pg_roles WHERE rolname = current_user") == false, 'GitLab role is a superuser')
puts 'PASS: application uses the dedicated non-superuser GitLab database role'
