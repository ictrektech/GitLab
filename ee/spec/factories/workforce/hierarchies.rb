# frozen_string_literal: true

FactoryBot.define do
  factory :workforce_hierarchy, class: 'Workforce::Hierarchy' do
    # The tenant is the root group on GitLab.com and the organization everywhere else.
    association :group, factory: :group, strategy: :create

    trait :instance_level do
      group { nil }
      organization { association(:common_organization) }
    end
  end
end
