# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Pipeline', :js, feature_category: :continuous_integration do
  include ProjectForksHelper

  let_it_be(:project, freeze: false) { create(:project) }

  let(:user) { create(:user) }
  let(:role) { :developer }

  before do
    sign_in(user)
    project.add_role(user, role)
  end

  shared_context 'pipeline builds' do
    let!(:external_stage) { create(:ci_stage, name: 'external', pipeline: pipeline) }

    let!(:build_passed) do
      create(:ci_build, :success, pipeline: pipeline, stage: 'build', stage_idx: 0, name: 'build-job')
    end

    let!(:build_failed) do
      create(:ci_build, :failed, pipeline: pipeline, stage_idx: 1, name: 'test-job')
    end

    let!(:build_preparing) do
      create(:ci_build, :preparing, pipeline: pipeline, stage: 'deploy', stage_idx: 2, name: 'prepare-job')
    end

    let!(:build_running) do
      create(:ci_build, :running, pipeline: pipeline, stage: 'deploy', stage_idx: 3, name: 'deploy-job')
    end

    let!(:build_manual) do
      create(:ci_build, :manual, pipeline: pipeline, stage: 'deploy', stage_idx: 3, name: 'manual-job')
    end

    let!(:build_scheduled) do
      create(:ci_build, :scheduled, pipeline: pipeline, stage: 'deploy', stage_idx: 3, name: 'delayed-job')
    end

    let!(:build_external) do
      create(
        :generic_commit_status,
        status: 'success',
        pipeline: pipeline,
        name: 'jenkins-job',
        ci_stage: external_stage,
        ref: 'master',
        target_url: 'http://gitlab.com/status'
      )
    end
  end

  describe 'GET /:project/-/pipelines/:id' do
    include_context 'pipeline builds'

    let_it_be(:group) { create(:group) }
    let_it_be_with_reload(:project) { create(:project, :repository, group: group) }

    let(:pipeline) do
      create(:ci_pipeline, name: 'Build pipeline', project: project, ref: 'master', sha: project.commit.id, user: user)
    end

    subject(:visit_pipeline) { visit project_pipeline_path(project, pipeline) }

    context 'page tabs' do
      before do
        visit_pipeline
      end

      context 'without permission to access builds' do
        let_it_be(:project) { create(:project, :public, :repository, public_builds: false) }
        let(:role) { :guest }

        it 'does not show the pipeline details page' do
          expect(page).to have_content('Page not found')
        end
      end
    end

    describe 'test tabs' do
      before do
        visit_pipeline
      end

      context 'without test reports' do
        let(:pipeline) { create(:ci_pipeline, project: project) }

        it 'shows zero' do
          expect(page).to have_testid('tests-counter', text: '0', exact_text: true, visible: :all)
        end
      end
    end

    context 'when deleting' do
      before do
        # Deleting cancels the running jobs, and the resulting status push can race the
        # poll that sees the deleted pipeline, logging Apollo "Missing field" console errors.
        allow(GraphqlTriggers).to receive(:ci_pipeline_status_updated)

        group.add_owner(user)

        visit_pipeline

        click_button 'Delete'
        click_button 'Delete pipeline'
      end

      it 'redirects to pipeline overview page', :sidekiq_inline do
        expect(page).to have_content('The pipeline has been deleted')
        expect(page).to have_current_path(project_pipelines_path(project), ignore_query: true)
      end
    end

    context 'when pipeline is detached merge request pipeline' do
      let(:source_project) { project }
      let(:target_project) { project }

      let(:merge_request) do
        create(
          :merge_request,
          :with_detached_merge_request_pipeline,
          source_project: source_project,
          target_project: target_project
        )
      end

      let(:pipeline) do
        merge_request.all_pipelines.last
      end

      context 'when source project is a forked project' do
        let(:source_project) { fork_project(project, user, repository: true) }

        before do
          visit project_pipeline_path(source_project, pipeline)
        end

        it 'shows the pipeline information', :sidekiq_might_not_need_inline do
          within_testid 'pipeline-header' do
            expect(page).to have_content("#{pipeline.statuses.count} jobs")
            expect(page).to have_content("Related merge request !#{merge_request.iid} " \
                                         "to merge #{merge_request.source_branch}")
            expect(page).to have_link("!#{merge_request.iid}",
              href: project_merge_request_path(project, merge_request))
            expect(page).to have_link(merge_request.source_branch,
              href: project_commits_path(merge_request.source_project, merge_request.source_branch))
          end
        end
      end
    end

    context 'when pipeline is merge request pipeline' do
      let(:project) { create(:project, :repository, group: group) }
      let(:source_project) { project }
      let(:target_project) { project }

      let(:merge_request) do
        create(:merge_request,
          :with_merge_request_pipeline,
          source_project: source_project,
          target_project: target_project,
          merge_sha: project.commit.id)
      end

      let(:pipeline) do
        merge_request.all_pipelines.last
      end

      before do
        pipeline.update!(user: user)
      end

      context 'when source project is a forked project' do
        let(:source_project) { fork_project(project, user, repository: true) }

        before do
          visit project_pipeline_path(source_project, pipeline)
        end

        it 'shows the pipeline information', :sidekiq_might_not_need_inline do
          within_testid 'pipeline-header' do
            expect(page).to have_content("#{pipeline.statuses.count} jobs")
            expect(page).to have_content("Related merge request !#{merge_request.iid} " \
                                       "to merge #{merge_request.source_branch} " \
                                       "into #{merge_request.target_branch}")
            expect(page).to have_link("!#{merge_request.iid}",
              href: project_merge_request_path(project, merge_request))
            expect(page).to have_link(merge_request.source_branch,
              href: project_commits_path(merge_request.source_project, merge_request.source_branch))
            expect(page).to have_link(merge_request.target_branch,
              href: project_commits_path(merge_request.target_project, merge_request.target_branch))
          end
        end
      end
    end
  end

  context 'when user does not have access to read jobs' do
    before do
      project.update!(public_builds: false)
    end

    describe 'GET /:project/-/pipelines/:id' do
      include_context 'pipeline builds'

      let_it_be(:project, freeze: false) { create(:project, :repository) }

      let(:pipeline) { create(:ci_pipeline, project: project, ref: 'master', sha: project.commit.id, user: user) }

      before do
        visit project_pipeline_path(project, pipeline)
      end

      it 'shows the pipeline graph and links to jobs', :aggregate_failures do
        expect(page).to have_selector('.js-pipeline-graph')
        expect(page).to have_content('build')
        expect(page).to have_content('test')
        expect(page).to have_content('deploy')
        expect(page).to have_content('Retry')
        expect(page).to have_button('Cancel the running pipeline')
        expect(page).to have_selector('[data-testid="ci-job-item"]')
      end
    end
  end

  context 'when a bridge job exists' do
    include_context 'pipeline builds'

    let_it_be(:project) { create(:project, :repository) }
    let_it_be(:downstream) { create(:project, :repository) }

    let(:pipeline) do
      create(
        :ci_pipeline,
        project: project,
        ref: 'master',
        sha: project.commit.id,
        user: user
      )
    end

    let!(:bridge) do
      create(
        :ci_bridge,
        pipeline: pipeline,
        name: 'cross-build',
        user: user,
        downstream: downstream
      )
    end

    describe 'GET /:project/-/pipelines/:id' do
      context 'when a scheduled pipeline is created by a blocked user', :sidekiq_inline do
        let(:project)  { create(:project, :repository) }

        let(:schedule) do
          create(:ci_pipeline_schedule,
            project: project,
            owner: project.first_owner,
            description: 'blocked user schedule'
          ).tap do |schedule|
            schedule.update_column(:next_run_at, 1.minute.ago)
          end
        end

        before do
          schedule.owner.block!
          PipelineScheduleWorker.new.perform
        end

        it 'displays the PipelineSchedule in an inactive state' do
          visit project_pipeline_schedules_path(project)
          click_link('Inactive')

          expect(page).to have_selector('[data-testid="pipeline-schedule-description"]', text: 'blocked user schedule')
        end

        it 'does not create a new Pipeline',
          quarantine: 'https://gitlab.com/gitlab-org/quality/test-failure-issues/-/issues/24866' do
          visit project_pipelines_path(project)

          expect(page).not_to have_selector('.ci-table')
          expect(schedule.last_pipeline).to be_nil
        end
      end
    end

    describe 'GET /:project/-/pipelines/:id/builds' do
      before do
        visit builds_project_pipeline_path(project, pipeline)
      end

      it 'shows a bridge job on a list' do
        expect(page).to have_content('cross-build')
        expect(page).to have_content(bridge.id)
      end
    end
  end

  context 'when build requires resource', :sidekiq_inline do
    let_it_be(:project, freeze: false) { create(:project, :repository) }

    let(:pipeline) { create(:ci_pipeline, project: project) }
    let(:resource_group) { create(:ci_resource_group, project: project) }

    let!(:test_job) do
      create(:ci_build, :pending, name: 'test', stage_idx: 1, pipeline: pipeline, project: project)
    end

    let!(:deploy_job) do
      create(
        :ci_build,
        :created,
        stage: 'deploy',
        name: 'deploy',
        stage_idx: 2,
        pipeline: pipeline,
        project: project,
        resource_group: resource_group
      )
    end

    describe 'GET /:project/-/pipelines/:id' do
      subject { visit project_pipeline_path(project, pipeline) }

      it 'shows deploy job as created' do
        subject

        within_testid('pipeline-header') do
          expect(page).to have_selector('[data-testid="ci-icon"]', text: 'Pending')
        end

        within('.js-pipeline-graph') do
          within(all('[data-testid="stage-column"]')[0]) do
            expect(page).to have_content('test')
            expect(page).to have_css('[data-testid="status_pending_borderless-icon"]')
          end

          within(all('[data-testid="stage-column"]')[1]) do
            expect(page).to have_content('deploy')
            expect(page).to have_css('[data-testid="status_created_borderless-icon"]')
          end
        end
      end

      context 'when test job succeeded' do
        before do
          test_job.success!
        end

        it 'shows deploy job as pending' do
          subject

          within_testid('pipeline-header') do
            expect(page).to have_selector('[data-testid="ci-icon"]', text: 'Running')
          end

          within('.js-pipeline-graph') do
            within(all('[data-testid="stage-column"]')[0]) do
              expect(page).to have_content('test')
              expect(page).to have_css('[data-testid="status_success_borderless-icon"]')
            end

            within(all('[data-testid="stage-column"]')[1]) do
              expect(page).to have_content('deploy')
              expect(page).to have_css('[data-testid="status_pending_borderless-icon"]')
            end
          end
        end
      end

      context 'when test job succeeded but there are no available resources' do
        let(:another_job) { create(:ci_build, :running, project: project, resource_group: resource_group) }

        before do
          resource_group.assign_resource_to(another_job)
          test_job.success!
        end

        it 'shows deploy job as waiting for resource' do
          subject

          within_testid('pipeline-header') do
            expect(page).to have_selector('[data-testid="ci-icon"]', text: 'Waiting')
          end

          within('.js-pipeline-graph') do
            within(all('[data-testid="stage-column"]')[1]) do
              expect(page).to have_content('deploy')
              expect(page).to have_css('[data-testid="status_pending_borderless-icon"]')
            end
          end
        end

        context 'when resource is released from another job' do
          before do
            another_job.success!
          end

          it 'shows deploy job as pending' do
            subject

            within_testid('pipeline-header') do
              expect(page).to have_selector('[data-testid="ci-icon"]', text: 'Running')
            end

            within('.js-pipeline-graph') do
              within(all('[data-testid="stage-column"]')[1]) do
                expect(page).to have_content('deploy')
                expect(page).to have_css('[data-testid="status_pending_borderless-icon"]')
              end
            end
          end
        end

        context 'when deploy job is a bridge to trigger a downstream pipeline' do
          let!(:deploy_job) do
            create(:ci_bridge, :created,
              stage: 'deploy',
              name: 'deploy',
              stage_idx: 2,
              pipeline: pipeline,
              project: project,
              resource_group: resource_group
            )
          end

          it 'shows deploy job as waiting for resource' do
            subject

            within_testid('pipeline-header') do
              expect(page).to have_selector('[data-testid="ci-icon"]', text: 'Waiting')
            end

            within('.js-pipeline-graph') do
              within(all('[data-testid="stage-column"]')[1]) do
                expect(page).to have_content('deploy')
                expect(page).to have_css('[data-testid="status_pending_borderless-icon"]')
              end
            end
          end
        end
      end
    end
  end

  describe 'GET /:project/-/pipelines/:id/builds' do
    include_context 'pipeline builds'

    let_it_be(:project, freeze: false) { create(:project, :repository) }

    let(:pipeline) { create(:ci_pipeline, project: project, ref: 'master', sha: project.commit.id) }

    before do
      visit builds_project_pipeline_path(project, pipeline)
    end

    context 'playing manual job' do
      before do
        within_testid 'jobs-tab-table' do
          click_button('Run')
        end
      end

      it 'marks the build as pending', :aggregate_failures do
        expect(page).to have_current_path(project_job_path(project, build_manual))

        expect(build_manual.reload).to be_pending
      end
    end
  end

  describe 'GET /:project/-/pipelines/:id/failures' do
    let(:pipeline) { create(:ci_pipeline, project: project, ref: 'master', sha: '1234') }
    let(:pipeline_failures_page) { failures_project_pipeline_path(project, pipeline) }
    let!(:failed_build) { create(:ci_build, :failed, pipeline: pipeline) }

    subject { visit pipeline_failures_page }

    context 'with failed build' do
      before do
        failed_build.trace.set('4 examples, 1 failure')
      end

      context 'when user does have permission to retry build' do
        before do
          create(:protected_branch, :developers_can_merge, name: pipeline.ref, project: project)
        end

        it 'shows retry button for failed build' do
          subject

          within_testid('tab-failures', match: :first) do
            expect(page).to have_button('Retry')
          end
        end
      end
    end

    context 'without permission to access builds' do
      let(:role) { :guest }

      before do
        project.update!(public_builds: false)
      end

      context 'when accessing failed jobs page' do
        it 'renders a 404 page' do
          requests = inspect_requests { subject }

          expect(page).to have_title('Not Found')
          expect(requests.first.status_code).to eq(404)
        end
      end
    end

    context 'without failures' do
      before do
        failed_build.update!(status: :success)
      end

      it 'does not show the failure tab and displays the pipeline graph', :aggregate_failures do
        subject

        expect(page).not_to have_content('Failed Jobs')
        expect(page).to have_current_path(pipeline_path(pipeline))
        expect(page).to have_selector('.js-pipeline-graph')
      end
    end
  end

  describe 'GET /:project/-/pipelines/latest' do
    let_it_be(:project, freeze: false) { create(:project, :repository) }

    let!(:pipeline) { create(:ci_pipeline, project: project, ref: 'master', sha: project.commit.id) }

    before do
      visit latest_project_pipelines_path(project)
    end

    it 'displays the pipeline graph with correct URL' do
      expect(page).to have_current_path("#{pipeline_path(pipeline)}/")
      expect(page).to have_selector('.js-pipeline-graph')
    end
  end
end
