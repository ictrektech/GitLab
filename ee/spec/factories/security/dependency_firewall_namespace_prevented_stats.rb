# frozen_string_literal: true

FactoryBot.define do
  factory :dependency_firewall_namespace_prevented_stat, class: 'Security::DependencyFirewallNamespacePreventedStat' do
    association :namespace, factory: :group
    window_days { 7 }
    window_start { Date.current - 6 }
  end
end
