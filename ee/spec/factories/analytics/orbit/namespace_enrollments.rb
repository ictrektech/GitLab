# frozen_string_literal: true

FactoryBot.define do
  factory :orbit_namespace_enrollment, class: '::Analytics::Orbit::NamespaceEnrollment' do
    namespace { association(:group) }
    source { :trial }

    trait :beta do
      source { :beta }
    end
  end
end
