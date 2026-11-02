# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Repositories::WorkItems::ReconcileIssueEventService, :clean_gitlab_redis_shared_state,
  feature_category: :importers do
  include Import::UserMappingHelper
  using RSpec::Parameterized::TableSyntax

  let_it_be(:project) { create(:project, :in_group, :github_import, :import_user_mapping_enabled) }
  let_it_be(:repository) { create(:import_sync_repository, :oauth, project: project) }
  let_it_be(:source_user) { generate_source_user(project, 1000) }
  let_it_be(:issue) { create(:issue, project: project, iid: 4) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project, iid: 5) }
  let_it_be(:label) { create(:label, project: project, title: 'bug') }
  let_it_be(:milestone) { create(:milestone, project: project, title: 'v1') }

  let(:client) { instance_double(Gitlab::GithubImport::Client) }
  let(:created_at) { Time.zone.parse('2026-08-25 11:30:00') }
  let(:event_type) { 'labeled' }
  let(:provider_issue) { { number: 4, pull_request: nil } }
  let(:provider_event) do
    {
      id: 9001,
      event: event_type,
      actor: { id: 1000, login: 'github_author' },
      label: { name: 'bug', color: 'fc2929' },
      milestone: { title: 'v1' },
      issue: provider_issue,
      created_at: created_at.utc.iso8601
    }
  end

  let(:cached_references) { placeholder_user_references(Import::SOURCE_GITHUB, project.import_state.id) }

  subject(:execute) { described_class.new(repository, client: client).execute(provider_event) }

  shared_examples 'creates nothing' do
    it 'creates no event and no label' do
      expect { execute }.to not_change { ResourceLabelEvent.count }
        .and not_change { ResourceMilestoneEvent.count }
        .and not_change { Label.count }
    end
  end

  describe 'label events' do
    where(:event_type, :provider_issue, :issuable_key, :action) do
      'labeled'   | { number: 4, pull_request: nil }            | :issue_id         | 'add'
      'unlabeled' | { number: 5, pull_request: { url: 'pr' } }  | :merge_request_id | 'remove'
    end

    with_them do
      it 'creates the event for the placeholder user' do
        expect { execute }.to change { ResourceLabelEvent.count }.by(1)

        issuable_id = issuable_key == :issue_id ? issue.id : merge_request.id
        expect(ResourceLabelEvent.last).to have_attributes(
          issuable_key => issuable_id,
          label_id: label.id,
          action: action,
          user_id: source_user.mapped_user_id,
          created_at: created_at,
          imported_from: 'github'
        )
        expect(cached_references).to contain_exactly(
          ['ResourceLabelEvent', an_instance_of(Integer), 'user_id', source_user.id]
        )
      end
    end

    it 'creates the event once when applied twice' do
      expect do
        described_class.new(repository, client: client).execute(provider_event)
        described_class.new(repository, client: client).execute(provider_event)
      end.to change { ResourceLabelEvent.count }.by(1)
    end

    context 'when the initial import already created the event' do
      before do
        create(:resource_label_event, issue: issue, label: label, action: :add, created_at: created_at,
          imported_from: :github)
      end

      it_behaves_like 'creates nothing'
    end

    context 'when the label finder cached a miss for the label' do
      before do
        cache_key = Gitlab::GithubImport::LabelFinder.new(project).cache_key_for('bug')
        Gitlab::Cache::Import::Caching.write(cache_key, Gitlab::GithubImport::LabelFinder::CACHE_OBJECT_NOT_FOUND)
      end

      it 'still links the event to the label' do
        execute

        expect(ResourceLabelEvent.last.label_id).to eq(label.id)
      end
    end

    context 'when the label does not exist in GitLab' do
      before do
        provider_event[:label] = { name: 'new-on-github', color: 'ffffff' }
      end

      it_behaves_like 'creates nothing'
    end
  end

  describe 'milestone events' do
    where(:event_type, :provider_issue, :issuable_key, :action) do
      'milestoned'   | { number: 4, pull_request: nil }           | :issue_id         | 'add'
      'demilestoned' | { number: 5, pull_request: { url: 'pr' } } | :merge_request_id | 'remove'
    end

    with_them do
      it 'creates the event for the placeholder user' do
        expect { execute }.to change { ResourceMilestoneEvent.count }.by(1)

        issuable_id = issuable_key == :issue_id ? issue.id : merge_request.id
        expect(ResourceMilestoneEvent.last).to have_attributes(
          issuable_key => issuable_id,
          milestone_id: milestone.id,
          action: action,
          user_id: source_user.mapped_user_id,
          created_at: created_at,
          imported_from: 'github'
        )
      end
    end

    context 'when the initial import already created the event' do
      let(:event_type) { 'milestoned' }

      before do
        create(:resource_milestone_event, issue: issue, milestone: milestone, action: :add, created_at: created_at,
          imported_from: :github)
      end

      it_behaves_like 'creates nothing'
    end

    context 'when the milestone does not exist in GitLab' do
      let(:event_type) { 'milestoned' }

      before do
        provider_event[:milestone] = { title: 'v2' }
      end

      it_behaves_like 'creates nothing'
    end
  end

  context 'when the issuable finder cached a miss for the issue' do
    before do
      representation = Gitlab::GithubImport::Representation::IssueEvent.from_api_response(provider_event)
      Gitlab::GithubImport::IssuableFinder.new(project, representation)
        .cache_database_id(Gitlab::GithubImport::IssuableFinder::CACHE_OBJECT_NOT_FOUND)
    end

    it 'still links the event to the issue' do
      execute

      expect(ResourceLabelEvent.last.issue_id).to eq(issue.id)
    end
  end

  context 'when sync has not created the issue yet' do
    let(:provider_issue) { { number: 99, pull_request: nil } }

    it_behaves_like 'creates nothing'
  end

  context 'when sync has not created the merge request yet' do
    let(:provider_issue) { { number: 98, pull_request: { url: 'pr' } } }

    it_behaves_like 'creates nothing'
  end

  context 'when the event type is out of scope' do
    let(:event_type) { 'closed' }

    it_behaves_like 'creates nothing'
  end
end
