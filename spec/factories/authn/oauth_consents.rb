# frozen_string_literal: true

FactoryBot.define do
  factory :oauth_consent, class: 'Authn::OauthConsent' do
    user
    application factory: :oauth_application
    client_id { application.uid }
    consent_challenge { SecureRandom.hex(32) }
    status { :authorized }
    requested_scopes { %w[openid profile] }
    granted_scopes { %w[openid profile] }

    trait :rejected do
      status { :rejected }
      granted_scopes { [] }
    end

    trait :revoked do
      status { :revoked }
    end

    # The application lives on another cell, so there is no local row to join to.
    trait :cross_cell do
      application { nil }
      sequence(:client_id) { |n| "cross-cell-client-#{n}" }
    end
  end
end
