# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::GoalTemplates::BlSecurity, feature_category: :duo_agent_platform do
  include ProjectForksHelper

  let_it_be(:project) { create(:project, :repository) }
  let_it_be_with_refind(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

  describe '.resolve' do
    it 'returns the merge request IID for a merge request pipeline' do
      pipeline = create(:ci_pipeline, :detached_merge_request_pipeline, merge_request: merge_request)

      expect(described_class.resolve(event_type: :pipeline_hooks, resource: pipeline)).to eq(merge_request.iid.to_s)
    end

    context 'when the merge request is from a fork' do
      let_it_be(:fork) { fork_project(project, nil, repository: true) }
      let_it_be(:fork_merge_request) do
        create(:merge_request, source_project: fork, target_project: project, source_branch: 'feature')
      end

      where(:pipeline_project) { [ref(:fork), ref(:project)] }

      with_them do
        it 'returns the pipeline URL, which the goal validator refuses' do
          pipeline = create(:ci_pipeline, :detached_merge_request_pipeline,
            merge_request: fork_merge_request, project: pipeline_project)

          expect(described_class.resolve(event_type: :pipeline_hooks, resource: pipeline))
            .to eq(Gitlab::UrlBuilder.build(pipeline))
        end
      end

      context 'with a branch pipeline in the fork' do
        let(:pipeline) { create(:ci_pipeline, source: :push, project: fork, ref: 'fix') }
        let!(:upstream_merge_request) do
          create(:merge_request, source_project: fork, target_project: project, source_branch: 'fix',
            head_pipeline: pipeline)
        end

        it 'picks the merge request into the fork over the one into upstream' do
          fork_own_merge_request = create(:merge_request, source_project: fork, target_project: fork,
            source_branch: 'fix', head_pipeline: pipeline)

          expect(described_class.merge_request_for(pipeline)).to eq(fork_own_merge_request)
          expect(described_class.resolve(event_type: :pipeline_hooks, resource: pipeline))
            .to eq(fork_own_merge_request.iid.to_s)
        end

        it 'finds no merge request when only the one into upstream has it as head pipeline' do
          expect(described_class.merge_request_for(pipeline)).to be_nil
        end
      end
    end

    it 'returns the merge request IID for the branch pipeline an open merge request has as head pipeline' do
      pipeline = create(:ci_pipeline, source: :push, project: project, ref: merge_request.source_branch)
      merge_request.update!(head_pipeline: pipeline)

      expect(described_class.resolve(event_type: :pipeline_hooks, resource: pipeline)).to eq(merge_request.iid.to_s)
    end

    it 'returns the resource URL when the resource is not a pipeline' do
      expect(described_class.merge_request_for(merge_request)).to be_nil
      expect(described_class.resolve(event_type: :pipeline_hooks, resource: merge_request))
        .to eq(Gitlab::UrlBuilder.build(merge_request))
    end

    it 'picks the newest open merge request that has the branch pipeline as head pipeline' do
      pipeline = create(:ci_pipeline, source: :push, project: project, ref: merge_request.source_branch)
      merge_request.update!(head_pipeline: pipeline)
      newer_merge_request = create(:merge_request, source_project: project, target_project: project,
        source_branch: merge_request.source_branch, target_branch: 'improve/awesome', head_pipeline: pipeline)
      create(:merge_request, :closed, source_project: project, target_project: project,
        source_branch: merge_request.source_branch, target_branch: 'markdown', head_pipeline: pipeline)

      expect(described_class.merge_request_for(pipeline)).to eq(newer_merge_request)
    end

    it 'returns the pipeline URL for a non-merge-request pipeline' do
      pipeline = create(:ci_pipeline, project: project)

      expect(described_class.resolve(event_type: :pipeline_hooks, resource: pipeline))
        .to eq(Gitlab::UrlBuilder.build(pipeline))
    end

    it 'raises ArgumentError when resource is nil' do
      expect do
        described_class.resolve(event_type: :pipeline_hooks, resource: nil)
      end.to raise_error(ArgumentError, /resource must not be nil/)
    end
  end
end
