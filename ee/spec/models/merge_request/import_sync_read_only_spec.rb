# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MergeRequest, feature_category: :code_review_workflow do # rubocop:disable RSpec/SpecFilePathFormat -- split from merge_request_spec.rb by topic
  include ProjectForksHelper

  describe '#can_be_merged_by?' do
    let_it_be_with_reload(:project) { create(:project, :repository) }
    let_it_be(:maintainer) { create(:user, maintainer_of: project) }

    let(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

    subject { merge_request.can_be_merged_by?(maintainer) }

    context 'when continuous GitHub sync is on' do
      before do
        project.update!(import_type: 'github')
        create(:import_sync_repository, project: project,
          authority_state: :provider_canonical)
        project.association(:import_sync_repository).reset
      end

      it { is_expected.to be(false) }
    end

    context 'for an ordinary project' do
      it { is_expected.to be(true) }
    end

    context 'with a fork' do
      let_it_be_with_reload(:forked_project) { fork_project(project, nil, repository: true) }
      let(:merge_request) { create(:merge_request, source_project: forked_project, target_project: project) }

      context 'when only the fork (source project) has continuous GitHub sync on' do
        before do
          forked_project.update!(import_type: 'github')
          create(:import_sync_repository, project: forked_project, authority_state: :provider_canonical)
          forked_project.association(:import_sync_repository).reset
        end

        it 'still allows merging, since only the target project matters' do
          is_expected.to be(true)
        end
      end

      context 'when only the target project has continuous GitHub sync on' do
        before do
          project.update!(import_type: 'github')
          create(:import_sync_repository, project: project, authority_state: :provider_canonical)
          project.association(:import_sync_repository).reset
        end

        it { is_expected.to be(false) }
      end
    end
  end
end
