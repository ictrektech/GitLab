# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::FixPipeline::Definition, feature_category: :duo_agent_platform do
  subject(:flow) { Ai::Catalog::FoundationalFlow.fix_pipeline_v1 }

  let_it_be(:project) { create(:project) }

  describe '#supported_events' do
    it 'is limited to pipeline_hooks' do
      expect(flow.supported_events).to eq([::Ai::FlowTrigger::EVENT_TYPES[:pipeline_hooks]])
    end
  end

  describe '#precondition' do
    it_behaves_like 'a foundational flow precondition',
      hook_scope: :pipeline_hooks, field: 'object_attributes.status',
      allowed: %w[failed], denied: %w[success running canceled skipped]
  end

  describe '#resolve_flow_version_for' do
    subject(:resolved) { flow.resolve_flow_version_for(container: project, user: nil) }

    context 'when fix_pipeline_experimental is disabled' do
      before do
        stub_feature_flags(fix_pipeline_experimental: false)
      end

      it 'returns the flow own reference and version' do
        expect(resolved).to eq(
          flow_config_id: 'fix_pipeline',
          flow_config_schema_version: 'v1',
          flow_version: '1.0.4'
        )
      end
    end

    context 'when fix_pipeline_experimental is enabled for the project' do
      before do
        stub_feature_flags(fix_pipeline_experimental: project)
      end

      it 'overrides to fix_pipeline/experimental' do
        expect(resolved).to eq(
          flow_config_id: 'fix_pipeline',
          flow_config_schema_version: 'experimental',
          flow_version: '1.0.0'
        )
      end
    end

    context 'when fix_pipeline_experimental is enabled for the root ancestor' do
      before do
        stub_feature_flags(fix_pipeline_experimental: project.root_ancestor)
      end

      it 'overrides to fix_pipeline/experimental' do
        expect(resolved).to eq(
          flow_config_id: 'fix_pipeline',
          flow_config_schema_version: 'experimental',
          flow_version: '1.0.0'
        )
      end
    end
  end

  describe '#resolve_noteable_for' do
    context 'with a valid pipeline URL for a merge request pipeline' do
      let_it_be(:merge_request) { create(:merge_request, source_project: project) }
      let_it_be(:pipeline) do
        create(:ci_pipeline, project: project, merge_request: merge_request)
      end

      let(:goal) { "https://gitlab.com/#{project.full_path}/-/pipelines/#{pipeline.id}" }

      it 'returns the merge request' do
        expect(flow.resolve_noteable_for(project: project, goal: goal)).to eq(merge_request)
      end
    end

    context 'when the pipeline is associated with a merged merge request' do
      let_it_be(:merge_request) { create(:merge_request, :merged, source_project: project) }
      let_it_be(:pipeline) do
        create(:ci_pipeline, project: project, merge_request: merge_request)
      end

      let(:goal) { "https://gitlab.com/#{project.full_path}/-/pipelines/#{pipeline.id}" }

      it 'returns nil' do
        expect(flow.resolve_noteable_for(project: project, goal: goal)).to be_nil
      end
    end

    context 'when the pipeline has no associated merge request' do
      let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
      let(:goal) { "https://gitlab.com/#{project.full_path}/-/pipelines/#{pipeline.id}" }

      it 'returns nil' do
        expect(flow.resolve_noteable_for(project: project, goal: goal)).to be_nil
      end
    end

    context 'when a branch pipeline has an open merge request for its branch' do
      let_it_be(:project) { create(:project, :repository) }
      let_it_be(:merge_request) do
        create(:merge_request, source_project: project, source_branch: 'feature', target_branch: 'master')
      end

      let_it_be(:pipeline) do
        create(:ci_pipeline, project: project, ref: merge_request.source_branch, sha: merge_request.diff_head_sha)
      end

      let(:goal) { "https://gitlab.com/#{project.full_path}/-/pipelines/#{pipeline.id}" }

      it 'returns the merge request for the pipeline ref' do
        expect(flow.resolve_noteable_for(project: project, goal: goal)).to eq(merge_request)
      end
    end

    context 'when the merge request for the branch is closed' do
      let_it_be(:project) { create(:project, :repository) }
      let_it_be(:merge_request) do
        create(:merge_request, :closed, source_project: project, source_branch: 'feature', target_branch: 'master')
      end

      let_it_be(:pipeline) do
        create(:ci_pipeline, project: project, ref: merge_request.source_branch, sha: merge_request.diff_head_sha)
      end

      let(:goal) { "https://gitlab.com/#{project.full_path}/-/pipelines/#{pipeline.id}" }

      it 'returns nil' do
        expect(flow.resolve_noteable_for(project: project, goal: goal)).to be_nil
      end
    end

    context 'with a malformed goal URL' do
      it 'returns nil' do
        expect(flow.resolve_noteable_for(project: project, goal: 'not-a-url')).to be_nil
      end
    end

    context 'with a nil goal' do
      it 'returns nil' do
        expect(flow.resolve_noteable_for(project: project, goal: nil)).to be_nil
      end
    end

    context 'when the pipeline belongs to a different project' do
      let_it_be(:other_project) { create(:project) }
      let_it_be(:other_pipeline) { create(:ci_pipeline, project: other_project) }
      let(:goal) { "https://gitlab.com/#{other_project.full_path}/-/pipelines/#{other_pipeline.id}" }

      it 'returns nil because the pipeline is scoped to the given project' do
        expect(flow.resolve_noteable_for(project: project, goal: goal)).to be_nil
      end
    end
  end

  describe '#resolve_source_pipeline_for' do
    context 'with a valid pipeline URL' do
      let_it_be(:pipeline) { create(:ci_pipeline, project: project) }
      let(:goal) { "https://gitlab.com/#{project.full_path}/-/pipelines/#{pipeline.id}" }

      it 'returns the pipeline' do
        expect(flow.resolve_source_pipeline_for(project: project, goal: goal)).to eq(pipeline)
      end
    end

    context 'with a malformed goal URL' do
      it 'returns nil' do
        expect(flow.resolve_source_pipeline_for(project: project, goal: 'not-a-url')).to be_nil
      end
    end

    context 'with a nil goal' do
      it 'returns nil' do
        expect(flow.resolve_source_pipeline_for(project: project, goal: nil)).to be_nil
      end
    end

    context 'when the pipeline belongs to a different project' do
      let_it_be(:other_project) { create(:project) }
      let_it_be(:other_pipeline) { create(:ci_pipeline, project: other_project) }
      let(:goal) { "https://gitlab.com/#{other_project.full_path}/-/pipelines/#{other_pipeline.id}" }

      it 'returns nil because the pipeline is scoped to the given project' do
        expect(flow.resolve_source_pipeline_for(project: project, goal: goal)).to be_nil
      end
    end
  end
end
