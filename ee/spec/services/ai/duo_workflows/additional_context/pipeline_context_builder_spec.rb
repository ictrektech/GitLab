# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::AdditionalContext::PipelineContextBuilder, feature_category: :duo_agent_platform do
  let_it_be(:project) { create(:project, :repository) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project, target_project: project) }

  subject(:envelopes) { described_class.build(pipeline) }

  def contents
    envelopes.to_h { |envelope| [envelope['Category'], Gitlab::Json::SafeParser.parse(envelope['Content'])] }
  end

  context 'when the pipeline belongs to an open merge request' do
    let(:pipeline) { create(:ci_pipeline, :detached_merge_request_pipeline, merge_request: merge_request) }

    it 'names the merge request and its branch' do
      expect(contents).to eq(
        'merge_request' => {
          'url' => Gitlab::UrlBuilder.build(merge_request), 'author_id' => merge_request.author_id.to_s
        },
        'pipeline' => { 'source_branch' => merge_request.source_branch, 'source' => 'merge_request_event' }
      )
    end

    it 'versions both envelopes' do
      expect(envelopes.pluck('metadata')).to all(eq('version' => '1.0.0'))
    end
  end

  context 'when a branch pipeline has an open merge request off that branch' do
    let(:pipeline) do
      create(:ci_pipeline, project: project, ref: merge_request.source_branch, sha: merge_request.diff_head_sha)
    end

    it 'names that merge request' do
      expect(contents.dig('merge_request', 'url')).to eq(Gitlab::UrlBuilder.build(merge_request))
    end
  end

  context 'when the caller passes no merge request, for one it may not name' do
    subject(:envelopes) { described_class.build(pipeline, merge_request: nil) }

    let(:pipeline) { create(:ci_pipeline, :detached_merge_request_pipeline, merge_request: merge_request) }

    it 'sends an empty merge request URL even though the pipeline has one' do
      expect(contents['merge_request']).to eq('url' => '')
    end
  end

  context 'when the pipeline has no open merge request' do
    let(:pipeline) { create(:ci_pipeline, project: project, ref: 'no-merge-request') }

    it 'sends an empty merge request URL, so the flow opens a new merge request' do
      expect(contents).to eq(
        'merge_request' => { 'url' => '' },
        'pipeline' => { 'source_branch' => 'no-merge-request', 'source' => pipeline.source }
      )
    end
  end
end
