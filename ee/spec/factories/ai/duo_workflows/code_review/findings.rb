# frozen_string_literal: true

FactoryBot.define do
  factory :duo_code_review_finding, class: 'Ai::DuoWorkflows::CodeReview::Finding' do
    note { association(:diff_note_on_merge_request) }
    merge_request { note.noteable }
    severity { :minor }
    depth { :standard }
    category { 'missing-test' }
    confidence { 7 }
  end
end
