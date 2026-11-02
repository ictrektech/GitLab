# frozen_string_literal: true

FactoryBot.define do
  factory :duo_workflows_session_file, class: 'Ai::DuoWorkflows::SessionFile' do
    workflow { association(:duo_workflows_workflow) }
    size { 1.kilobyte }
    file { fixture_file_upload('spec/fixtures/dk.png', 'image/png') }
    content_type { 'image/png' }
  end
end
