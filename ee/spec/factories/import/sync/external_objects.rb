# frozen_string_literal: true

FactoryBot.define do
  factory :import_sync_external_object, class: 'Import::Sync::ExternalObject' do
    repository { association(:import_sync_repository) }
    project_id { repository.project_id }
    kind { :issue }
    sequence(:provider_object_xid, 70_000)
    provider_updated_at { Time.current }
    issue { association(:issue, project: repository.project) }

    trait :pull_request do
      kind { :pull_request }
      issue { nil }
      merge_request do
        association(:merge_request, source_project: repository.project, target_project: repository.project)
      end
    end

    trait :issue_comment do
      kind { :issue_comment }
      issue { nil }
      note { association(:note, project: repository.project) }
    end

    trait :review_comment do
      kind { :review_comment }
      issue { nil }
      note { association(:legacy_diff_note_on_merge_request, project: repository.project) }
    end
  end
end
