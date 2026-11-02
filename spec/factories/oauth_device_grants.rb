# frozen_string_literal: true

FactoryBot.define do
  factory :oauth_device_grant, class: 'Doorkeeper::DeviceAuthorizationGrant::DeviceGrant' do
    organization { association(:common_organization) }
    application
    resource_owner_id { nil }
    expires_in { 300 }
    scopes { 'api' }
    user_code { SecureRandom.alphanumeric(8) }
  end
end
