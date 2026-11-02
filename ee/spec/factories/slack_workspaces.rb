# frozen_string_literal: true

FactoryBot.define do
  factory :slack_workspace, class: 'Integrations::SlackWorkspace::Workspace' do
    sequence(:team_id) { |n| "T0DUO#{n}" }
    duo_namespace { association :group }
  end
end
