# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying an AI catalog skill', :with_current_organization,
  feature_category: :ai_catalog_curation do
  include Ai::Catalog::TestHelpers
  include GraphqlHelpers

  let_it_be(:current_user, freeze: false) { create(:user) }

  let_it_be(:project, freeze: false) do
    create(:project, :in_group, developers: current_user, organization: current_organization)
  end

  let_it_be_with_reload(:skill) do
    create(:ai_catalog_skill, :public, project: project, name: 'cosign-blob', versions: [
      build(:ai_catalog_skill_version, item: nil, definition: {
        'path' => 'skills/cosign-blob/SKILL.md',
        'git_ref' => 'main',
        'blob_sha' => 'a' * 40,
        'commit_sha' => 'b' * 40,
        'author_name' => 'A. Committer'
      })
    ])
  end

  let(:fields) do
    <<~FIELDS
      id
      name
      itemType
      webPath
      ... on AiCatalogSkill {
        path
        directory
        gitRef
        blobSha
        commitSha
        authorName
      }
    FIELDS
  end

  let(:query) { graphql_query_for('aiCatalogItem', { id: skill.to_global_id.to_s }, fields) }

  before do
    enable_ai_catalog
  end

  it_behaves_like 'authorizing granular token permissions for GraphQL', :read_ai_catalog_item do
    let(:user) { current_user }
    let(:boundary_object) { project }
    let(:request) { post_graphql(query, current_user: current_user, token: { personal_access_token: pat }) }
  end

  it 'resolves to AiCatalogSkill and exposes the repository pointer' do
    post_graphql(query, current_user: current_user)

    expect(graphql_data_at(:ai_catalog_item)).to include(
      'name' => 'cosign-blob',
      'itemType' => 'SKILL',
      'webPath' => "/explore/ai-catalog/skills/#{skill.id}",
      'path' => 'skills/cosign-blob/SKILL.md',
      'directory' => 'skills/cosign-blob',
      'gitRef' => 'main',
      'blobSha' => 'a' * 40,
      'commitSha' => 'b' * 40,
      'authorName' => 'A. Committer'
    )
  end

  context 'when the definition records no commit' do
    let_it_be(:skill) { create(:ai_catalog_skill, :public, project: project, name: 'no-commit-skill') }

    it 'returns null for the optional provenance fields' do
      post_graphql(query, current_user: current_user)

      expect(graphql_data_at(:ai_catalog_item)).to include(
        'path' => 'skills/no-commit-skill/SKILL.md',
        'commitSha' => nil,
        'authorName' => nil
      )
    end
  end

  # `ai_catalog_items.latest_version_id` is nullable, so this state is representable even though
  # the model requires a latest version. The pointer fields are nullable and must say so rather
  # than erroring.
  context 'when the item has no latest version' do
    before do
      skill.update_column(:latest_version_id, nil)
    end

    it 'returns null for the repository pointer without raising' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:ai_catalog_item)).to include(
        'itemType' => 'SKILL',
        'path' => nil,
        'directory' => nil,
        'gitRef' => nil,
        'blobSha' => nil,
        'commitSha' => nil,
        'authorName' => nil
      )
    end
  end

  context 'when querying the latest item version' do
    let(:fields) do
      <<~FIELDS
        id
        latestVersion {
          versionName
          ... on AiCatalogSkillVersion {
            path
            blobSha
          }
        }
      FIELDS
    end

    it 'resolves to AiCatalogSkillVersion' do
      post_graphql(query, current_user: current_user)

      expect(graphql_data_at(:ai_catalog_item, :latest_version)).to include(
        'path' => 'skills/cosign-blob/SKILL.md',
        'blobSha' => 'a' * 40
      )
    end
  end

  context 'when querying item versions' do
    let(:fields) do
      <<~FIELDS
        id
        versions {
          nodes {
            versionName
            ... on AiCatalogSkillVersion {
              path
              gitRef
              blobSha
              commitSha
              authorName
            }
          }
        }
      FIELDS
    end

    it_behaves_like 'authorizing granular token permissions for GraphQL', :read_ai_catalog_item do
      let(:user) { current_user }
      let(:boundary_object) { project }
      let(:request) { post_graphql(query, current_user: current_user, token: { personal_access_token: pat }) }
    end

    it 'resolves versions to AiCatalogSkillVersion' do
      post_graphql(query, current_user: current_user)

      expect(graphql_data_at(:ai_catalog_item, :versions, :nodes, 0)).to include(
        'path' => 'skills/cosign-blob/SKILL.md',
        'gitRef' => 'main',
        'blobSha' => 'a' * 40,
        'commitSha' => 'b' * 40,
        'authorName' => 'A. Committer'
      )
    end
  end

  # Without a registered type, resolve_type raises for a skill, which takes down any query that
  # reaches one -- including an unfiltered list, because ItemsFinder does not exclude skills.
  describe 'an unfiltered aiCatalogItems query' do
    let(:query) do
      <<~GRAPHQL
        query {
          aiCatalogItems {
            nodes {
              id
              itemType
            }
          }
        }
      GRAPHQL
    end

    it 'includes the skill without raising' do
      post_graphql(query, current_user: current_user)

      expect(graphql_errors).to be_nil
      expect(graphql_data_at(:ai_catalog_items, :nodes)).to include(
        a_graphql_entity_for(skill, 'itemType' => 'SKILL')
      )
    end
  end

  describe 'listing skills' do
    let(:query) do
      <<~GRAPHQL
        query {
          aiCatalogItems(itemType: SKILL) {
            nodes {
              id
              ... on AiCatalogSkill {
                path
                directory
                gitRef
                blobSha
                commitSha
                authorName
              }
            }
          }
        }
      GRAPHQL
    end

    it 'avoids N+1 queries for the repository pointer' do
      # Warm up first: the first request of the example does one-off work that would otherwise
      # mask the per-item queries this guards against.
      post_graphql(query, current_user: current_user)

      control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }

      create_list(:ai_catalog_skill, 2, :public, project: project)

      expect { post_graphql(query, current_user: current_user) }.not_to exceed_query_limit(control)
      expect(graphql_data_at(:ai_catalog_items, :nodes).size).to eq(3)
    end
  end

  describe 'filtering by the SKILL item type' do
    let(:query) do
      <<~GRAPHQL
        query {
          aiCatalogItems(itemType: SKILL) {
            nodes {
              id
            }
          }
        }
      GRAPHQL
    end

    it 'returns only skills' do
      create(:ai_catalog_agent, :public, project: project)

      post_graphql(query, current_user: current_user)

      expect(graphql_data_at(:ai_catalog_items, :nodes)).to contain_exactly(a_graphql_entity_for(skill))
    end
  end
end
