# frozen_string_literal: true

module QA
  RSpec.describe 'Security Risk Management', :external_api_calls, feature_category: :vulnerability_management do
    describe 'Dependency list' do
      let(:expected_dependency_count) { 9 }

      let!(:cyclonedx_json) { File.join(EE::Runtime::Path.fixture('secure_premade_reports'), 'gl-sbom.json') }

      let!(:dependency_scan_yaml) do
        <<~YAML
          dependency_scanning:
            tags: [secure_report]
            script:
              - echo "Skipped"
            artifacts:
              reports:
                cyclonedx: gl-sbom.json
        YAML
      end

      let!(:project) do
        create(:project, name: 'project-with-dependencies', description: 'Project for dependency list tests')
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

      it 'shows the empty state when no dependencies have been detected' do
        Page::Project::Menu.perform(&:go_to_dependency_list)

        EE::Page::Project::Secure::DependencyList.perform do |dependency_list|
          expect(dependency_list).to have_empty_state_description(
            'The dependency list details information about the components used within your project.'
          )
          expect(dependency_list).to have_link(
            'More Information',
            href: %r{/help/user/application_security/dependency_list/_index}
          )
        end
      end

      it 'lists the dependencies from the uploaded CycloneDX report' do
        commit_scan_files(fixture_json: cyclonedx_json, ci_yaml_content: dependency_scan_yaml)
        project.visit!
        wait_for_pipeline_success
        Page::Project::Menu.perform(&:go_to_dependency_list)

        EE::Page::Project::Secure::DependencyList.perform do |dependency_list|
          expect(dependency_list).to have_dependency_count_of expected_dependency_count
        end
      end

      def commit_scan_files(fixture_json:, ci_yaml_content:)
        create(:commit, project: project, commit_message: 'Commit dependency scanning files', actions: [
          { action: 'create', file_path: File.basename(fixture_json), content: File.read(fixture_json) },
          { action: 'create', file_path: '.gitlab-ci.yml', content: ci_yaml_content }
        ])
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
    end
  end
end
