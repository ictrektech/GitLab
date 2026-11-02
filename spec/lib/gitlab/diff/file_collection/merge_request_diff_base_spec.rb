# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Diff::FileCollection::MergeRequestDiffBase, feature_category: :code_review_workflow do
  using RSpec::Parameterized::TableSyntax

  let(:merge_request) { create(:merge_request) }
  let(:diffable) { merge_request.merge_request_diff }

  describe '#overflow?' do
    subject(:overflown) { described_class.new(diffable, diff_options: nil).overflow? }

    context 'when it is not overflown' do
      it 'returns false' do
        expect(overflown).to be(false)
      end
    end

    context 'when it is overflown' do
      before do
        diffable.update!(state: :overflow)
      end

      it 'returns true' do
        expect(overflown).to be(true)
      end
    end
  end

  describe '#diff_files' do
    subject(:diff_files) { described_class.new(diffable, diff_options: nil).diff_files }

    it 'measures diffs_highlight_cache_decorate' do
      allow(Gitlab::Metrics).to receive(:measure).and_call_original
      expect(Gitlab::Metrics).to receive(:measure).with(:diffs_highlight_cache_decorate).and_call_original

      diff_files
    end

    context 'with blobs larger than OVERSIZED_BLOB_SIZE' do
      let_it_be(:project) { create(:project, :repository) }
      let_it_be_with_reload(:merge_request) do
        repository = project.repository
        user = project.creator
        # Old content and new content. The edited file keeps enough lines for Git to detect the rename.
        renamed_files = {
          'rename-large.txt' => ["b\n" * 100, "b\n" * 100],
          'rename-small.txt' => ["c\n" * 5, "c\n" * 5],
          'rename-edited.txt' => ["d\n" * 100, "#{"d\n" * 99}e\n"]
        }

        repository.create_branch('oversized-base', 'master')
        { 'deleted.bin' => "\0\1" * 50, 'modified.bin' => "\0\2" * 50 }.each do |path, content|
          repository.create_file(user, path, content, message: "Add #{path}", branch_name: 'oversized-base')
        end
        renamed_files.each do |path, (content, _)|
          repository.create_file(user, path, content, message: "Add #{path}", branch_name: 'oversized-base')
        end

        repository.create_branch('oversized-blobs', 'oversized-base')
        { 'large.bin' => "\0" * 100, 'large.txt' => "a\n" * 100, 'small.bin' => "\0" * 10 }.each do |path, content|
          repository.create_file(user, path, content, message: "Add #{path}", branch_name: 'oversized-blobs')
        end
        repository.update_file(user, 'modified.bin', "\0" * 10, message: 'Shrink', branch_name: 'oversized-blobs')
        repository.delete_file(user, 'deleted.bin', message: 'Delete', branch_name: 'oversized-blobs')
        renamed_files.each do |path, (_, content)|
          repository.update_file(user, path.sub('rename-', 'renamed-'), content,
            previous_path: path, message: "Rename #{path}", branch_name: 'oversized-blobs')
        end

        create(:merge_request, source_project: project, source_branch: 'oversized-blobs',
          target_branch: 'oversized-base')
      end

      let(:diffable) { merge_request.merge_request_diff }
      let(:diff_file) { diff_files.find { |file| file.old_path == path } }

      before do
        stub_const("#{described_class}::OVERSIZED_BLOB_SIZE", 50)
      end

      context 'when the diff has a binary notice and the blob is above the limit' do
        let(:path) { 'large.bin' }

        it 'measures diffs_oversized_blobs_check' do
          allow(Gitlab::Metrics).to receive(:measure).and_call_original
          expect(Gitlab::Metrics).to receive(:measure).with(:diffs_oversized_blobs_check).and_call_original

          diff_file
        end

        it 'marks the diff as too large and loads only the blob metadata' do
          expect(diff_file).to be_too_large
          expect(diff_file.viewer.render_error).to eq(:too_large)
          expect(diff_file.new_blob.raw_size).to eq(100)
          expect(diff_file.new_blob.data.bytesize).to eq(0)
        end

        it 'loads the blob metadata with a single Gitaly call', :request_store do
          diff_file

          expect { diff_file.new_blob }.not_to change { Gitlab::GitalyClient.get_request_count }
        end

        context 'when skip_oversized_diff_blobs is disabled' do
          before do
            stub_feature_flags(skip_oversized_diff_blobs: false)
          end

          it 'loads the blob content' do
            expect(diff_file).not_to be_too_large
            expect(diff_file.new_blob.data.bytesize).to eq(100)
          end
        end

        context 'when the merge request diff has no diff refs' do
          before do
            allow(diffable).to receive_messages(diff_refs: nil, fallback_diff_refs: nil)
          end

          it 'does not mark the diff as too large' do
            expect(diff_file).not_to be_too_large
          end
        end

        context 'when the collection is over its safe limits' do
          before do
            # Safe file limit is 1, so every diff after the first is collapsed.
            stub_application_setting(diff_max_files: 10)
          end

          it 'marks the collapsed diff as too large and loads only the blob metadata', :aggregate_failures do
            expect(diff_file).to be_collapsed
            expect(diff_file).to be_too_large
            expect(diff_file.new_blob.raw_size).to eq(100)
            expect(diff_file.new_blob.data.bytesize).to eq(0)
          end

          context 'when the diffs are loaded from Gitaly' do
            # `ignore_whitespace_change` makes `raw_diffs` read from Gitaly, which drops the patch of collapsed diffs.
            subject(:diff_files) do
              described_class.new(diffable, diff_options: { ignore_whitespace_change: true }).diff_files
            end

            it 'marks the collapsed diff as too large' do
              expect(diff_file).to be_collapsed
              expect(diff_file).to be_too_large
            end
          end
        end
      end

      context 'when a text diff is collapsed and its blob is above the limit' do
        let(:path) { 'large.txt' }

        before do
          stub_application_setting(diff_max_files: 10)
        end

        it 'loads the blob content' do
          expect(diff_file).to be_collapsed
          expect(diff_file).not_to be_too_large
          expect(diff_file.new_blob.data.bytesize).to eq(200)
        end
      end

      context 'when the stored diff is too large and the blob is above the limit' do
        let(:path) { 'large.txt' }

        before do
          # Mimics a text patch over `diff_max_patch_bytes`, which is stored without content.
          diffable.merge_request_diff_files.by_paths([path]).first.update!(too_large: true, diff: '')
        end

        it 'loads only the blob metadata' do
          expect(diff_file).to be_too_large
          expect(diff_file.new_blob.raw_size).to eq(200)
          expect(diff_file.new_blob.data.bytesize).to eq(0)
        end
      end

      context 'when a file is renamed without changes and its blob is above the limit' do
        let(:path) { 'rename-large.txt' }

        it 'marks the diff as too large and loads only the blob metadata', :aggregate_failures do
          expect(diff_file).to be_renamed_file
          expect(diff_file).to be_too_large
          expect(diff_file.old_blob.raw_size).to eq(200)
          expect(diff_file.old_blob.data.bytesize).to eq(0)
          expect(diff_file.new_blob.raw_size).to eq(200)
          expect(diff_file.new_blob.data.bytesize).to eq(0)
        end
      end

      context 'when the old blob is above the limit' do
        where(:path) { %w[deleted.bin modified.bin] }

        with_them do
          it 'marks the diff as too large and loads only the old blob metadata' do
            expect(diff_file).to be_too_large
            expect(diff_file.old_blob.raw_size).to eq(100)
            expect(diff_file.old_blob.data.bytesize).to eq(0)
          end
        end
      end

      where(:path, :size) do
        'large.txt'         | 200
        'small.bin'         | 10
        'rename-small.txt'  | 10
        'rename-edited.txt' | 200
      end

      with_them do
        it 'loads the blob content' do
          expect(diff_file).not_to be_too_large
          expect(diff_file.new_blob.data.bytesize).to eq(size)
        end
      end
    end
  end

  describe '#cache_key' do
    subject(:cache_key) { described_class.new(diffable, diff_options: nil).cache_key }

    it 'returns cache_key from merge_request_diff' do
      expect(cache_key).to eq diffable.cache_key
    end
  end

  describe '.max_blob_size' do
    before do
      allow(Gitlab::Highlight).to receive(:file_size_limit).and_return(max_config)
    end

    context 'when MAX_BLOB_SIZE constant is larger' do
      let(:max_config) { described_class::MAX_BLOB_SIZE - 1 }

      it 'returns the MAX_BLOB_SIZE constant' do
        expect(described_class.max_blob_size).to eq(described_class::MAX_BLOB_SIZE)
      end
    end

    context 'when maximum_text_highlight_size_kilobytes setting is larger' do
      let(:max_config) { described_class::MAX_BLOB_SIZE + 1 }

      it 'returns the maximum_text_highlight_size_kilobytes setting' do
        expect(described_class.max_blob_size).to eq(max_config)
      end
    end
  end
end
