# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::Catalog::FoundationalFlow::BlSecurity::RunEligibility, :clean_gitlab_redis_shared_state,
  feature_category: :duo_agent_platform do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, :repository, group: group) }
  let_it_be(:merge_request) { create(:merge_request, source_project: project) }
  let_it_be(:mr_pipeline) do
    create(:ci_pipeline, :success, :detached_merge_request_pipeline, merge_request: merge_request)
  end

  let(:resource) { mr_pipeline }

  subject(:eligible) { described_class.call(project: project, resource: resource) }

  before do
    stub_licensed_features(security_scan_profiles: true)
    allow(mr_pipeline.merge_request).to receive(:diff_head_pipeline?).with(mr_pipeline).and_return(true)
    allow(::Gitlab::AppJsonLogger).to receive(:info)
  end

  def attach_profile(trigger_type, scan_type: :business_logic)
    profile = create(:security_scan_profile, namespace: group, scan_type: scan_type, projects: [project])
    create(:security_scan_profile_trigger, scan_profile: profile, trigger_type: trigger_type)
  end

  shared_examples 'a skipped run' do |reason|
    it 'returns false and logs why', :aggregate_failures do
      expect(eligible).to be(false)
      expect(::Gitlab::AppJsonLogger).to have_received(:info).with(hash_including(
        message: "Skipping BL security flow: #{reason}", project_id: project.id, pipeline_id: resource&.id
      ))
    end
  end

  context 'with a merge request pipeline' do
    it_behaves_like 'a skipped run', 'no Business Logic scan profile attached for merge requests'

    context 'when only another scan type has a merge request trigger' do
      before do
        attach_profile(:merge_request_pipeline, scan_type: :sast)
      end

      it_behaves_like 'a skipped run', 'no Business Logic scan profile attached for merge requests'
    end

    context 'when the Business Logic profile triggers on merge request pipelines' do
      before do
        attach_profile(:merge_request_pipeline)
      end

      it { is_expected.to be(true) }

      context 'when the pipeline already started a run' do
        before do
          described_class.call(project: project, resource: resource)
        end

        it_behaves_like 'a skipped run', 'pipeline already scanned'
      end

      context 'when the project is not licensed for scan profiles' do
        before do
          stub_licensed_features(security_scan_profiles: false)
        end

        it_behaves_like 'a skipped run', 'no Business Logic scan profile attached for merge requests'
      end

      context 'when a newer commit made the pipeline stale' do
        before do
          allow(mr_pipeline.merge_request).to receive(:diff_head_pipeline?).with(mr_pipeline).and_return(false)
        end

        it_behaves_like 'a skipped run', 'merge request pipeline is stale'
      end

      context 'with a merge train pipeline' do
        before do
          allow(mr_pipeline).to receive(:merge_train_pipeline?).and_return(true)
        end

        it_behaves_like 'a skipped run', 'merge train pipeline'
      end
    end
  end

  # The flow's goal validator refuses a branch pipeline that is not an open merge request's
  # head pipeline, so the one that reaches this check is.
  context 'with a branch pipeline of an open merge request' do
    let(:resource) do
      create(:ci_pipeline, :success, project: project, ref: merge_request.source_branch, source: :push)
    end

    before do
      attach_profile(:merge_request_pipeline)
    end

    it { is_expected.to be(true) }
  end

  context 'when the pipeline is gone' do
    let(:resource) { nil }

    before do
      attach_profile(:merge_request_pipeline)
    end

    it_behaves_like 'a skipped run', 'pipeline not found'
  end
end
