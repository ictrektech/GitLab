# frozen_string_literal: true

module QA
  RSpec.describe 'Security Risk Management', :external_api_calls, feature_category: :vulnerability_management do
    let(:dependency_scan_example_vuln) { 'Prototype pollution attack in mixin-deep' }
    let(:container_scan_example_vuln) { 'CVE-2017-18269 in glibc' }
    let(:sast_scan_example_vuln) { 'Cipher with no integrity' }
    let(:dast_scan_example_vuln) { 'Flask debug mode identified on target:7777' }
    let(:sast_scan_fp_example_vuln) { "Possible unprotected redirect" }
    let(:secret_detection_vuln) { "Typeform API token" }

    let!(:gitlab_ci_yaml_path) { File.join(EE::Runtime::Path.fixture('secure_premade_reports'), '.gitlab-ci.yml') }

    let!(:ci_yaml_content) do
      original_yaml = File.read(gitlab_ci_yaml_path)
      original_yaml << "\n"
      original_yaml << <<~YAML
        secret_detection:
          tags: [secure_report]
          script:
            - echo "Skipped"
          artifacts:
            reports:
              secret_detection: gl-secret-detection-report.json
      YAML
    end

    let(:group) { create(:group, path: "govern-security-reports-#{Faker::Alphanumeric.alphanumeric(number: 6)}") }

    let!(:project) do
      create(:project, name: 'project-with-secure', description: 'Project for security report tests', group: group)
    end

    let!(:runner) do
      create(:project_runner, project: project, name: "runner-for-#{project.name}", tags: ['secure_report'])
    end

    before do
      Flow::Login.sign_in_unless_signed_in
      project.visit!
    end

    after do
      runner&.remove_via_api! if runner
    end

    describe 'Pipeline security tab' do
      it 'lists a finding from every report type' do
        push_security_reports
        project.visit!
        wait_for_pipeline_success
        Flow::Pipeline.visit_latest_pipeline
        Page::Project::Pipeline::Show.perform do |pipeline|
          pipeline.click_on_security

          pipeline.filter_by(token_name: "Report type", token_value: "Dependency Scanning")
          expect(pipeline).to have_vulnerability dependency_scan_example_vuln

          pipeline.filter_by(token_name: "Report type", token_value: "Container Scanning")
          expect(pipeline).to have_vulnerability container_scan_example_vuln

          pipeline.filter_by(token_name: "Report type", token_value: "SAST")
          expect(pipeline).to have_vulnerability sast_scan_example_vuln
          expect(pipeline).to have_vulnerability sast_scan_fp_example_vuln

          pipeline.filter_by(token_name: "Report type", token_value: "DAST")
          expect(pipeline).to have_vulnerability dast_scan_example_vuln

          pipeline.filter_by(token_name: "Report type", token_value: "Secret Detection")
          expect(pipeline).to have_vulnerability secret_detection_vuln
        end
      end
    end

    describe 'Project vulnerability report' do
      it 'lists a vulnerability from every scanner' do
        push_security_reports
        project.visit!
        wait_for_pipeline_success
        Page::Project::Menu.perform(&:click_project)
        Page::Project::Menu.perform(&:go_to_vulnerability_report)

        EE::Page::Project::Secure::VulnerabilityReport.perform(&:wait_for_vuln_report_to_ingest)

        EE::Page::Project::Secure::Show.perform do |vulnerability_report|
          vulnerability_report.filter_by(token_name: "Scanner", token_value: "gemnasium")
          expect(vulnerability_report).to have_vulnerability dependency_scan_example_vuln

          vulnerability_report.filter_by(token_name: "Scanner", token_value: "Trivy")
          expect(vulnerability_report).to have_vulnerability container_scan_example_vuln

          vulnerability_report.filter_by(token_name: "Scanner", token_value: "Brakeman")
          expect(vulnerability_report).to have_vulnerability sast_scan_example_vuln
          expect(vulnerability_report).to have_vulnerability sast_scan_fp_example_vuln
          expect(vulnerability_report).to have_false_positive_vulnerability

          vulnerability_report.filter_by(token_name: "Scanner", token_value: "GitLab API Security")
          expect(vulnerability_report).to have_vulnerability dast_scan_example_vuln

          vulnerability_report.filter_by(token_name: "Scanner", token_value: "Gitleaks")
          expect(vulnerability_report).to have_vulnerability secret_detection_vuln
        end
      end
    end

    describe 'Group security dashboard' do
      it 'shows the project security status and lists the findings in the group vulnerability report' do
        push_security_reports
        project.visit!
        wait_for_pipeline_success

        project.group.visit!

        Page::Group::Menu.perform(&:go_to_security_dashboard)

        # Check if new dashboard is being used by looking for the test-id element
        is_new_dashboard = has_element?('data-testid': 'group-security-dashboard')

        if is_new_dashboard
          # Handle the new dashboard implementation
          EE::Page::Group::Secure::Show.perform do |_|
            Support::Retrier.retry_on_exception(
              max_attempts: 2,
              reload_page: page,
              message: "Retry project visibility in new security dashboard"
            ) do
              expect(page).to have_content('Security dashboard')
            end
          end
        else
          # Original implementation for when the feature flag is disabled
          EE::Page::Group::Secure::Show.perform do |dashboard|
            Support::Retrier.retry_on_exception(
              max_attempts: 2,
              reload_page: page,
              message: "Retry project security status in security dashboard"
            ) do
              expect(dashboard).to have_security_status_project_for_severity('F', project)
            end
          end
        end

        Page::Group::Menu.perform(&:go_to_vulnerability_report)

        EE::Page::Group::Secure::Show.perform do |vulnerability_report|
          vulnerability_report.filter_project(project_name: project.name)

          vulnerability_report.filter_by(token_name: 'Report type', token_value: "Dependency Scanning")
          expect(vulnerability_report).to have_vulnerability dependency_scan_example_vuln

          vulnerability_report.filter_by(token_name: 'Report type', token_value: "Container Scanning")
          expect(vulnerability_report).to have_vulnerability container_scan_example_vuln

          vulnerability_report.filter_by(token_name: 'Report type', token_value: "SAST")
          expect(vulnerability_report).to have_vulnerability sast_scan_example_vuln

          vulnerability_report.filter_by(token_name: 'Report type', token_value: "DAST")
          expect(vulnerability_report).to have_vulnerability dast_scan_example_vuln

          vulnerability_report.filter_by(token_name: 'Report type', token_value: "Secret Detection")
          expect(vulnerability_report).to have_vulnerability secret_detection_vuln
        end
      end
    end

    def push_security_reports
      build(:commit,
        project: project,
        commit_message: 'Create Secure compatible application to serve premade reports') do |commit|
        commit.add_directory(Pathname.new(EE::Runtime::Path.fixture('dismissed_security_findings_mr_widget')))
        commit.add_directory(Pathname.new(EE::Runtime::Path.fixture('secure_premade_reports')))
        commit.update_files([ci_file])
      end.fabricate_via_api!
    end

    def wait_for_pipeline_success
      Support::Waiter.wait_until(sleep_interval: 10, message: "Check for pipeline success", max_duration: 90) do
        latest_pipeline.status == 'success'
      end
    end

    def latest_pipeline
      Support::Waiter.wait_until(sleep_interval: 2, message: "Waiting for pipelines api endpoint to populate") do
        !project.pipelines.empty?
      end
      create(:pipeline, project: project, id: project.latest_pipeline[:id]) # Fetch existing pipeline object
    end

    def ci_file
      {
        file_path: '.gitlab-ci.yml',
        content: ci_yaml_content
      }
    end
  end
end
