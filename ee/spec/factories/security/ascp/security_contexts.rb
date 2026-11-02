# frozen_string_literal: true

FactoryBot.define do
  factory :security_ascp_security_context, class: 'Security::Ascp::SecurityContext' do
    project
    scan { association(:security_ascp_scan, project: project) }
    component { association(:security_ascp_component, project: project, scan: scan) }
    summary { 'Handles user authentication with session-based security' }
    authentication_model { 'Session-based with JWT tokens' }
    authorization_model { 'Role-based access control (RBAC)' }
    data_sensitivity { 'high' }
    security_boundary { %w[NETWORK_ACCESS USER_INPUT] }

    trait :with_guidelines do
      guidelines do
        [
          association(:security_ascp_security_guideline,
            strategy: :build, security_context: instance, project: project, scan: scan)
        ]
      end
    end
  end
end
