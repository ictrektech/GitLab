# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'getting project information', feature_category: :notifications do
  include GraphqlHelpers

  let_it_be(:current_user) { create(:user) }
  let_it_be(:group) { create(:group, developers: current_user) }
  let_it_be(:epic) { create(:epic, group: group) }
  let_it_be(:epic_todo) { create(:todo, user: current_user, target: epic) }

  let(:fields) do
    <<~QUERY
    nodes {
      #{all_graphql_fields_for('todos'.classify)}
    }
    QUERY
  end

  let(:query) do
    graphql_query_for('currentUser', {}, query_graphql_field('todos', {}, fields))
  end

  subject { graphql_data.dig('currentUser', 'todos', 'nodes') }

  before do
    stub_licensed_features(epics: true)

    post_graphql(query, current_user: current_user)
  end

  it_behaves_like 'a working graphql query'

  it 'returns Todos for all target types' do
    is_expected.to include(
      a_hash_including('targetType' => 'EPIC')
    )
  end

  describe 'a to-do whose target is behind an expired group SAML session' do
    let_it_be(:saml_group) { create(:group, :private) }
    let_it_be(:saml_provider) { create(:saml_provider, group: saml_group, enabled: true, enforced_sso: true) }
    let_it_be(:saml_project) { create(:project, :private, group: saml_group, developers: current_user) }
    let_it_be(:saml_issue) { create(:issue, project: saml_project, title: 'Confidential issue title') }
    let_it_be(:saml_note) do
      create(:note_on_issue, noteable: saml_issue, project: saml_project, note: 'Confidential note body')
    end

    let_it_be(:saml_todo) do
      create(:todo, user: current_user, project: saml_project, target: saml_issue, note: saml_note)
    end

    let(:fields) do
      <<~QUERY
      nodes {
        id
        targetType
        targetUrl
        body
        author {
          name
        }
        note {
          bodyFirstLineHtml
        }
        targetEntity {
          name
        }
      }
      QUERY
    end

    # Run inside a web session that has never recorded a group SAML sign-in, so the
    # group's SAML session reads as expired and the target is restricted.
    around do |example|
      session = { 'warden.user.user.key' => [[current_user.id], current_user.authenticatable_salt] }
      Gitlab::Session.with_session(session) { example.run }
    end

    before do
      stub_licensed_features(epics: true, group_saml: true)

      post_graphql(query, current_user: current_user)
    end

    it 'lists the to-do but masks the target-derived contents so the user can reauthenticate' do
      ghost = ::Users::Internal.in_organization(saml_project.organization_id).ghost
      saml_node = graphql_data.dig('currentUser', 'todos', 'nodes').find do |node|
        node['id'] == saml_todo.to_global_id.to_s
      end

      expect(saml_node).to include(
        'targetType' => 'ISSUE',
        'targetEntity' => nil,
        'body' => '',
        'note' => nil,
        'author' => { 'name' => ghost.name }
      )
      # The target URL is kept so selecting the to-do can trigger reauthentication.
      expect(saml_node['targetUrl']).to be_present
    end

    it 'does not leak the confidential target contents anywhere in the response' do
      expect(response.body).not_to include(saml_issue.title, saml_note.note, saml_todo.author.name)
    end

    it 'avoids N+1 queries when masking several to-dos in the same project', :request_store do
      control = ActiveRecord::QueryRecorder.new { post_graphql(query, current_user: current_user) }

      second_issue = create(:issue, project: saml_project, title: 'Second confidential issue')
      create(:todo, user: current_user, project: saml_project, target: second_issue)

      # The bypassed-policy cache is shared across masked to-dos in the same
      # project, so a second masked to-do must not rebuild the target's policy
      # tree from scratch (as `cache: false` per to-do would).
      expect { post_graphql(query, current_user: current_user) }.not_to exceed_query_limit(control)
    end
  end

  describe 'a commit-backed to-do whose target is behind an expired group SAML session' do
    let_it_be(:saml_group) { create(:group, :private) }
    let_it_be(:saml_provider) { create(:saml_provider, group: saml_group, enabled: true, enforced_sso: true) }
    let_it_be(:saml_project) do
      create(:project, :repository, :private, group: saml_group, developers: current_user)
    end

    let_it_be(:commit_todo) do
      create(:on_commit_todo, user: current_user, project: saml_project, author: current_user)
    end

    let(:fields) do
      <<~QUERY
      nodes {
        id
        targetType
        body
        author {
          name
        }
        targetEntity {
          ... on Commit {
            sha
          }
        }
      }
      QUERY
    end

    # Run inside a web session that has never recorded a group SAML sign-in, so the
    # group's SAML session reads as expired and the commit target is restricted.
    around do |example|
      session = { 'warden.user.user.key' => [[current_user.id], current_user.authenticatable_salt] }
      Gitlab::Session.with_session(session) { example.run }
    end

    before do
      stub_licensed_features(group_saml: true)

      post_graphql(query, current_user: current_user)
    end

    it 'masks the commit-backed to-do so the user can reauthenticate' do
      ghost = ::Users::Internal.in_organization(saml_project.organization_id).ghost
      commit_node = graphql_data.dig('currentUser', 'todos', 'nodes').find do |node|
        node['id'] == commit_todo.to_global_id.to_s
      end

      expect(commit_node).to include(
        'targetType' => 'COMMIT',
        'targetEntity' => nil,
        'body' => '',
        'author' => { 'name' => ghost.name }
      )
    end
  end
end
