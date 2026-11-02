# frozen_string_literal: true

FactoryBot.define do
  factory :workforce_person, class: 'Workforce::Person' do
    # Forced to :create so build(:workforce_person) still populates the sharding key,
    # which is copied from the hierarchy before validation.
    association :hierarchy, factory: :workforce_hierarchy, strategy: :create
    sequence(:external_xid) { |n| "wd-#{n}" }
    sequence(:full_name) { |n| "Person #{n}" }

    trait :matched do
      association :user, strategy: :create
    end

    trait :unmatched do
      user { nil }
    end
  end
end
