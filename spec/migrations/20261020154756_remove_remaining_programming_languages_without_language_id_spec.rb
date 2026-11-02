# frozen_string_literal: true

require 'spec_helper'
require_migration!

RSpec.describe RemoveRemainingProgrammingLanguagesWithoutLanguageId,
  migration: :gitlab_main_cell_local,
  feature_category: :source_code_management do
  let(:programming_languages) { table(:programming_languages) }
  let(:repository_languages) { table(:repository_languages) }

  describe '#up' do
    subject(:run_migration) { migrate! }

    context 'when programming languages have missing language IDs' do
      it 'deletes languages without a language ID' do
        unknown_language = create_programming_language(name: 'Unknown', language_id: nil)
        other_unknown_language = create_programming_language(name: 'Other unknown', language_id: nil)

        run_migration

        expect(programming_languages.where(id: [unknown_language.id, other_unknown_language.id])).to be_empty
      end
    end

    context 'when programming languages have language IDs' do
      it 'preserves programming languages and repository languages', :aggregate_failures do
        ruby = create_programming_language(name: 'Ruby', language_id: 326)
        repository_language = repository_languages.create!(
          project_id: create_project.id,
          programming_language_id: ruby.id,
          language_id: ruby.language_id,
          share: 100
        )
        ruby_attributes = ruby.reload.attributes
        repository_language_attributes = repository_language.reload.attributes

        run_migration

        expect(ruby.reload.attributes).to eq(ruby_attributes)
        expect(repository_language.reload.attributes).to eq(repository_language_attributes)
      end
    end
  end

  def create_programming_language(name:, language_id:)
    programming_languages.create!(
      name: name,
      color: '#000000',
      language_id: language_id,
      created_at: Time.current
    )
  end

  def create_project
    organization = table(:organizations).create!(name: 'Organization', path: 'organization')
    group = table(:namespaces).create!(
      name: 'Group', path: 'group', type: 'Group', organization_id: organization.id
    )
    project_namespace = table(:namespaces).create!(
      name: 'Project', path: 'project', type: 'Project', organization_id: organization.id
    )

    table(:projects).create!(
      name: 'Project', path: 'project', namespace_id: group.id,
      project_namespace_id: project_namespace.id, organization_id: organization.id
    )
  end
end
