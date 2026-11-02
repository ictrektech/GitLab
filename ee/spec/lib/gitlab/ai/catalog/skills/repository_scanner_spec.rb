# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ai::Catalog::Skills::RepositoryScanner, feature_category: :ai_catalog_curation do
  using RSpec::Parameterized::TableSyntax

  # Contexts that stub the project itself, or mutate its repository, keep `let`: a `let_it_be`
  # record is frozen, and rspec-mocks cannot proxy a frozen object.
  let(:files) { {} }
  let(:project) { create(:project, :custom_repo, files: files) }

  subject(:scan) { described_class.new(project).scan }

  # An instance method, not a `let`: a `let_it_be` block runs in a `before(:all)` hook, where
  # `let` declarations are unavailable but instance methods are.
  def skill_file(name, front_matter = '', directory: name)
    { "skills/#{directory}/SKILL.md" => "---\nname: #{name}\ndescription: Does a thing\n#{front_matter}---\n\nBody\n" }
  end

  describe '#scan' do
    context 'with a valid skill' do
      let_it_be(:project) do
        create(:project, :custom_repo,
          files: skill_file('cosign', "license: MIT\ncompatibility: Duo CLI\nallowed-tools: Bash\n"))
      end

      it 'returns the skill, pointing at the blob it was read from', :aggregate_failures do
        expect(scan.skills).to contain_exactly(
          have_attributes(
            path: 'skills/cosign/SKILL.md',
            name: 'cosign',
            description: 'Does a thing',
            blob_sha: project.repository.blob_at(project.default_branch, 'skills/cosign/SKILL.md').id,
            visibility: 'private',
            license: 'MIT',
            compatibility: 'Duo CLI',
            allowed_tools: 'Bash'
          )
        )
        expect(scan.rejections).to be_empty
        expect(scan).not_to be_truncated
      end

      it 'lists one level, checks the paths exist, then reads them, all at HEAD' do
        sha = project.repository.commit.sha

        expect(project.repository).to receive(:tree)
          .with(sha, ::Gitlab::Ai::Catalog::Skills::Path::ROOT)
          .once.and_call_original
        expect(project.repository).to receive(:get_blob_types)
          .with([[sha, 'skills/cosign/SKILL.md']], 1)
          .once.and_call_original
        expect(project.repository).to receive(:blobs_at)
          .with([[sha, 'skills/cosign/SKILL.md']], blob_size_limit: described_class::MAX_READ_BYTES)
          .once.and_call_original

        scan
      end

      it 'does not search the whole repository' do
        expect(project.repository).not_to receive(:search_files_by_regexp)

        scan
      end
    end

    context 'with CRLF line endings' do
      let(:files) { { 'skills/crlf/SKILL.md' => "---\r\nname: crlf\r\ndescription: Windows\r\n---\r\n\r\nBody\r\n" } }

      it 'parses the front matter' do
        expect(scan.skills).to contain_exactly(have_attributes(name: 'crlf', description: 'Windows'))
      end
    end

    context 'with files at other paths' do
      let(:files) do
        skill_file('good').merge(
          'skills/good/references/notes.md' => '# notes',
          'skills/nested/deeper/SKILL.md' => "---\nname: deeper\ndescription: D\n---\n",
          'docs/SKILL.md' => "---\nname: docs\ndescription: D\n---\n"
        )
      end

      it 'reads only skills/<name>/SKILL.md', :aggregate_failures do
        expect(scan.skills.map(&:path)).to contain_exactly('skills/good/SKILL.md')
        expect(scan.rejections).to be_empty
        expect(scan).not_to be_truncated
      end

      it 'never asks for a skill\'s own files' do
        expect(project.repository).to receive(:blobs_at)
          .with([[anything, 'skills/good/SKILL.md']], anything)
          .and_call_original

        scan
      end
    end

    context 'with a file the Validator rejects' do
      let_it_be(:project) do
        create(:project, :custom_repo, files: skill_file('good').merge(skill_file('sigstore', directory: 'cosign')))
      end

      it 'returns the Rejection alongside the valid skills', :aggregate_failures do
        expect(scan.skills.map(&:path)).to contain_exactly('skills/good/SKILL.md')
        expect(scan.rejections).to contain_exactly(
          have_attributes(path: 'skills/cosign/SKILL.md', code: :name_directory_mismatch, category: :spec)
        )
      end

      it 'logs the Rejection' do
        allow(::Gitlab::AppJsonLogger).to receive(:warn)

        scan

        expect(::Gitlab::AppJsonLogger).to have_received(:warn).with(
          hash_including('message' => 'Rejected skill file', 'path' => 'skills/cosign/SKILL.md', 'category' => 'spec')
        )
      end
    end

    context 'with a file larger than the read limit' do
      let(:files) { skill_file('large') }

      before do
        stub_const("#{described_class}::MAX_READ_BYTES", 8)
      end

      it 'returns a platform Rejection from BlobCheck', :aggregate_failures do
        expect(scan.rejections).to contain_exactly(have_attributes(path: 'skills/large/SKILL.md', category: :platform))
        expect(scan.skills).to be_empty
      end
    end

    context 'when the repository has no skills directory' do
      let(:files) { { 'README.md' => '# readme' } }

      it 'returns an empty, complete result rather than failing to list it' do
        expect(scan).to eq(described_class::ScanResult.new(skills: [], rejections: [], truncated: false))
      end
    end

    context 'when the skills directory holds no skill files' do
      let(:files) { { 'skills/not-a-skill/notes.md' => '# notes' } }

      it 'returns an empty, complete result, because absent is not unread' do
        expect(scan).to eq(described_class::ScanResult.new(skills: [], rejections: [], truncated: false))
      end
    end

    context 'when a directory beside a skill holds no SKILL.md' do
      let(:files) { skill_file('alpha').merge('skills/not-a-skill/notes.md' => '# notes') }

      it 'discards it without marking the scan truncated', :aggregate_failures do
        expect(scan.skills.map(&:name)).to contain_exactly('alpha')
        expect(scan.rejections).to be_empty
        expect(scan).not_to be_truncated
      end
    end

    context 'when a tag has the same name as the default branch' do
      let(:files) { { 'README.md' => '# readme' }.merge(skill_file('alpha')) }

      it 'reads the branch, not the tag', :aggregate_failures do
        earlier_commit = project.repository.commit.parent_id

        expect(project.repository.add_tag(project.creator, project.default_branch, earlier_commit)).to be_truthy
        expect(scan.skills.map(&:name)).to contain_exactly('alpha')
      end
    end

    context 'when the default branch does not resolve to a commit' do
      let(:files) { skill_file('alpha') }

      before do
        allow(project).to receive(:default_branch).and_return('missing')
      end

      it 'returns nil without listing, because an unresolved branch is not an empty one' do
        expect(project.repository).not_to receive(:tree)

        expect(scan).to be_nil
      end
    end

    context 'when the project has no default branch' do
      let(:project) { build(:project) }

      before do
        allow(project).to receive(:default_branch).and_return(nil)
      end

      it 'returns nil' do
        expect(scan).to be_nil
      end
    end

    context 'when the repository cannot be read' do
      let(:files) { skill_file('alpha') }
      let(:error) { GRPC::Unavailable.new }

      before do
        allow(project.repository).to receive(:tree).and_raise(error)
      end

      it 'returns nil, not an empty result, and tracks the error' do
        expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(error, project_id: project.id)

        expect(scan).to be_nil
      end
    end

    context 'when there are more skill directories than the scan limit' do
      let_it_be(:project) do
        create(:project, :custom_repo, files: skill_file('beta').merge(skill_file('alpha')))
      end

      before do
        stub_const("#{described_class}::MAX_SKILLS", 1)
      end

      it 'keeps the first in tree order and reports the scan as truncated', :aggregate_failures do
        expect(scan.skills.map(&:name)).to contain_exactly('alpha')
        expect(scan).to be_truncated
      end

      it 'does not read the directories it skipped' do
        expect(project.repository).to receive(:get_blob_types)
          .with([[anything, 'skills/alpha/SKILL.md']], 1)
          .and_call_original

        scan
      end

      it 'logs how many directories were left unread' do
        allow(::Gitlab::AppJsonLogger).to receive(:warn)

        scan

        expect(::Gitlab::AppJsonLogger).to have_received(:warn).with(
          hash_including(
            'message' => 'Skill directories over the scan limit were not read',
            'limit' => 1,
            'ignored_count' => 1,
            'sample_paths' => ['skills/beta']
          )
        )
      end
    end

    context 'when a file found by the search is missing from the batch read' do
      let_it_be(:project) do
        create(:project, :custom_repo, files: skill_file('alpha').merge(skill_file('beta')))
      end

      before do
        allow(project.repository).to receive(:blobs_at).and_wrap_original do |original, items, **kwargs|
          original.call(items.reject { |_ref, path| path == 'skills/beta/SKILL.md' }, **kwargs)
        end
      end

      it 'reports the scan as truncated, because an unread file is not a removed one', :aggregate_failures do
        expect(scan.skills.map(&:name)).to contain_exactly('alpha')
        expect(scan).to be_truncated
      end

      it 'logs the unread paths' do
        allow(::Gitlab::AppJsonLogger).to receive(:warn)

        scan

        expect(::Gitlab::AppJsonLogger).to have_received(:warn).with(
          hash_including('unread_count' => 1, 'sample_paths' => ['skills/beta/SKILL.md'])
        )
      end
    end

    # One project for the whole group: each case is its own skill directory, named after what its
    # front matter does, rather than a project per case.
    describe 'visibility' do
      let_it_be(:project) do
        create(:project, :custom_repo, files: [
          skill_file('no-metadata'),
          skill_file('other-metadata', "metadata:\n  author: someone\n"),
          skill_file('namespaced-public', "metadata:\n  gitlab.visibility: public\n"),
          skill_file('namespaced-restricted', "metadata:\n  gitlab.visibility: restricted\n"),
          skill_file('namespaced-padded', %(metadata:\n  gitlab.visibility: "  PUBLIC  "\n)),
          skill_file('namespaced-empty', %(metadata:\n  gitlab.visibility: ""\n)),
          skill_file('namespaced-unknown', "metadata:\n  gitlab.visibility: interal\n"),
          skill_file('bare-key', "metadata:\n  visibility: public\n"),
          skill_file('both-keys', "metadata:\n  visibility: public\n  gitlab.visibility: restricted\n"),
          skill_file('not-a-mapping', "metadata: public\n")
        ].reduce(:merge))
      end

      where(:skill, :visibility) do
        'no-metadata'           | 'private'
        'other-metadata'        | 'private'
        'namespaced-public'     | 'public'
        'namespaced-restricted' | 'restricted'
        'namespaced-padded'     | 'public'
        'namespaced-empty'      | 'private'
        'namespaced-unknown'    | 'private'
        # The un-namespaced key is ignored, so a `visibility` written for another tool cannot
        # publish a skill its author never meant to share.
        'bare-key'              | 'private'
        'both-keys'             | 'restricted'
      end

      with_them do
        it 'reads it from the metadata map' do
          expect(scan.skills.to_h { |item| [item.name, item.visibility] }[skill]).to eq(visibility)
        end
      end

      it 'rejects a skill whose metadata is not a mapping, rather than guessing', :aggregate_failures do
        expect(scan.skills.map(&:name)).not_to include('not-a-mapping')
        expect(scan.rejections).to contain_exactly(
          have_attributes(path: 'skills/not-a-mapping/SKILL.md', code: :invalid_metadata)
        )
      end

      it 'logs an unrecognised value' do
        allow(::Gitlab::AppJsonLogger).to receive(:warn)

        scan

        expect(::Gitlab::AppJsonLogger).to have_received(:warn).with(
          hash_including(
            'message' => 'Unknown skill visibility, defaulting to private',
            'path' => 'skills/namespaced-unknown/SKILL.md'
          )
        )
      end
    end
  end
end
