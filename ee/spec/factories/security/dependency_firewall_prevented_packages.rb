# frozen_string_literal: true

FactoryBot.define do
  factory :dependency_firewall_prevented_package, class: 'Security::DependencyFirewallPreventedPackage' do
    project
    rule_type { :license }
    sequence(:identifier) { |n| "pkg:npm/package-#{n}@1.0.0" }
    first_seen_at { Time.current }
    last_blocked_at { Time.current }

    trait :warned_only do
      last_blocked_at { nil }
      last_warned_at { Time.current }
    end

    trait :risk_severity do
      rule_type { :risk_severity }
      severity { :critical }
    end

    trait :malicious do
      rule_type { :malicious }
    end
  end
end
