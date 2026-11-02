# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::Skills::PublishService, feature_category: :ai_catalog_curation do
  let_it_be(:project) { create(:project, :small_repo) }

  subject(:service) { described_class.new(project: project) }

  # Skill is a Data type, so every member has to be given. A skill is named after the directory it
  # is in, as the Validator requires.
  def skill(name, description: 'Does a thing', blob_sha: 'a' * 40, visibility: 'private')
    ::Gitlab::Ai::Catalog::Skills::RepositoryScanner::Skill.new(
      path: "skills/#{name}/SKILL.md",
      name: name,
      description: description,
      blob_sha: blob_sha,
      visibility: visibility,
      license: nil,
      compatibility: nil,
      allowed_tools: nil
    )
  end

  def rejection(path, message: 'name is required.')
    ::Gitlab::Ai::Catalog::Skills::Validator::Rejection.new(
      path: path, code: :invalid_name, message: message, category: :spec
    )
  end

  # `nil` stands for a scan that could not read the repository at all.
  def stub_scan(skills, rejections: [], truncated: false)
    result = skills && ::Gitlab::Ai::Catalog::Skills::RepositoryScanner::ScanResult.new(
      skills: skills, rejections: rejections, truncated: truncated
    )

    allow_next_instance_of(::Gitlab::Ai::Catalog::Skills::RepositoryScanner) do |scanner|
      allow(scanner).to receive(:scan).and_return(result)
    end
  end

  # A publish is one run, so a second one needs its own instance.
  def publish
    described_class.new(project: project).execute
  end

  def skill_items
    ::Ai::Catalog::Item.for_project(project).with_item_type(:skill).not_deleted
  end

  def skill_item(name = 'alpha')
    skill_items.find_by(name: name)
  end

  describe '#execute' do
    context 'when the repository has skills' do
      before do
        stub_scan([skill('alpha'), skill('beta', blob_sha: 'b' * 40)])
      end

      it 'creates an item and a released version per skill', :aggregate_failures do
        expect { service.execute }.to change { skill_items.count }.from(0).to(2)

        item = skill_item
        expect(item.latest_version.version).to eq('1.0.0')
        expect(item.latest_version).to be_released
        expect(item.latest_released_version).to eq(item.latest_version)
        expect(item.definition.path).to eq('skills/alpha/SKILL.md')
        expect(item.definition.blob_sha).to eq('a' * 40)
        expect(item.definition.git_ref).to eq(project.default_branch)
      end

      it 'reports every bucket, so a caller never has to check for a key' do
        expect(service.execute.payload).to match(
          created: match_array(['skills/alpha/SKILL.md', 'skills/beta/SKILL.md']),
          updated: [], deleted: [], unchanged: [], failed: [], unpublishable: []
        )
      end
    end

    context 'when publishing again with no repository change' do
      before do
        stub_scan([skill('alpha')])
        service.execute
      end

      it 'creates no further versions' do
        expect { publish }.not_to change { ::Ai::Catalog::ItemVersion.count }
      end

      it 'writes nothing' do
        recorder = ActiveRecord::QueryRecorder.new { publish }

        expect(recorder.log.grep(/\A(INSERT|UPDATE|DELETE)/)).to be_empty
      end

      it 'looks up no commit, because attribution is only read for a skill that changed' do
        expect(project.repository).not_to receive(:last_commit_for_path)

        expect(publish.payload[:unchanged]).to contain_exactly('skills/alpha/SKILL.md')
      end
    end

    context 'when a skill changed' do
      before do
        stub_scan([skill('alpha')])
        service.execute
        stub_scan([skill('alpha', description: 'Does another thing', blob_sha: 'c' * 40)])
      end

      it 'mints a new released version with a minor bump', :aggregate_failures do
        expect(publish.payload[:updated]).to contain_exactly('skills/alpha/SKILL.md')

        item = skill_item
        expect(item.versions.count).to eq(2)
        expect(item.latest_version.version).to eq('1.1.0')
        expect(item.latest_released_version.version).to eq('1.1.0')
        expect(item.description).to eq('Does another thing')
        expect(item.definition.blob_sha).to eq('c' * 40)
      end
    end

    context 'when only the metadata changed' do
      before do
        stub_scan([skill('alpha')])
        service.execute
        stub_scan([skill('alpha', description: 'Does another thing')])
      end

      it 'updates the item without minting a version, because the blob is unchanged',
        :aggregate_failures do
        expect { publish }.not_to change { ::Ai::Catalog::ItemVersion.count }

        expect(skill_item.description).to eq('Does another thing')
      end
    end

    # Nothing creates a draft skill version today, but ItemVersion allows one, and the released
    # pointer must never be moved onto it.
    context 'when the item\'s latest version was never released' do
      before do
        item = create(:ai_catalog_skill, project: project, name: 'alpha')
        item.latest_version.update!(definition: {
          'path' => 'skills/alpha/SKILL.md', 'git_ref' => project.default_branch, 'blob_sha' => 'a' * 40
        })

        stub_scan([skill('alpha', description: 'Does another thing')])
      end

      it 'updates the item but leaves the released pointer alone', :aggregate_failures do
        expect(publish.payload[:updated]).to contain_exactly('skills/alpha/SKILL.md')

        item = skill_item
        expect(item.description).to eq('Does another thing')
        expect(item.latest_released_version).to be_nil
      end
    end

    context 'when a SKILL.md was removed' do
      before do
        stub_scan([skill('alpha')])
        service.execute
        stub_scan([])
      end

      it 'soft-deletes the item rather than destroying it, so its versions survive',
        :aggregate_failures do
        expect { publish }.to change { skill_items.count }.from(1).to(0)

        expect(::Ai::Catalog::Item.for_project(project).with_item_type(:skill).find_by(name: 'alpha'))
          .to be_deleted
      end

      it 'reports the path it deleted' do
        expect(publish.payload[:deleted]).to contain_exactly('skills/alpha/SKILL.md')
      end

      it 'reports an item the database refuses to delete rather than aborting the publish' do
        allow_next_found_instance_of(::Ai::Catalog::Item) do |item|
          allow(item).to receive(:soft_delete).and_wrap_original do |_original|
            item.errors.add(:base, 'Cannot delete an item that has consumers')
            false
          end
        end

        expect(publish.payload[:failed]).to contain_exactly(
          { path: 'skills/alpha/SKILL.md', errors: ['Cannot delete an item that has consumers'] }
        )
      end
    end

    context 'when a published skill stops validating' do
      let(:path) { 'skills/alpha/SKILL.md' }

      before do
        stub_scan([skill('alpha')])
        service.execute
        stub_scan([], rejections: [rejection(path)])
      end

      it 'keeps the item rather than deleting it' do
        expect { publish }.not_to change { skill_items.count }
      end

      it 'keeps the last good version and its pointer', :aggregate_failures do
        expect { publish }.not_to change { ::Ai::Catalog::ItemVersion.count }

        expect(skill_item.definition.blob_sha).to eq('a' * 40)
      end

      it 'keeps the consumers that enabled the skill' do
        create(:ai_catalog_item_consumer, item: skill_item, project: project)

        expect { publish }.not_to change { ::Ai::Catalog::ItemConsumer.count }
      end

      it 'leaves the item untouched' do
        expect { publish }.not_to change { skill_item.updated_at }
      end

      it 'reports the path and the reason' do
        expect(publish.payload[:unpublishable])
          .to contain_exactly({ path: path, errors: ['name is required.'] })
      end
    end

    context 'when a skill has never validated' do
      let(:path) { 'skills/never-valid/SKILL.md' }

      before do
        stub_scan([], rejections: [rejection(path, message: 'description must not be empty.')])
      end

      it 'creates nothing, because an item cannot exist without a valid version' do
        expect { service.execute }.not_to change { skill_items.count }
      end

      it 'reports the path and the reason so the caller still sees it' do
        expect(service.execute.payload[:unpublishable])
          .to contain_exactly({ path: path, errors: ['description must not be empty.'] })
      end
    end

    context 'when the scan was truncated' do
      before do
        stub_scan([skill('alpha'), skill('beta', blob_sha: 'b' * 40)])
        service.execute
        stub_scan([skill('alpha')], truncated: true)
      end

      it 'deletes nothing, because an unread file is not an absent one' do
        expect { publish }.not_to change { skill_items.count }
      end

      it 'still reconciles the skills it did read' do
        expect(publish.payload).to include(unchanged: ['skills/alpha/SKILL.md'], deleted: [])
      end
    end

    context 'when the repository could not be read' do
      before do
        stub_scan([skill('alpha')])
        service.execute
        stub_scan(nil)
      end

      it 'returns an error and reconciles nothing', :aggregate_failures do
        response = publish

        expect(response).to be_error
        expect(response.reason).to eq(:scan_failed)
        expect(skill_items.count).to eq(1)
      end
    end

    context 'when a skill cannot be saved' do
      before do
        # Longer than Ai::Catalog::Item's description limit, so the record is invalid.
        stub_scan([skill('alpha', description: 'x' * 2000)])
      end

      it 'reports the failure rather than silently dropping the skill', :aggregate_failures do
        response = service.execute

        expect(response.payload[:created]).to be_empty
        expect(response.payload[:failed]).to contain_exactly(
          { path: 'skills/alpha/SKILL.md', errors: array_including(a_string_matching(/Description/)) }
        )
        expect(skill_items.count).to eq(0)
      end
    end

    context 'when a publish is already running for the project', :clean_gitlab_redis_shared_state do
      before do
        stub_scan([skill('alpha')])
      end

      it 'returns an error rather than racing', :aggregate_failures do
        lease = ::Gitlab::ExclusiveLease.new(
          "#{described_class::LEASE_KEY}:#{project.id}", timeout: described_class::LEASE_TTL
        )
        expect(lease.try_obtain).to be_present

        response = service.execute

        expect(response).to be_error
        expect(response.reason).to eq(:lease_taken)
        expect(skill_items.count).to eq(0)
      end
    end

    context 'when more than one item claims the same path' do
      before do
        2.times { create(:ai_catalog_skill, project: project, name: 'alpha') }
        stub_scan([skill('alpha')])
      end

      it 'logs the drift rather than silently dropping the shadowed item', :aggregate_failures do
        allow(::Gitlab::AppJsonLogger).to receive(:warn)

        expect { service.execute }.not_to change { skill_items.count }

        expect(::Gitlab::AppJsonLogger).to have_received(:warn).with(
          hash_including(
            'message' => 'Multiple AI Catalog skill items share one path',
            'path' => 'skills/alpha/SKILL.md'
          )
        )
      end
    end

    describe 'visibility' do
      it 'creates the item with the visibility the scan read from the repository' do
        stub_scan([skill('alpha', visibility: 'public')])

        service.execute

        expect(skill_item.visibility).to eq('public')
      end

      it 'raises visibility on a later publish' do
        stub_scan([skill('alpha')])
        service.execute

        stub_scan([skill('alpha', blob_sha: 'b' * 40, visibility: 'public')])
        publish

        expect(skill_item.visibility).to eq('public')
      end

      # An item enabled elsewhere cannot be pulled back, so the repository and the catalog
      # disagree and the publish says so.
      it 'reports a reduction the database refuses', :aggregate_failures do
        stub_scan([skill('alpha', visibility: 'public')])
        service.execute

        allow_next_found_instance_of(::Ai::Catalog::Item) do |item|
          allow(item).to receive(:has_external_consumers?).and_return(true)
        end

        stub_scan([skill('alpha', blob_sha: 'b' * 40, visibility: 'private')])
        response = publish

        expect(response.payload[:failed].first[:errors].join).to include('enabled outside its owning project')
        expect(skill_item.visibility).to eq('public')
      end
    end

    describe 'record loading' do
      it 'does not load the organization once per skill', :aggregate_failures do
        stub_scan([skill('alpha'), skill('beta', blob_sha: 'b' * 40), skill('gamma', blob_sha: 'c' * 40)])

        recorder = ActiveRecord::QueryRecorder.new { service.execute }

        expect(skill_items.count).to eq(3)
        expect(recorder.log.grep(/FROM "organizations"/).size).to be <= 1
      end
    end

    # These examples commit for real, so the project cannot be a frozen let_it_be one.
    describe 'author attribution' do
      let(:project) { create(:project, :small_repo) }
      let(:author) { create(:user, maintainer_of: project) }
      let(:path) { 'skills/alpha/SKILL.md' }

      def commit_skill(user, action: :create, description: 'Does a thing')
        ::Files::MultiService.new(
          project, user,
          commit_message: 'Write a skill',
          branch_name: project.default_branch,
          start_branch: project.default_branch,
          actions: [{
            action: action, file_path: path, content: "---\nname: alpha\ndescription: #{description}\n---\n"
          }]
        ).execute

        project.repository.blob_at(project.default_branch, path)
      end

      it 'records the commit author as both a name and a user', :aggregate_failures do
        blob = commit_skill(author)
        stub_scan([skill('alpha', blob_sha: blob.id)])

        service.execute

        version = skill_item.latest_version
        expect(version.created_by).to eq(author)
        expect(version.def_author_name).to eq(author.name)
        expect(version.def_commit_sha).to be_present
      end

      it 'attributes a later version to whoever changed it', :aggregate_failures do
        blob = commit_skill(author)
        stub_scan([skill('alpha', blob_sha: blob.id)])
        service.execute

        editor = create(:user, maintainer_of: project)
        changed = commit_skill(editor, action: :update, description: 'Does another thing')
        stub_scan([skill('alpha', description: 'Does another thing', blob_sha: changed.id)])
        publish

        item = skill_item
        expect(item.versions.count).to eq(2)
        expect(item.latest_version.created_by).to eq(editor)
      end

      it 'keeps the author name when the commit email matches no user', :aggregate_failures do
        blob = commit_skill(author)
        stub_scan([skill('alpha', blob_sha: blob.id)])

        commit = project.repository.commit
        allow(commit).to receive(:author).and_return(nil)
        allow(project.repository).to receive(:last_commit_for_path).and_return(commit)

        service.execute

        version = skill_item.latest_version
        expect(version.created_by).to be_nil
        expect(version.def_author_name).to eq(author.name)
      end

      it 'publishes without attribution when the commit lookup fails', :aggregate_failures do
        blob = commit_skill(author)
        stub_scan([skill('alpha', blob_sha: blob.id)])
        allow(project.repository).to receive(:last_commit_for_path)
          .and_raise(::Gitlab::Git::CommandError, 'gitaly is sulking')

        expect { service.execute }.to change { skill_items.count }.by(1)

        version = skill_item.latest_version
        expect(version.created_by).to be_nil
        expect(version.def_commit_sha).to be_nil
      end
    end
  end
end
