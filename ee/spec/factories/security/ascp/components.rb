# frozen_string_literal: true

FactoryBot.define do
  factory :security_ascp_component, class: 'Security::Ascp::Component' do
    project
    scan { association(:security_ascp_scan, project: project) }
    title { 'User Authentication Module' }
    sequence(:sub_directory) { |n| "app/services/auth_#{n}" }
    description { 'Handles user authentication' }
    expected_user_behavior { 'Users authenticate with email and password' }

    trait :with_security_context do
      security_context do
        association(:security_ascp_security_context,
          strategy: :build, component: instance, project: project, scan: scan)
      end
    end
  end
end
