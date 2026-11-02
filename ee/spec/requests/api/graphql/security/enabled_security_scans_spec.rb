# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Querying enabled scans for a pipeline', feature_category: :vulnerability_management do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:project) { create(:project) }
  let_it_be(:pipeline) { create(:ci_pipeline, :running, project: project) }

  let(:variables) { { fullPath: project.full_path, pipelineIid: pipeline.iid } }
  let(:enabled_scans) { graphql_data.dig('project', 'pipeline', 'enabledSecurityScans') }
  let(:enabled_partial_scans) { graphql_data.dig('project', 'pipeline', 'enabledPartialSecurityScans') }

  let(:query) do
    <<~QUERY
    query enabledScans($fullPath: ID!, $pipelineIid: ID!) {
      project(fullPath: $fullPath) {
        pipeline(iid: $pipelineIid) {
          enabledSecurityScans {
            ready
            apiFuzzing
            clusterImageScanning
            containerScanning
            coverageFuzzing
            dast
            dependencyScanning
            sast
            secretDetection
          }
          enabledPartialSecurityScans {
            ready
            apiFuzzing
            clusterImageScanning
            containerScanning
            coverageFuzzing
            dast
            dependencyScanning
            sast
            secretDetection
          }
        }
      }
    }
    QUERY
  end

  def send_request
    post_graphql(query, variables: variables, current_user: user)
  end

  context 'when user does not have permission to read pipeline' do
    it 'does not return pipeline data' do
      send_request

      expect(graphql_data.dig('project', 'pipeline')).to be_nil
    end
  end

  context 'when user has permission to read pipeline' do
    before_all do
      project.add_developer(user)
    end

    context 'when there are no scans' do
      it 'returns false for all scanners' do
        send_request

        expect(enabled_scans).to include(
          'apiFuzzing' => false,
          'clusterImageScanning' => false,
          'containerScanning' => false,
          'coverageFuzzing' => false,
          'dast' => false,
          'dependencyScanning' => false,
          'sast' => false,
          'secretDetection' => false
        )
        expect(enabled_partial_scans).to include(
          'apiFuzzing' => false,
          'clusterImageScanning' => false,
          'containerScanning' => false,
          'coverageFuzzing' => false,
          'dast' => false,
          'dependencyScanning' => false,
          'sast' => false,
          'secretDetection' => false
        )
      end

      it 'indicates results are ready' do
        send_request

        expect(enabled_scans).to include('ready' => true)
        expect(enabled_partial_scans).to include('ready' => true)
      end
    end

    context 'when there are scans in the pipeline' do
      let_it_be(:sast_build) { create(:ee_ci_build, :sast, :success, pipeline: pipeline, project: project) }
      let_it_be(:sast_scan) { sast_build.security_scans.first.tap { |scan| scan.update!(status: :succeeded) } }
      let_it_be(:dast_scan) { create(:security_scan, status: :succeeded, pipeline: pipeline, scan_type: :dast) }
      let_it_be(:sast_partial_scan) do
        create(:vulnerabilities_partial_scan, scan: sast_scan, pipeline: pipeline, scan_type: :sast)
      end

      before do
        # Should be ready if a non-security job is still running
        create(:ee_ci_build, :running, pipeline: pipeline, project: project)
      end

      it 'returns true for report types which have scans' do
        send_request

        expect(enabled_scans).to eq({
          'ready' => true,
          'apiFuzzing' => false,
          'clusterImageScanning' => false,
          'containerScanning' => false,
          'coverageFuzzing' => false,
          'dast' => true,
          'dependencyScanning' => false,
          'sast' => true,
          'secretDetection' => false
        })
        expect(enabled_partial_scans).to eq({
          'ready' => true,
          'apiFuzzing' => false,
          'clusterImageScanning' => false,
          'containerScanning' => false,
          'coverageFuzzing' => false,
          'dast' => false,
          'dependencyScanning' => false,
          'sast' => true,
          'secretDetection' => false
        })
      end

      context 'when the pipeline has running security jobs' do
        let_it_be(:sast_build) { create(:ee_ci_build, :sast, :running, pipeline: pipeline, project: project) }

        it 'indicates results are not ready' do
          send_request

          expect(enabled_scans).to include('ready' => false)
          expect(enabled_partial_scans).to include('ready' => false)
        end
      end

      context 'when scan processing is not done yet' do
        let!(:sast_scan) { create(:security_scan, status: status, pipeline: pipeline, scan_type: :sast) }

        where(:status) { %i[created preparing] }

        with_them do
          it 'indicates results are not ready' do
            send_request

            expect(enabled_scans).to include('ready' => false)
            expect(enabled_partial_scans).to include('ready' => false)
          end
        end
      end
    end

    context 'when the scans are in a related pipeline with the same sha' do
      let_it_be(:related_pipeline) do
        create(:ci_pipeline, :success, project: project, sha: pipeline.sha, source: :web)
      end

      let_it_be(:secret_detection_scan) do
        create(:security_scan, status: :succeeded, pipeline: related_pipeline, scan_type: :secret_detection)
      end

      it 'returns true for report types with scans in related pipelines' do
        send_request

        expect(enabled_scans).to include('secretDetection' => true)
      end
    end

    context 'when a business logic security scan ran on a duo_workflow workload pipeline at the same sha' do
      let_it_be(:workload_pipeline) do
        create(:ci_pipeline, :success, project: project, sha: pipeline.sha, source: :duo_workflow)
      end

      let_it_be(:workload_build) { create(:ci_build, :success, pipeline: workload_pipeline, project: project) }
      let_it_be(:workload_scan) do
        create(:security_scan, status: :succeeded, build: workload_build, scan_type: :sast)
      end

      let_it_be(:workload_partial_scan) do
        create(:vulnerabilities_partial_scan, scan: workload_scan, scan_type: :sast)
      end

      it 'reports the workload scan so the MR widget picks the right scan mode' do
        send_request

        expect(enabled_scans).to include('sast' => true)
        expect(enabled_partial_scans).to include('sast' => true)
      end

      context 'when the agentic_analyzer_security_ingestion feature flag is disabled' do
        before do
          stub_feature_flags(agentic_analyzer_security_ingestion: false)
        end

        it 'does not consider the workload scan' do
          send_request

          expect(enabled_scans).to include('sast' => false)
          expect(enabled_partial_scans).to include('sast' => false)
        end
      end
    end

    context 'when a business logic security scan ran on the source commit of a merged-results pipeline' do
      let_it_be(:merge_request) { create(:merge_request, source_project: project) }
      let_it_be(:merged_result_pipeline) do
        create(:ci_pipeline, :merged_result_pipeline, merge_request: merge_request,
          sha: 'b' * 40, source_sha: 'a' * 40, target_sha: 'c' * 40)
      end

      let_it_be(:workload_pipeline) do
        create(:ci_pipeline, :success, project: project, sha: 'a' * 40, source: :duo_workflow)
      end

      let_it_be(:workload_build) { create(:ci_build, :success, pipeline: workload_pipeline, project: project) }
      let_it_be(:workload_scan) do
        create(:security_scan, status: :succeeded, build: workload_build, scan_type: :sast)
      end

      let(:variables) { { fullPath: project.full_path, pipelineIid: merged_result_pipeline.iid } }

      it 'reports the workload scan' do
        send_request

        expect(enabled_scans).to include('sast' => true)
      end
    end

    context 'when the scans are in a child pipeline' do
      let_it_be(:child_pipeline) { create(:ci_pipeline, child_of: pipeline) }
      let_it_be(:sast_scan) { create(:security_scan, status: :succeeded, pipeline: child_pipeline, scan_type: :sast) }
      let_it_be(:dast_scan) { create(:security_scan, status: :succeeded, pipeline: child_pipeline, scan_type: :dast) }
      let_it_be(:sast_partial_scan) do
        create(:vulnerabilities_partial_scan, scan: sast_scan, pipeline: child_pipeline, scan_type: :sast)
      end

      it 'returns true for report types which have scans' do
        send_request

        expect(enabled_scans).to eq({
          'ready' => true,
          'apiFuzzing' => false,
          'clusterImageScanning' => false,
          'containerScanning' => false,
          'coverageFuzzing' => false,
          'dast' => true,
          'dependencyScanning' => false,
          'sast' => true,
          'secretDetection' => false
        })
        expect(enabled_partial_scans).to eq({
          'ready' => true,
          'apiFuzzing' => false,
          'clusterImageScanning' => false,
          'containerScanning' => false,
          'coverageFuzzing' => false,
          'dast' => false,
          'dependencyScanning' => false,
          'sast' => true,
          'secretDetection' => false
        })
      end

      context 'when scan processing is not done yet' do
        let!(:sast_scan) { create(:security_scan, status: status, pipeline: child_pipeline, scan_type: :sast) }

        where(:status) { %i[created preparing] }

        with_them do
          it 'indicates results are not ready' do
            send_request

            expect(enabled_scans).to include('ready' => false)
            expect(enabled_partial_scans).to include('ready' => false)
          end
        end
      end
    end
  end
end
