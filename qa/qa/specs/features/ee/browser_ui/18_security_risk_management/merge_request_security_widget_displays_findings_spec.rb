# frozen_string_literal: true

module QA
  RSpec.describe 'Security Risk Management', feature_category: :vulnerability_management do
    describe 'Merge request security widget' do
      let(:project) do
        create(:project,
          :with_readme,
          add_name_uuid: false,
          name: "project-create-mr-secure-#{SecureRandom.hex(6)}",
          description: 'Project for merge request security widget tests')
      end

      let(:source_branch) { "secure-mr-#{SecureRandom.hex(6)}" }

      let!(:runner) do
        create(:project_runner, project: project, name: "qa-runner-#{SecureRandom.hex(6)}",
          tags: %w[secure_report])
      end

      after do
        runner.remove_via_api! if runner
      end

      before do
        Flow::Login.sign_in

        # Push fixture to generate security reports
        source = Resource::Repository::ProjectPush.fabricate! do |push|
          push.project = project
          push.directory = Pathname.new(EE::Runtime::Path.fixture('secure_premade_reports'))
          push.commit_message = 'Add premade security reports'
          push.branch_name = source_branch
        end

        merge_request = create(:merge_request,
          project: project,
          source_branch: source_branch,
          target_branch: project.default_branch,
          source: source,
          target: project.default_branch,
          target_new_branch: false)

        Flow::Pipeline.wait_for_pipeline_to_have_status_by_source_branch(
          project: project, source_branch: source_branch, status: 'success')

        merge_request.visit!
      end

      it 'displays the vulnerability report and the finding count' do
        Page::MergeRequest::Show.perform do |merge_request|
          expect(merge_request).to have_vulnerability_report(timeout: 120)
          expect(merge_request).to have_vulnerability_count(24)
        end
      end
    end
  end
end
