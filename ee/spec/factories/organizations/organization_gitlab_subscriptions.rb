# frozen_string_literal: true

FactoryBot.define do
  factory :organization_gitlab_subscription, class: 'Organizations::OrganizationGitlabSubscription' do
    organization

    gitlab_subscription do
      association(:gitlab_subscription, namespace: association(:group, organization: organization))
    end
  end
end
