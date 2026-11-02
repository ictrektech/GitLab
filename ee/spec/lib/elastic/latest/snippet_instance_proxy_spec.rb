# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Elastic::Latest::SnippetInstanceProxy, :elastic_helpers, feature_category: :global_search do
  let(:snippet) { create(:personal_snippet) }

  subject { described_class.new(snippet) }

  describe '#as_indexed_json' do
    it 'serializes snippet as hash' do
      expect(subject.as_indexed_json.with_indifferent_access).to include(
        id: snippet.id,
        title: snippet.title,
        description: snippet.description,
        created_at: snippet.created_at,
        updated_at: snippet.updated_at,
        project_id: snippet.project_id,
        author_id: snippet.author_id,
        visibility_level: snippet.visibility_level
      )
    end

    describe 'project access data' do
      let_it_be(:project) { create(:project, :internal, :snippets_private) }
      let_it_be(:project_snippet) { create(:project_snippet, :private, project: project) }

      before do
        set_elasticsearch_migration_to described_class::ORGANIZATION_FIELDS_MIGRATION, including: true
      end

      it 'adds the project visibility and snippets access level to a project snippet' do
        expect(described_class.new(project_snippet).as_indexed_json).to include(
          'visibility_level' => Gitlab::VisibilityLevel::PRIVATE,
          'project_visibility_level' => Gitlab::VisibilityLevel::INTERNAL,
          'snippets_access_level' => ProjectFeature::PRIVATE,
          'schema_version' => described_class::SCHEMA_VERSION
        )
      end

      it 'adds neither field to a personal snippet' do
        expect(subject.as_indexed_json.keys).not_to include('project_visibility_level', 'snippets_access_level')
      end

      context 'when the mapping migration has not finished' do
        before do
          set_elasticsearch_migration_to described_class::PROJECT_ACCESS_FIELDS_MIGRATION, including: false
        end

        it 'adds neither field to a project snippet and keeps the previous schema version' do
          json = described_class.new(project_snippet).as_indexed_json

          expect(json.keys).not_to include('project_visibility_level', 'snippets_access_level')
          expect(json['schema_version']).to eq(described_class::SCHEMA_VERSIONS.keys.min)
        end
      end
    end

    describe 'organization data' do
      let_it_be(:project) { create(:project) }
      let_it_be(:project_snippet) { create(:project_snippet, project: project) }

      before do
        set_elasticsearch_migration_to described_class::ORGANIZATION_FIELDS_MIGRATION, including: true
      end

      it 'resolves the organization of a project snippet through its project' do
        expect(described_class.new(project_snippet).as_indexed_json).to include(
          'organization_id' => project.organization_id,
          'schema_version' => described_class::SCHEMA_VERSION
        )
      end

      it 'reads the organization of a personal snippet from the snippet itself' do
        expect(subject.as_indexed_json).to include('organization_id' => snippet.organization_id)
      end

      it 'does not index organization_traversal_ids, since snippets carry no traversal_ids' do
        expect(described_class.new(project_snippet).as_indexed_json.keys)
          .not_to include('organization_traversal_ids', 'traversal_ids')
      end

      # The DB constraint allows exactly one of organization_id/project_id, so this cannot
      # happen today. The nil-guard is defensive: indexing must not raise on bad data.
      context 'when the snippet has neither an organization nor a project' do
        it 'indexes a nil organization_id instead of raising' do
          allow(project_snippet).to receive_messages(organization_id: nil, project: nil)

          json = described_class.new(project_snippet).as_indexed_json

          expect(json).to include('organization_id' => nil)
        end
      end

      context 'when the mapping migration has not finished' do
        before do
          set_elasticsearch_migration_to described_class::ORGANIZATION_FIELDS_MIGRATION, including: false
        end

        it 'does not index organization_id and keeps the previous schema version' do
          json = described_class.new(project_snippet).as_indexed_json

          expect(json.keys).not_to include('organization_id')
          expect(json['schema_version']).to eq(described_class::SCHEMA_VERSIONS.keys.sort[-2])
        end
      end
    end
  end
end
