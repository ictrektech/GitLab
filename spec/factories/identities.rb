# frozen_string_literal: true

FactoryBot.define do
  factory :identity do
    association :user
    provider { 'ldapmain' }
    sequence(:extern_uid) { |n| "my-ldap-id-#{n}" }

    trait :skip_validate do
      to_create { |instance| instance.save!(validate: false) }
    end
  end
end
