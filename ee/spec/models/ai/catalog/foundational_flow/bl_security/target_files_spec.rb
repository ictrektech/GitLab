# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::BlSecurity::TargetFiles, feature_category: :duo_agent_platform do
  include ProjectForksHelper

  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:merge_request, refind: true) { create(:merge_request, source_project: project) }

  let(:diff) { merge_request.merge_request_diff }
  let(:diff_files) { diff.merge_request_diff_files }
  let(:goal) { merge_request.iid.to_s }

  subject(:result) { described_class.for_goal(project: project, goal: goal) }

  # The factory diff (gitlab-test, master vs feature) includes "with space/README.md", a path the
  # engine cannot split, which would make every example an :unsupported_path whole-repository scan.
  before do
    MergeRequestDiffFile.where(merge_request_diff_id: diff.id)
      .update_all("new_path = replace(new_path, ' ', '_'), old_path = replace(old_path, ' ', '_')")
  end

  it 'lists the paths the merge request adds or modifies' do
    expected = diff_files.reject(&:deleted_file).map(&:new_path)

    expect(expected).not_to be_empty
    expect(result.paths).to match_array(expected)
    expect(result.reason).to be_nil
    expect(result.source_branch).to eq(merge_request.source_branch)
  end

  it 'leaves out deleted files' do
    deleted = diff_files.first
    MergeRequestDiffFile.where(merge_request_diff_id: diff.id, relative_order: deleted.relative_order)
      .update_all(deleted_file: true)

    expect(result.paths).not_to include(deleted.new_path)
    expect(result.paths).not_to be_empty
  end

  it 'lists a renamed file under its new path' do
    MergeRequestDiffFile.where(merge_request_diff_id: diff.id, relative_order: 0).update_all(
      renamed_file: true, deleted_file: false, old_path: 'old/name.rb', new_path: 'new/name.rb'
    )

    expect(result.paths).to include('new/name.rb')
    expect(result.paths).not_to include('old/name.rb')
  end

  context 'when the merge request only deletes files' do
    before do
      MergeRequestDiffFile.where(merge_request_diff_id: diff.id).update_all(deleted_file: true)
    end

    it 'returns no paths' do
      expect(result.paths).to eq([])
      expect(result.reason).to be_nil
    end
  end

  context 'when the merge request is from a fork' do
    let_it_be(:fork) { fork_project(project, nil, repository: true) }
    let_it_be(:fork_merge_request) do
      create(:merge_request, source_project: fork, target_project: project, source_branch: 'feature')
    end

    let(:goal) { fork_merge_request.iid.to_s }

    it 'returns no list, with the reason' do
      expect(result).to have_attributes(paths: nil, reason: :fork_merge_request)
    end
  end

  context 'when the diff overflowed' do
    before do
      diff.update_column(:state, 'overflow')
    end

    it 'returns no list, with the reason' do
      expect(result).to have_attributes(paths: nil, reason: :diff_overflow)
    end
  end

  context 'when the diff was not collected' do
    before do
      diff.update_column(:state, 'without_files')
    end

    it 'returns no list, with the reason' do
      expect(result).to have_attributes(paths: nil, reason: :diff_not_collected)
    end
  end

  context 'when a path contains whitespace, a comma or a semicolon' do
    where(path: ['docs/my file.md', 'a,b.rb', 'a;b.rb', "a\tb.rb"])

    with_them do
      before do
        MergeRequestDiffFile.where(merge_request_diff_id: diff.id, relative_order: 0)
          .update_all(deleted_file: false, new_path: path)
      end

      it 'returns no list, with the reason' do
        expect(result).to have_attributes(paths: nil, reason: :unsupported_path)
      end
    end
  end

  context 'with an active request store', :request_store do
    it 'runs the diff query once for repeated calls' do
      recorder = ActiveRecord::QueryRecorder.new do
        2.times { described_class.for_goal(project: project, goal: goal) }
      end

      expect(recorder.log.grep(/merge_request_diff_files/).size).to eq(1)
    end
  end

  it 'caps the list at 400 paths' do
    expect(described_class::MAX_PATHS).to eq(400)
  end

  context 'when the merge request changes more files than the limit' do
    before do
      stub_const("#{described_class}::MAX_PATHS", 1)
    end

    it 'returns no list, with the reason' do
      expect(result).to have_attributes(paths: nil, reason: :too_many_paths)
    end
  end

  context 'when no merge request has the IID' do
    let(:goal) { non_existing_record_iid.to_s }

    it 'returns no list, with the reason' do
      expect(result).to have_attributes(paths: nil, reason: :merge_request_not_found)
    end
  end

  context 'when the goal is not a merge request IID' do
    where(goal: ['http://example.com/pipelines/1', '1x', '', nil])

    with_them do
      it 'returns no list and no reason' do
        expect(result).to have_attributes(paths: nil, reason: nil)
      end
    end
  end
end
