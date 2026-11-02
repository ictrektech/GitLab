# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DependencyManagement::SecurityUpdate::CreateMergeRequestService,
  feature_category: :dependency_management do
  let_it_be(:organization) { create(:organization) }
  let_it_be(:group) { create(:group, organization: organization) }
  let_it_be(:project) { create(:project, :small_repo, group: group, organization: organization) }
  let_it_be(:vulnerability) { create(:vulnerability, :with_finding, project: project, severity: :high) }
  let_it_be(:maintainer) { create(:user, organization: organization) }

  # The commit is written on top of the workload pipeline's SHA, so it must exist in the repository.
  let(:pipeline) { create(:ci_pipeline, :success, project: project, sha: project.repository.commit.sha) }
  let(:build) { create(:ci_build, :success, pipeline: pipeline) }

  let(:source_branch_name) { 'dependency-management/rack-3.x' }

  let(:output_json) { load_output_fixture("output_valid") }

  def load_output_fixture(name)
    File.read(Rails.root.join("ee/spec/fixtures/dependency_management/#{name}.json"))
  end

  # An array stub cannot answer the finder's scope chain, so stub the finder too
  # or the service ends up in its rescue.
  def stub_no_remediated_occurrence
    allow_next_instance_of(DependencyManagement::SecurityUpdate::SbomOccurrenceFinder) do |finder|
      allow(finder).to receive(:execute).and_return(Sbom::Occurrence.none)
    end
  end

  subject(:execute) do
    described_class.new(
      project: project,
      pipeline: pipeline,
      vulnerability: vulnerability
    ).execute
  end

  before_all do
    project.add_maintainer(maintainer)
  end

  before do
    # The service warns on several degraded paths, so examples asserting one of
    # them need the others to pass through rather than fail the expectation.
    allow(Gitlab::AppLogger).to receive(:warn)

    stub_licensed_features(dependency_scanning: true)
    stub_ee_application_setting(
      allow_top_level_group_owners_to_create_service_accounts: true
    )
    allow_next_instance_of(Namespaces::ServiceAccounts::ProjectCreateService) do |svc|
      allow(svc).to receive(:can_create_service_account?).and_return(true)
    end

    allow(pipeline).to receive(:find_job_with_archive_artifacts)
      .with('workload')
      .and_return(build)

    allow(Gitlab::Ci::ArtifactFileReader).to receive(:new)
      .with(build, max_archive_size: 5.megabytes)
      .and_return(instance_double(Gitlab::Ci::ArtifactFileReader,
        read: output_json
      ))

    allow(build).to receive(:variables).and_return([
      instance_double(
        Gitlab::Ci::Variables::Collection::Item,
        key: 'DEPENDENCY_MANAGEMENT_SOURCE_REF',
        value: source_branch_name
      )

    ])
  end

  after do
    project.repository.delete_branch(source_branch_name) if project.repository.branch_exists?(source_branch_name)
  end

  describe 'recording the remediation' do
    let(:proposed_version) do
      Gitlab::Json::SafeParser.parse(output_json)['dependency_updates'].first['new_version']
    end

    let(:remediation) { DependencyManagement::Remediation.last }

    let_it_be(:component) { create(:sbom_component, :bundler, name: 'rack') }
    let_it_be_with_reload(:sbom_occurrence) do
      create(:sbom_occurrence,
        project: project,
        component: component,
        package_manager: 'bundler',
        input_file_path: 'Gemfile.lock')
    end

    before_all do
      create(:sbom_occurrences_vulnerability, occurrence: sbom_occurrence, vulnerability: vulnerability)
    end

    it 'records the remediated dependency, not every dependency the updater touched' do
      expect { execute }.to change { DependencyManagement::Remediation.count }.by(1)

      expect(remediation).to have_attributes(
        project_id: project.id,
        purl_type: 'gem',
        package_name: 'rack',
        input_file_path: 'Gemfile.lock',
        current_version: sbom_occurrence.version,
        target_version: proposed_version,
        state: 'open'
      )
    end

    it 'points the row at the merge request it created' do
      result = execute

      expect(remediation.merge_request_id).to eq(result.payload[:merge_request].id)
    end

    context 'with several dependencies in the output' do
      let(:output_json) { load_output_fixture('output_multiple_deps') }

      it 'still records only one row' do
        expect { execute }.to change { DependencyManagement::Remediation.count }.by(1)
      end
    end

    context 'when the updater names the component group:artifact' do
      let(:output_json) do
        output = Gitlab::Json::SafeParser.parse(load_output_fixture('output_valid'))
        output['dependency_updates'].first['name'] = 'org.rack:rack'
        output.to_json
      end

      before do
        sbom_occurrence.update!(component_name: 'org.rack/rack', package_manager: 'maven')
      end

      it 'matches it to the stored group/artifact name' do
        execute

        expect(remediation).to have_attributes(package_name: 'org.rack/rack', target_version: proposed_version)
      end
    end

    context 'when the remediated component is absent from the updater output' do
      before do
        sbom_occurrence.update!(component_name: 'nokogiri')
      end

      # Another package's version as the ceiling could put it out of reach for
      # good, and skipping the row entirely would leave the merge request
      # untracked, which is the bug this table exists for.
      it 'records the installed version and warns' do
        expect(Gitlab::AppLogger).to receive(:warn).with(
          hash_including(message: 'DependencyManagement: remediated component absent from updater output')
        )

        expect { execute }.to change { DependencyManagement::Remediation.count }.by(1)

        expect(remediation).to have_attributes(
          package_name: 'nokogiri',
          target_version: sbom_occurrence.version
        )
      end

      context 'with several dependencies in the output' do
        let(:output_json) { load_output_fixture('output_multiple_deps') }

        it 'still records the installed version' do
          execute

          expect(remediation).to have_attributes(
            package_name: 'nokogiri',
            target_version: sbom_occurrence.version
          )
        end
      end
    end

    context 'when the vulnerability spans several installed versions' do
      # Lowest id is not the one the branch was built from, so guessing records
      # the wrong bump.
      let_it_be(:other_occurrence) do
        create(:sbom_occurrence,
          project: project,
          component: component,
          package_manager: 'bundler',
          input_file_path: 'other/Gemfile.lock')
      end

      before_all do
        create(:sbom_occurrences_vulnerability, occurrence: other_occurrence, vulnerability: vulnerability)
      end

      before do
        allow(build).to receive(:variables).and_return([
          instance_double(
            Gitlab::Ci::Variables::Collection::Item,
            key: 'DEPENDENCY_MANAGEMENT_SOURCE_REF',
            value: source_branch_name
          ),
          instance_double(
            Gitlab::Ci::Variables::Collection::Item,
            key: 'DEPENDENCY_MANAGEMENT_SBOM_OCCURRENCE_ID',
            value: other_occurrence.id.to_s
          )
        ])
      end

      it 'records the occurrence the workload named' do
        execute

        expect(remediation).to have_attributes(
          input_file_path: 'other/Gemfile.lock',
          current_version: other_occurrence.version
        )
      end

      context 'with a dismissal recorded against the named occurrence' do
        before do
          create(:dependency_management_remediation,
            project: project,
            purl_type: :gem,
            package_name: 'rack',
            input_file_path: 'other/Gemfile.lock',
            current_version: other_occurrence.version,
            target_version: proposed_version,
            state: :dismissed)
        end

        it 'skips the remediation' do
          expect(execute.payload[:skipped]).to be(true)
        end
      end

      context 'when the named occurrence no longer exists' do
        before do
          create(:dependency_management_remediation,
            project: project,
            purl_type: :gem,
            package_name: 'rack',
            input_file_path: 'Gemfile.lock',
            current_version: sbom_occurrence.version,
            target_version: proposed_version,
            state: :dismissed)

          allow(build).to receive(:variables).and_return([
            instance_double(
              Gitlab::Ci::Variables::Collection::Item,
              key: 'DEPENDENCY_MANAGEMENT_SOURCE_REF',
              value: source_branch_name
            ),
            instance_double(
              Gitlab::Ci::Variables::Collection::Item,
              key: 'DEPENDENCY_MANAGEMENT_SBOM_OCCURRENCE_ID',
              value: non_existing_record_id.to_s
            )
          ])
        end

        it 'does not apply another manifest\'s dismissal' do
          result = execute

          expect(result).to be_success
          expect(result.payload[:merge_request]).to be_persisted
        end
      end

      context 'when the workload predates the variable' do
        before do
          allow(build).to receive(:variables).and_return([
            instance_double(
              Gitlab::Ci::Variables::Collection::Item,
              key: 'DEPENDENCY_MANAGEMENT_SOURCE_REF',
              value: source_branch_name
            )
          ])
        end

        it 'falls back to the first supported occurrence' do
          execute

          expect(remediation.input_file_path).to eq('Gemfile.lock')
        end
      end

      context 'when the pipeline has no workload job' do
        before do
          allow(pipeline).to receive(:find_job_with_archive_artifacts).with('workload').and_return(nil)
        end

        it 'records nothing and reports the missing artifact' do
          expect { execute }.not_to change { DependencyManagement::Remediation.count }
        end
      end

      context 'when the named occurrence belongs to another project' do
        let_it_be(:foreign_occurrence) { create(:sbom_occurrence) }

        before do
          allow(build).to receive(:variables).and_return([
            instance_double(
              Gitlab::Ci::Variables::Collection::Item,
              key: 'DEPENDENCY_MANAGEMENT_SOURCE_REF',
              value: source_branch_name
            ),
            instance_double(
              Gitlab::Ci::Variables::Collection::Item,
              key: 'DEPENDENCY_MANAGEMENT_SBOM_OCCURRENCE_ID',
              value: foreign_occurrence.id.to_s
            )
          ])
        end

        it 'records nothing rather than trusting the id' do
          result = nil

          expect { result = execute }.not_to change { DependencyManagement::Remediation.count }
          expect(result).to be_success
          expect(result.payload[:merge_request]).to be_persisted
        end
      end
    end

    context 'when the first run failed to record the row and an identical refresh follows' do
      it 'records it on the refresh' do
        allow(DependencyManagement::Remediation)
          .to receive(:record_proposal).and_raise(ActiveRecord::StatementInvalid, 'boom')
        execute
        allow(DependencyManagement::Remediation).to receive(:record_proposal).and_call_original

        expect do
          travel_to(1.minute.from_now) do
            described_class.new(project: project, pipeline: pipeline, vulnerability: vulnerability).execute
          end
        end.to change { DependencyManagement::Remediation.count }.by(1)
      end
    end

    context 'when recording the row fails' do
      before do
        allow(DependencyManagement::Remediation)
          .to receive(:record_proposal).and_raise(ActiveRecord::StatementInvalid, 'boom')
      end

      it 'still succeeds, so the merge request keeps its refresh cooldown' do
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(instance_of(ActiveRecord::StatementInvalid), hash_including(project_id: project.id))

        expect(execute).to be_success
      end
    end
  end

  describe '#execute' do
    context 'when everything succeeds' do
      it 'returns a success response with the merge request' do
        result = execute

        expect(result).to be_success
        expect(result.payload[:merge_request]).to be_a(MergeRequest)
        expect(result.payload[:merge_request]).to be_persisted
      end

      it 'creates a merge request with the correct attributes' do
        result = execute
        mr = result.payload[:merge_request]

        expect(mr.source_branch).to eq(source_branch_name)
        expect(mr.target_branch).to eq(project.default_branch_or_main)
        expect(mr.title).to include('rack')
        expect(mr.title).to include('2.0.9')
        expect(mr.title).to include('2.2.0')
      end

      it 'creates the target branch' do
        expect(project.repository.branch_exists?(source_branch_name)).to be(false)

        execute

        expect(project.repository.branch_exists?(source_branch_name)).to be(true)
      end

      it 'creates a commit on the target branch with the updated files' do
        execute

        commit = project.repository.commit(source_branch_name)
        expect(commit).to be_present
        expect(commit.message).to include('rack')
        expect(commit.message).to include('2.0.9')
        expect(commit.message).to include('2.2.0')
      end

      it 'renders the description using the md.erb template' do
        expect(ApplicationController).to receive(:render).with(
          template: 'dependency_management/security_update/merge_request_description',
          formats: :md,
          locals: hash_including(
            :dependencies, :updated_files, :vulnerability, :vulnerability_url
          )
        ).and_call_original

        result = execute
        mr = result.payload[:merge_request]

        expect(mr.description).to include('Security Dependency Update')
        expect(mr.description).to include('`rack`')
        expect(mr.description).to include('`2.0.9`')
        expect(mr.description).to include('`2.2.0`')
        expect(mr.description).to include('`Gemfile`')
        expect(mr.description).to include('`Gemfile.lock`')
        expect(mr.description).to include("vulnerability ##{vulnerability.id}")
      end

      it 'does not include vulnerability details in the description', :aggregate_failures do
        result = execute
        mr = result.payload[:merge_request]

        expect(mr.description).not_to include(vulnerability.title)
        expect(mr.description).not_to include(vulnerability.severity.to_s.capitalize)
        expect(mr.description).not_to include(vulnerability.finding.cve_value)
      end

      it 'links the vulnerability to the merge request' do
        result = execute
        mr = result.payload[:merge_request]

        expect(Vulnerabilities::MergeRequestLink.exists?(
          vulnerability: vulnerability,
          merge_request: mr
        )).to be(true)
      end

      it 'updates vulnerability_reads has_merge_request' do
        expect(Vulnerabilities::Reads::UpsertService).to receive(:new).with(
          vulnerability,
          { has_merge_request: true },
          projects: project,
          findings: Array(vulnerability.finding)
        ).and_call_original

        execute
      end

      context 'when the project still relies on the vulnerability_reads DB trigger' do
        before do
          stub_feature_flags(turn_off_vulnerability_read_create_db_trigger_function: false)
        end

        it 'updates has_merge_request and enqueues an Elasticsearch sync for the vulnerability', :aggregate_failures do
          vulnerability_read = Vulnerabilities::Read.find_by(vulnerability_id: vulnerability.id) ||
            create(:vulnerability_read, vulnerability: vulnerability, has_merge_request: false)

          expect(Vulnerabilities::BulkEsOperationService)
            .to receive(:new).once.and_wrap_original do |original, relation|
            expect(relation).to contain_exactly(vulnerability)
            original.call(relation)
          end

          execute

          expect(vulnerability_read.reload.has_merge_request).to be(true)
        end
      end

      it 'does not assign a reviewer' do
        result = execute
        mr = result.payload[:merge_request]

        expect(mr.reviewers).to be_empty
      end

      context 'when automatic reviewer assignment is enabled', :clean_gitlab_redis_shared_state do
        let_it_be(:code_owner) { create(:user, organization: organization) }

        before_all do
          project.add_developer(code_owner)
          project.repository.create_file(project.creator, 'CODEOWNERS', "* @#{code_owner.username}\n",
            message: 'Add CODEOWNERS', branch_name: project.default_branch_or_main)
          project.project_setting.update!(reviewer_assignment_strategy: 'code_owners')
        end

        after(:context) do
          project.repository.delete_file(project.creator, 'CODEOWNERS',
            message: 'Remove CODEOWNERS', branch_name: project.default_branch_or_main)
        end

        before do
          stub_licensed_features(dependency_scanning: true, merge_request_approvers: true,
            multiple_merge_request_reviewers: true, code_owners: true)
        end

        it 'lets the code owners be assigned as reviewers' do
          mr = execute.payload[:merge_request]

          expect(MergeRequests::ReviewerAssignment::PendingInitialAssignment.consume(mr)).to be(true)

          mr.ensure_merge_request_diff
          MergeRequests::SyncCodeOwnerApprovalRules.new(mr).execute
          MergeRequests::AutoAssignReviewersWorker.new.perform(mr.id)

          expect(mr.reset.reviewers).to contain_exactly(code_owner)
        end
      end

      it 'assigns the service account as assignee' do
        result = execute
        mr = result.payload[:merge_request]

        expect(mr.assignees).to contain_exactly(mr.author)
      end

      it 'tracks the create event with purl_type and merge_request_id' do
        sbom_occurrence = instance_double(Sbom::Occurrence, purl_type: 'gem')
        allow(vulnerability).to receive(:sbom_occurrences).and_return([sbom_occurrence])
        stub_no_remediated_occurrence

        expect { execute }
          .to trigger_internal_events('create_dependency_management_auto_remediation_mr')
          .with(
            project: project,
            additional_properties: {
              purl_type: 'gem',
              merge_request_id: kind_of(Integer)
            }
          )
      end
    end

    context 'when the repository uses Conventional Commits' do
      let(:title) { 'build(deps): [security] update rack from 2.0.9 to 2.2.0' }

      let(:style) { DependencyManagement::SecurityUpdate::CommitConvention::Style.new(type: 'build', capitalize: false) }

      before do
        allow(DependencyManagement::SecurityUpdate::CommitConvention).to receive(:detect)
          .with(project, exclude_email: kind_of(String))
          .and_return(style)
      end

      it 'uses the conventional title as both the MR title and the commit subject', :aggregate_failures do
        mr = execute.payload[:merge_request]

        expect(mr.title).to eq(title)
        expect(project.repository.commit(source_branch_name).title).to eq(title)
      end

      context 'when a merge request already exists for the branch' do
        let!(:existing_mr) do
          project.repository.create_branch(source_branch_name, project.default_branch_or_main)

          create(:merge_request,
            source_project: project,
            source_branch: source_branch_name,
            target_branch: project.default_branch_or_main,
            title: 'Security: Update rack from 2.0.9 to 2.1.0'
          )
        end

        it 'moves the title to the conventional format' do
          expect(execute.payload[:merge_request].title).to eq(title)
        end
      end

      context 'when the dependency_management_conventional_commits flag is disabled' do
        before do
          stub_feature_flags(dependency_management_conventional_commits: false)
        end

        it 'keeps the plain title and commit subject without reading the history', :aggregate_failures do
          expect(DependencyManagement::SecurityUpdate::CommitConvention).not_to receive(:detect)

          mr = execute.payload[:merge_request]

          expect(mr.title).to eq('Security: Update rack from 2.0.9 to 2.2.0')
          expect(project.repository.commit(source_branch_name).title).to eq('Update rack')
        end
      end
    end

    context 'when the repository does not use Conventional Commits' do
      before do
        allow(DependencyManagement::SecurityUpdate::CommitConvention).to receive(:detect).and_return(nil)
      end

      it 'keeps the plain commit subject' do
        execute

        expect(project.repository.commit(source_branch_name).title).to eq('Update rack')
      end

      context 'when the open merge request already has a conventional title' do
        before do
          project.repository.create_branch(source_branch_name, project.default_branch_or_main)

          create(:merge_request,
            source_project: project,
            source_branch: source_branch_name,
            target_branch: project.default_branch_or_main,
            title: 'Build(deps): [security] update rack from 2.0.9 to 2.1.0'
          )
        end

        it 'keeps its style without reading the history' do
          expect(DependencyManagement::SecurityUpdate::CommitConvention).not_to receive(:detect)

          expect(execute.payload[:merge_request].title).to eq('Build(deps): [security] update rack from 2.0.9 to 2.2.0')
        end

        context 'when the dependency_management_conventional_commits flag is disabled' do
          before do
            stub_feature_flags(dependency_management_conventional_commits: false)
          end

          it 'moves the title back to the plain format' do
            expect(execute.payload[:merge_request].title).to eq('Security: Update rack from 2.0.9 to 2.2.0')
          end
        end
      end
    end

    context 'when reading the commit history fails' do
      before do
        allow(project.repository).to receive(:commits).and_call_original
        allow(project.repository).to receive(:commits)
          .with(project.default_branch, limit: 50, skip_merges: true)
          .and_raise(Gitlab::Git::CommandError, 'boom')
      end

      it 'falls back to the plain format' do
        result = execute

        expect(result).to be_success
        expect(result.payload[:merge_request].title).to eq('Security: Update rack from 2.0.9 to 2.2.0')
      end
    end

    context 'when the vulnerability title is longer than 100 characters' do
      before do
        allow(vulnerability).to receive(:title).and_return("rack is vulnerable to #{'a very long description ' * 6}")
      end

      it 'wraps the commit body at 100 characters' do
        execute

        message = project.repository.commit(source_branch_name).message
        expect(message.lines.map(&:chomp)).to all(satisfy { |line| line.length <= 100 })
        expect(message).to include('Vulnerability: rack is vulnerable to')
      end
    end

    context 'when the vulnerability has no sbom_occurrences' do
      before do
        allow(vulnerability).to receive(:sbom_occurrences).and_return([])
        stub_no_remediated_occurrence
      end

      it 'tracks the create event with a nil purl_type' do
        expect { execute }
          .to trigger_internal_events('create_dependency_management_auto_remediation_mr')
          .with(
            project: project,
            additional_properties: {
              purl_type: nil,
              merge_request_id: kind_of(Integer)
            }
          )
      end
    end

    context 'when the exclusive lease cannot be obtained' do
      before do
        allow_next_instance_of(described_class) do |instance|
          allow(instance).to receive(:in_lock).and_raise(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
        end
      end

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('Could not obtain lock for merge request creation')
      end
    end

    context 'when the pipeline has not succeeded' do
      let(:pipeline) { create(:ci_pipeline, :failed, project: project) }

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('Pipeline has not completed successfully')
      end

      it 'does not track the create event' do
        expect { execute }
          .not_to trigger_internal_events('create_dependency_management_auto_remediation_mr')
      end
    end

    context 'when the service account cannot be provisioned' do
      before do
        allow_next_instance_of(DependencyManagement::ProvisionServiceAccountService) do |svc|
          allow(svc).to receive(:execute)
            .and_return(ServiceResponse.error(message: 'quota exceeded'))
        end
      end

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('Service account not available')
      end
    end

    context 'when the job producing output artifact is not found' do
      before do
        allow(pipeline).to receive(:find_job_with_archive_artifacts)
          .with('workload')
          .and_return(nil)
      end

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('job producing output.json artifact not found')
      end
    end

    context 'when the output artifact is too large' do
      before do
        allow(Gitlab::Ci::ArtifactFileReader).to receive(:new)
          .and_raise(Gitlab::Ci::ArtifactFileReader::Error,
            'Artifacts archive for job `workload` is too large')
      end

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('too large')
      end
    end

    context 'when the output contains no dependency changes' do
      let(:output_json) { { 'dependency_updates' => [], 'updated_files' => [] }.to_json }

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('No dependency changes found')
      end
    end

    context 'when the output contains no updated files' do
      let(:output_json) do
        {
          'dependency_updates' => [{ 'name' => 'rack', 'new_version' => '3.1.18', 'previous_version' => '3.1.17' }],
          'updated_files' => []
        }.to_json
      end

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('No updated files found')
      end
    end

    context 'when the source ref variable is missing' do
      before do
        allow(build).to receive(:variables).and_return([])
      end

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('Source ref is not set on pipeline')
      end
    end

    context 'when a merge request already exists for the branch' do
      before do
        project.repository.create_branch(source_branch_name, project.default_branch_or_main)

        ::Files::MultiService.new(project, project.creator, {
          commit_message: 'Add initial Gemfile',
          branch_name: source_branch_name,
          start_branch: source_branch_name,
          actions: [
            { action: 'create', file_path: 'Gemfile', content: 'gem "rack", "= 2.0.9"' },
            { action: 'create', file_path: 'Gemfile.lock', content: 'rack (2.0.9)' }
          ]
        }).execute
      end

      let!(:existing_mr) do
        create(:merge_request,
          source_project: project,
          source_branch: source_branch_name,
          target_branch: project.default_branch_or_main,
          state: :opened
        )
      end

      it 'updates the existing merge request instead of creating a new one' do
        result = execute

        expect(result).to be_success
        expect(result.payload[:merge_request].id).to eq(existing_mr.id)
      end

      it 'does not create a new merge request' do
        expect { execute }.not_to change { MergeRequest.count }
      end

      it 'updates the description on the existing merge request' do
        result = execute
        mr = result.payload[:merge_request]

        expect(mr.description).to include('Security Dependency Update')
        expect(mr.description).to include('`rack`')
      end

      it 'moves the title to the newly resolved version' do
        result = execute

        expect(result.payload[:merge_request].title).to eq(
          'Security: Update rack from 2.0.9 to 2.2.0'
        )
      end

      it 'restarts the refresh cooldown so the scheduler leaves it alone' do
        expect(DependencyManagement::SecurityUpdate::RefreshCooldown)
          .to receive(:start).with(existing_mr)

        execute
      end

      it 'links the vulnerability even when starting the cooldown fails' do
        allow(DependencyManagement::SecurityUpdate::RefreshCooldown)
          .to receive(:start).and_raise(Redis::BaseError)

        expect { execute }.to change { existing_mr.vulnerability_merge_request_links.count }.by(1)
      end
    end

    context 'when the output contains directory traversal paths' do
      let(:output_json) do
        {
          'dependency_updates' => [
            { 'name' => 'rack', 'new_version' => '3.1.18', 'previous_version' => '3.1.17' }
          ],
          'updated_files' => [
            { 'directory' => '../../../etc/', 'name' => 'passwd', 'content' => 'malicious' }
          ]
        }.to_json
      end

      it 'rejects the malicious path and returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('No updated files found')
      end
    end

    context 'when the licensed features are not available' do
      before do
        stub_licensed_features(dependency_scanning: false)
      end

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('Feature not available')
      end
    end

    context 'with multiple dependencies' do
      let(:output_json) { load_output_fixture('output_multiple_deps') }

      it 'creates a merge request with a multi-dependency title' do
        result = execute
        mr = result.payload[:merge_request]

        expect(mr.title).to eq('Security: Update 2 dependencies')
      end

      it 'includes all dependencies in the description' do
        result = execute
        mr = result.payload[:merge_request]

        expect(mr.description).to include('`rack`')
        expect(mr.description).to include('`rake`')
      end
    end

    context 'when untrusted input contains markdown-sensitive characters' do
      let(:output_json) do
        {
          'dependency_updates' => [
            { 'name' => 'evil<script>gem', 'new_version' => '2.0|injected', 'previous_version' => '1.0' }
          ],
          'updated_files' => [
            { 'name' => 'Gemfile', 'directory' => '/', 'content' => 'safe' }
          ]
        }.to_json
      end

      it 'wraps untrusted values in code spans and HTML-escapes them' do
        result = execute
        mr = result.payload[:merge_request]

        expect(mr.description).to include('`evil&lt;script&gt;gem`')
        expect(mr.description).to include('`2.0|injected`')
      end

      context 'when a dependency name contains a newline and markdown' do
        let(:output_json) do
          {
            'dependency_updates' => [
              { 'name' => "pkg\n## Injected", 'new_version' => '1.1.0', 'previous_version' => '1.0.0' }
            ],
            'updated_files' => [
              { 'name' => 'Gemfile', 'directory' => '/', 'content' => 'safe' }
            ]
          }.to_json
        end

        it 'collapses it into a single-line code span so the table row cannot break' do
          result = execute
          mr = result.payload[:merge_request]

          expect(mr.description).to include('`pkg ## Injected`')
          expect(mr.description).not_to include("pkg\n## Injected")
        end
      end

      context 'when the file path contains backticks' do
        let(:output_json) do
          {
            'dependency_updates' => [
              { 'name' => 'rack', 'new_version' => '2.2.0', 'previous_version' => '2.0.9' }
            ],
            'updated_files' => [
              { 'name' => 'a`b.lock', 'directory' => '/', 'content' => 'safe' }
            ]
          }.to_json
        end

        it 'wraps it in a backtick-safe code span' do
          result = execute
          mr = result.payload[:merge_request]

          expect(mr.description).to include('``a`b.lock``')
        end
      end
    end

    context 'when updating an existing merge request fails' do
      let!(:existing_mr) do
        create(:merge_request,
          source_project: project,
          source_branch: source_branch_name,
          target_branch: project.default_branch_or_main,
          state: :opened
        )
      end

      before do
        project.repository.create_branch(source_branch_name, project.default_branch_or_main)

        allow_next_instance_of(::MergeRequests::UpdateService) do |svc|
          allow(svc).to receive(:execute).and_return(
            existing_mr.tap { |mr| mr.errors.add(:base, 'Something went wrong') }
          )
        end
      end

      it 'returns an error response' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('Failed to update merge request')
      end

      it 'does not link the vulnerability' do
        execute

        expect(Vulnerabilities::MergeRequestLink.where(vulnerability: vulnerability)).not_to exist
      end
    end

    context 'when an unexpected error occurs' do
      before do
        allow_next_instance_of(described_class) do |svc|
          allow(svc).to receive(:create_branch_and_commit).and_raise(StandardError, 'boom')
        end
      end

      it 'returns an error response' do
        result = execute

        expect(result).to be_error
        expect(result.message).to eq('Unexpected error creating merge request')
      end
    end

    context 'when the artifact content cannot be read' do
      before do
        allow(Gitlab::Ci::ArtifactFileReader).to receive(:new)
          .and_raise(Gitlab::Ci::ArtifactFileReader::Error,
            'Path `output.json` does not exist inside the `workload` artifacts archive!')
      end

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('Failed to read output.json artifact')
      end
    end

    context 'when the output artifact contains invalid JSON' do
      before do
        allow(Gitlab::Ci::ArtifactFileReader).to receive(:new)
          .with(build, max_archive_size: 5.megabytes)
          .and_return(instance_double(Gitlab::Ci::ArtifactFileReader,
            read: 'not valid json {{{'
          ))
      end

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('Failed to parse output.json')
      end
    end

    context 'when the output contains too many file changes' do
      let(:output_json) do
        {
          'dependency_updates' => [{ 'name' => 'rack', 'new_version' => '3.1.18', 'previous_version' => '3.1.17' }],
          'updated_files' => Array.new(51) { |i| { 'directory' => '/', 'name' => "file_#{i}.rb", 'content' => 'x' } }
        }.to_json
      end

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('Too many file changes')
      end
    end

    context 'when committing files fails' do
      before do
        allow_next_instance_of(::Files::MultiService) do |svc|
          allow(svc).to receive(:execute).and_return({ status: :error, message: 'commit failed' })
        end
      end

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('Failed to commit changes')
      end
    end

    context 'when a git pre-receive hook rejects the push' do
      before do
        allow_next_instance_of(::Files::MultiService) do |svc|
          allow(svc).to receive(:execute).and_raise(Gitlab::Git::PreReceiveError, 'hook rejected')
        end
      end

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('Git pre-receive hook rejected the push')
      end
    end

    context 'when a git command error occurs during commit' do
      before do
        allow_next_instance_of(::Files::MultiService) do |svc|
          allow(svc).to receive(:execute).and_raise(Gitlab::Git::CommandError, 'git error')
        end
      end

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('Git error while committing')
      end
    end

    describe 'the commit' do
      let(:tip) { project.repository.commit(source_branch_name) }

      context 'when the branch already has commits of its own' do
        before do
          project.repository.create_branch(source_branch_name, project.default_branch_or_main)
          project.repository.create_file(
            project.creator, 'NOTE.md', 'note', message: 'note', branch_name: source_branch_name
          )
        end

        it 'writes one commit whose parent is the pipeline SHA' do
          execute

          expect(tip.parent_ids).to eq([pipeline.sha])
        end
      end

      context 'when the branch does not exist' do
        where(:target_sha_flag) { [true, false] }

        with_them do
          before do
            stub_feature_flags(commit_files_target_sha: target_sha_flag)
          end

          it 'creates the branch with the commit' do
            execute

            expect(tip.parent_ids).to eq([pipeline.sha])
          end
        end
      end

      context 'when the default branch moved after the workload started' do
        let!(:original_head) { project.repository.commit(project.default_branch_or_main).sha }

        before do
          project.repository.create_file(
            maintainer, 'MOVED.md', 'moved', message: 'move', branch_name: project.default_branch_or_main
          )
        end

        after do
          project.repository.update_branch(
            project.default_branch_or_main,
            user: maintainer,
            newrev: original_head,
            oldrev: project.repository.commit(project.default_branch_or_main).sha
          )
        end

        it 'still commits on the pipeline SHA' do
          execute

          expect(tip.parent_ids).to eq([original_head])
        end
      end

      context 'when the merge request conflicts because the target moved on' do
        let(:original_head) { project.repository.commit(project.default_branch_or_main).sha }
        # The workload ran after the target branch added a lockfile that clashes with the bump
        # commit's. Reading original_head first pins it before the move.
        let(:moved_head) do
          original_head
          project.repository.create_file(
            maintainer, 'Gemfile.lock', 'lock on main', message: 'move', branch_name: project.default_branch_or_main
          )
        end

        let(:pipeline) { create(:ci_pipeline, :success, project: project, sha: moved_head) }
        let(:merge_request) do
          create(:merge_request, source_project: project, source_branch: source_branch_name,
            target_branch: project.default_branch_or_main)
        end

        # The push-triggered diff refresh is asynchronous, so reload the diff first.
        def mergeable?
          merge_request.reload.reload_diff(maintainer)
          MergeRequests::MergeabilityCheckService.new(merge_request).execute(recheck: true)
          merge_request.reload.can_be_merged?
        end

        before do
          bot = DependencyManagement::ProvisionServiceAccountService.new(project: project).execute.payload[:user]
          project.repository.create_branch(source_branch_name, original_head)
          project.repository.create_file(
            bot, 'Gemfile.lock', 'old bump', message: 'Update rack', branch_name: source_branch_name
          )
          pipeline
        end

        after do
          project.repository.update_branch(
            project.default_branch_or_main,
            user: maintainer,
            newrev: original_head,
            oldrev: project.repository.commit(project.default_branch_or_main).sha
          )
        end

        it 'rebases the branch onto the pipeline SHA so the merge request is mergeable again' do
          expect(mergeable?).to be(false)

          execute

          expect(tip.parent_ids).to eq([pipeline.sha])
          expect(mergeable?).to be(true)
        end
      end
    end

    describe 'skipping an unchanged refresh' do
      def stub_output(json)
        allow(Gitlab::Ci::ArtifactFileReader).to receive(:new)
          .and_return(instance_double(Gitlab::Ci::ArtifactFileReader, read: json))
      end

      def open_merge_request
        project.merge_requests.opened.find_by(source_branch: source_branch_name)
      end

      # MergeRequests::AfterCreateService finishes preparing a merge request before any refresh runs.
      def prepare_open_merge_request
        merge_request = open_merge_request
        return unless merge_request&.preparing?

        merge_request.ensure_merge_request_diff
        merge_request.update_column(:merge_status, 'unchecked')
      end

      # A later commit time, so a re-commit of identical content gets a new SHA rather than
      # repeating the first one.
      def run_again
        prepare_open_merge_request
        travel_to(1.minute.from_now) do
          described_class.new(project: project, pipeline: pipeline, vulnerability: vulnerability).execute
        end
      end

      def tip
        project.repository.commit(source_branch_name)
      end

      def edit_first_file(json)
        Gitlab::Json::SafeParser.parse(json).tap { |output| yield output['updated_files'] }.to_json
      end

      context 'when the output matches the open merge request' do
        before do
          execute
        end

        it 'skips the commit and reports the run as skipped', :aggregate_failures do
          merge_request = project.merge_requests.find_by(source_branch: source_branch_name)

          expect(DependencyManagement::SecurityUpdate::RefreshCooldown).to receive(:start).with(merge_request)
          expect(MergeRequestMergeabilityCheckWorker).not_to receive(:perform_async)
          allow(Gitlab::AppLogger).to receive(:info)
          expect(Gitlab::AppLogger).to receive(:info).with(hash_including(
            skip_reason: :unchanged, Labkit::Fields::GL_PROJECT_ID => project.id, source_branch: source_branch_name
          ))

          result = nil
          expect { result = run_again }.not_to change { MergeRequest.find(merge_request.id).source_branch_sha }
          expect(result.payload).to include(skipped: true, merge_request: merge_request)
          expect(open_merge_request).to be_can_be_merged
        end

        it 'brings a stale description up to date without pushing' do
          open_merge_request.update_column(:description, 'stale')

          expect { run_again }.not_to change { tip.sha }
          expect(open_merge_request.description).to include('This merge request was automatically generated')
        end

        it 'returns the error and starts no cooldown when the title and description cannot be updated' do
          allow_next_instance_of(::MergeRequests::UpdateService) do |service|
            allow(service).to receive(:execute) do |merge_request|
              merge_request.tap { |mr| mr.errors.add(:base, 'Something went wrong') }
            end
          end
          expect(DependencyManagement::SecurityUpdate::RefreshCooldown).not_to receive(:start)

          result = nil
          expect { result = run_again }.not_to change { tip.sha }
          expect(result).to be_error
          expect(result.message).to include('Failed to update merge request')
        end

        it 'releases the branch head, so a conflict found later is refreshed straight away',
          :clean_gitlab_redis_shared_state do
          merge_request = project.merge_requests.find_by(source_branch: source_branch_name)
          DependencyManagement::SecurityUpdate::RefreshCooldown.hold_head(merge_request)

          run_again

          expect(DependencyManagement::SecurityUpdate::RefreshCooldown.conflict_refresh_due?(merge_request)).to be(true)
        end
      end

      context 'when the merge request was closed after the first run' do
        before do
          execute
          project.merge_requests.find_by(source_branch: source_branch_name).close!
          allow_next_instance_of(DependencyManagement::SecurityUpdate::RemediationDismissalChecker) do |checker|
            allow(checker).to receive(:dismissed?).and_return(false)
          end
        end

        it 'commits and opens a new merge request' do
          expect { run_again }.to change { tip.sha }
            .and change { project.merge_requests.opened.where(source_branch: source_branch_name).count }.from(0).to(1)
        end
      end

      context 'when the tip commit also changes a file the output does not' do
        it 'commits, so the branch holds only the output files' do
          execute
          bot = DependencyManagement::ProvisionServiceAccountService.new(project: project).execute.payload[:user]
          files = Gitlab::Json::SafeParser.parse(output_json)['updated_files']
          ::Files::MultiService.new(project, bot, {
            commit_message: 'Update rack', branch_name: source_branch_name, start_sha: pipeline.sha, force: true,
            actions: files.map { |f| { action: 'create', file_path: f['name'], content: f['content'] } } +
              [{ action: 'create', file_path: 'EXTRA.md', content: 'extra' }]
          }).execute

          expect { run_again }.to change { tip.sha }
          expect(project.repository.blob_at(tip.sha, 'EXTRA.md')).to be_nil
        end
      end

      context 'when the repository uses SHA-256 object IDs' do
        let_it_be(:project) do
          create(:project, :small_repo, object_format: Repository::FORMAT_SHA256, group: group,
            organization: organization)
        end

        let_it_be(:vulnerability) { create(:vulnerability, :with_finding, project: project, severity: :high) }

        it 'still recognises an identical refresh as unchanged' do
          execute

          expect { run_again }.not_to change { tip.sha }
        end
      end

      context 'when the branch was deleted while the merge request stays open' do
        it 'recreates it with one commit on the pipeline SHA' do
          execute
          project.repository.delete_branch(source_branch_name)

          run_again

          expect(tip.parent_ids).to eq([pipeline.sha])
        end
      end

      # Gitaly writes blobs with `hash-object --path`, but with attr.tree set to the empty tree and
      # core.autocrlf off, so these attributes and the CRLF endings leave the stored bytes as given.
      context 'when the repository has attributes that would rewrite the output on write' do
        let(:content) { "line one\r\n$Id: abc123 $\r\n" }
        let(:original_head) { project.repository.commit(project.default_branch_or_main).sha }
        let(:attributes_head) do
          original_head
          project.repository.create_file(
            maintainer, '.gitattributes', "* text\n* ident\n", message: 'attributes',
            branch_name: project.default_branch_or_main
          )
        end

        let(:pipeline) { create(:ci_pipeline, :success, project: project, sha: attributes_head) }

        before do
          stub_output(edit_first_file(output_json) { |files| files.first['content'] = content })
        end

        after do
          project.repository.update_branch(
            project.default_branch_or_main,
            user: maintainer,
            newrev: original_head,
            oldrev: project.repository.commit(project.default_branch_or_main).sha
          )
        end

        it 'stores the output bytes unchanged and still recognises an identical refresh' do
          execute
          path = Gitlab::Json::SafeParser.parse(output_json)['updated_files'].first['name']

          expect(project.repository.blob_at(tip.sha, path).data.b).to eq(content.b)
          expect { run_again }.not_to change { tip.sha }
        end
      end

      context 'when the matching output is base64 encoded' do
        it 'still recognises it as unchanged' do
          execute
          allow(DependencyManagement::SecurityUpdate::OutputParser).to receive(:parse)
            .and_wrap_original do |parse, *args|
            parse.call(*args).tap do |output|
              output.updated_files.each do |file|
                file.content = Base64.strict_encode64(file.content)
                file.encoding = 'base64'
              end
            end
          end

          expect { run_again }.not_to change { tip.sha }
        end
      end

      context 'when the matching output contains non-ASCII text' do
        it 'still recognises it as unchanged' do
          stub_output(edit_first_file(output_json) { |files| files.first['content'] += "\n# café 🔒\n" })
          execute

          expect { run_again }.not_to change { tip.sha }
        end
      end

      context 'when the output changed' do
        it 'writes exactly one new commit whose parent is the pipeline SHA' do
          execute
          stub_output(edit_first_file(output_json) { |files| files.first['content'] += "\n# changed\n" })

          expect { run_again }.to change { tip.sha }
          expect(tip.parent_ids).to eq([pipeline.sha])
        end
      end

      context 'when the output adds a file that is not at the tip' do
        it 'commits' do
          execute
          stub_output(edit_first_file(output_json) { |files| files << files.first.merge('name' => 'NEW_FILE.lock') })

          expect { run_again }.to change { tip.sha }
        end
      end

      context 'when the first run failed to link the vulnerability' do
        it 'links it on an identical refresh' do
          allow(Vulnerabilities::MergeRequestLink).to receive(:create).and_raise(StandardError, 'boom')
          execute
          allow(Vulnerabilities::MergeRequestLink).to receive(:create).and_call_original

          expect { run_again }.to change { Vulnerabilities::MergeRequestLink.count }.by(1)
        end
      end

      context 'when the tip deletes an output file that exists at the pipeline SHA' do
        let(:original_head) { project.repository.commit(project.default_branch_or_main).sha }
        let(:gemfile_head) do
          original_head
          project.repository.create_file(
            maintainer, 'Gemfile', 'base', message: 'add Gemfile', branch_name: project.default_branch_or_main
          )
        end

        let(:pipeline) { create(:ci_pipeline, :success, project: project, sha: gemfile_head) }

        after do
          project.repository.update_branch(
            project.default_branch_or_main,
            user: maintainer,
            newrev: original_head,
            oldrev: project.repository.commit(project.default_branch_or_main).sha
          )
        end

        it 'commits, so the deleted file comes back' do
          execute
          bot = DependencyManagement::ProvisionServiceAccountService.new(project: project).execute.payload[:user]
          lock = Gitlab::Json::SafeParser.parse(output_json)['updated_files'].find { |f| f['name'] == 'Gemfile.lock' }
          ::Files::MultiService.new(project, bot, {
            commit_message: 'Update rack', branch_name: source_branch_name, start_sha: pipeline.sha, force: true,
            actions: [
              { action: 'delete', file_path: 'Gemfile' },
              { action: 'create', file_path: 'Gemfile.lock', content: lock['content'] }
            ]
          }).execute

          expect { run_again }.to change { tip.sha }
          expect(project.repository.blob_at(tip.sha, 'Gemfile')).to be_present
        end
      end

      context 'when the target branch moves after the first run' do
        let(:original_head) { project.repository.commit(project.default_branch_or_main).sha }
        let(:newer_pipeline) { create(:ci_pipeline, :success, project: project, sha: moved_head) }

        before do
          original_head
          allow(newer_pipeline).to receive(:find_job_with_archive_artifacts).with('workload').and_return(build)
        end

        after do
          project.repository.update_branch(
            project.default_branch_or_main,
            user: maintainer,
            newrev: original_head,
            oldrev: project.repository.commit(project.default_branch_or_main).sha
          )
        end

        def refresh_on_moved_target
          prepare_open_merge_request
          travel_to(1.minute.from_now) do
            described_class.new(project: project, pipeline: newer_pipeline, vulnerability: vulnerability).execute
          end
        end

        context 'with unrelated changes' do
          let(:moved_head) do
            project.repository.create_file(
              maintainer, 'UNRELATED.md', 'x', message: 'move', branch_name: project.default_branch_or_main
            )
          end

          it 'skips the commit, leaving the merge request on its base' do
            execute
            moved_head

            expect { refresh_on_moved_target }.not_to change { tip.sha }
          end

          context 'when the project only allows fast-forward merges' do
            it 'still commits, so the merge request can merge' do
              execute
              moved_head
              allow(project).to receive(:ff_merge_must_be_possible?).and_return(true)

              expect { refresh_on_moved_target }.to change { tip.sha }
              expect(tip.parent_ids).to eq([newer_pipeline.sha])
            end
          end
        end

        context 'with a change to an output file' do
          let(:moved_head) do
            project.repository.create_file(
              maintainer, 'Gemfile', 'main edit', message: 'move', branch_name: project.default_branch_or_main
            )
          end

          # The default branch's change conflicts with the merge request, but the updater writes the same file.
          context 'when the output is unchanged and a push left the merge request unchecked' do
            it 'finds the conflict and commits on the new pipeline SHA' do
              execute
              moved_head
              open_merge_request.update_column(:merge_status, 'unchecked')

              expect { refresh_on_moved_target }.to change { tip.sha }
              expect(tip.parent_ids).to eq([newer_pipeline.sha])
            end
          end

          it 'commits on the new pipeline SHA' do
            execute
            moved_head
            # A workload on the moved target sees main's Gemfile, so its output differs from the tip.
            stub_output(edit_first_file(output_json) do |files|
              files.first['content'] = "main edit\n#{files.first['content']}"
            end)

            expect { refresh_on_moved_target }.to change { tip.sha }
            expect(tip.parent_ids).to eq([newer_pipeline.sha])
          end
        end
      end

      context 'when the merge request cannot be merged' do
        it 'still commits, even though the output matches the tip' do
          execute
          project.merge_requests.find_by(source_branch: source_branch_name)
            .update_column(:merge_status, 'cannot_be_merged')

          expect { run_again }.to change { tip.sha }
          expect(tip.parent_ids).to eq([pipeline.sha])
        end
      end

      context 'when the branch and the pipeline SHA share no history' do
        it 'does not treat the output as unchanged' do
          execute
          allow(project.repository).to receive(:merge_base).and_return(nil)

          expect(Gitlab::AppLogger).not_to receive(:info).with(hash_including(skip_reason: :unchanged))
          run_again
        end
      end

      # Anything but a confirmed mergeable status commits: a needless commit is recoverable, a skip every round is not.
      context 'when the mergeability check cannot finish' do
        it 'commits' do
          execute
          open_merge_request.update_column(:merge_status, 'cannot_be_merged_recheck')
          allow_next_instance_of(MergeRequests::MergeabilityCheckService) do |service|
            allow(service).to receive(:execute).and_return(ServiceResponse.error(message: 'Failed to obtain a lock'))
          end

          expect { run_again }.to change { tip.sha }
          expect(tip.parent_ids).to eq([pipeline.sha])
        end
      end

      context 'when the mergeability check raises' do
        it 'commits and succeeds' do
          execute
          allow_next_instance_of(MergeRequests::MergeabilityCheckService) do |service|
            allow(service).to receive(:execute).and_raise(StandardError, 'Gitaly unavailable')
          end

          result = nil
          expect { result = run_again }.to change { tip.sha }
          expect(result).to be_success
        end
      end

      context 'when the merge request has not caught up with the branch tip' do
        it 'commits, since its merge status describes another head' do
          execute
          prepare_open_merge_request
          open_merge_request.merge_request_diff.update_column(:head_commit_sha, pipeline.sha)

          expect { run_again }.to change { tip.sha }
        end
      end

      context 'when the repository moved to Conventional Commits after the merge request opened' do
        let(:style) { DependencyManagement::SecurityUpdate::CommitConvention::Style.new(type: 'build', capitalize: false) }

        it 'commits with the conventional subject and moves the title with it', :aggregate_failures do
          allow(DependencyManagement::SecurityUpdate::CommitConvention).to receive(:detect).and_return(nil)
          execute
          allow(DependencyManagement::SecurityUpdate::CommitConvention).to receive(:detect).and_return(style)

          expect { run_again }.to change { tip.sha }
          expect(tip.full_title).to start_with('build(deps): [security] update')
          expect(open_merge_request.title).to eq(tip.full_title)
        end
      end

      context 'when the branch tip is the pipeline SHA itself' do
        it 'commits rather than skipping, even when the output matches the base' do
          execute
          files = Gitlab::Json::SafeParser.parse(output_json)['updated_files']
          ::Files::MultiService.new(project, maintainer, {
            commit_message: 'base', branch_name: project.default_branch_or_main,
            start_branch: project.default_branch_or_main,
            actions: files.map { |f| { action: 'create', file_path: f['name'], content: f['content'] } }
          }).execute
          base = project.repository.commit(project.default_branch_or_main).sha
          project.repository.update_branch(source_branch_name, user: maintainer, newrev: base, oldrev: tip.sha)
          on_base = create(:ci_pipeline, :success, project: project, sha: base)
          allow(on_base).to receive(:find_job_with_archive_artifacts).with('workload').and_return(build)

          result = travel_to(1.minute.from_now) do
            described_class.new(project: project, pipeline: on_base, vulnerability: vulnerability).execute
          end

          expect(result.payload[:skipped]).not_to be(true)
        ensure
          project.repository.update_branch(project.default_branch_or_main, user: maintainer,
            newrev: pipeline.sha, oldrev: project.repository.commit(project.default_branch_or_main).sha)
        end
      end

      context 'when the branch has a commit that changes a non-output file' do
        it 'commits, rebasing the branch onto the pipeline SHA' do
          execute
          # The output files still match, so only the parent check can force the commit.
          project.repository.create_file(
            maintainer, 'NOTE.md', 'note', message: 'note', branch_name: source_branch_name
          )

          expect { run_again }.to change { tip.sha }
          expect(tip.parent_ids).to eq([pipeline.sha])
        end
      end
    end

    context 'when updated files already exist on the branch' do
      before do
        project.repository.create_branch(source_branch_name, project.default_branch_or_main)
        project.repository.create_file(
          project.creator, 'Gemfile', 'original', message: 'init', branch_name: source_branch_name
        )
      end

      it 'commits when the files exist only on the branch' do
        result = execute

        expect(result).to be_success
      end

      it 'checks file existence in a single batched Gitaly call' do
        expect(project.repository).to receive(:blobs_at).once.and_call_original

        execute
      end

      it 'decides create or update from the pipeline SHA, not the branch tip' do
        actions_used = nil

        expect_next_instance_of(::Files::MultiService) do |svc|
          expect(svc).to receive(:execute).with(no_args).and_wrap_original do |original|
            actions_used = svc.params[:actions]
            original.call
          end
        end

        execute

        expect(actions_used).to contain_exactly(
          hash_including(action: 'create', file_path: 'Gemfile'),
          hash_including(action: 'create', file_path: 'Gemfile.lock')
        )
      end
    end

    context 'when an updated file exists at the pipeline SHA' do
      let(:base_branch) { 'dependency-management-spec-base' }
      # Built in the let, not a before: the top-level before evaluates pipeline first.
      let(:pipeline) do
        project.repository.create_branch(base_branch, project.default_branch_or_main)
        sha = project.repository.create_file(
          project.creator, 'Gemfile', 'original', message: 'add Gemfile', branch_name: base_branch
        )

        create(:ci_pipeline, :success, project: project, sha: sha)
      end

      after do
        project.repository.delete_branch(base_branch) if project.repository.branch_exists?(base_branch)
      end

      it 'updates the file that exists there and creates the one that does not' do
        actions_used = nil

        expect_next_instance_of(::Files::MultiService) do |svc|
          expect(svc).to receive(:execute).with(no_args).and_wrap_original do |original|
            actions_used = svc.params[:actions]
            original.call
          end
        end

        expect(execute).to be_success
        expect(actions_used).to contain_exactly(
          hash_including(action: 'update', file_path: 'Gemfile'),
          hash_including(action: 'create', file_path: 'Gemfile.lock')
        )
      end
    end

    context 'when merge request creation fails' do
      before do
        allow_next_instance_of(::MergeRequests::CreateService) do |svc|
          allow(svc).to receive(:execute).and_return(
            MergeRequest.new.tap { |mr| mr.errors.add(:base, 'invalid') }
          )
        end
      end

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('Failed to create merge request')
      end
    end

    context 'when saving the vulnerability link fails' do
      before do
        allow_next_instance_of(Vulnerabilities::MergeRequestLink) do |link|
          allow(link).to receive(:save).and_return(false)
        end
      end

      it 'still returns success' do
        result = execute

        expect(result).to be_success
      end

      it 'does not call UpsertService' do
        expect(Vulnerabilities::Reads::UpsertService).not_to receive(:new)

        execute
      end

      it 'logs a warning' do
        expect(Gitlab::AppLogger).to receive(:warn).with(
          hash_including(
            message: 'DependencyManagement: failed to link vulnerability to merge request',
            vulnerability_id: vulnerability.id,
            project_id: project.id
          )
        )

        execute
      end
    end

    context 'when linking the vulnerability raises an error' do
      before do
        allow_next_instance_of(Vulnerabilities::MergeRequestLink) do |link|
          allow(link).to receive(:save).and_raise(StandardError, 'db error')
        end
      end

      it 'still returns success' do
        result = execute

        expect(result).to be_success
      end
    end

    context 'when the merge request is refreshed' do
      it 'reuses the existing link and still flags the vulnerability read' do
        merge_request = execute.payload[:merge_request]
        # Changed output, so this covers a refresh that commits. A skipped refresh links too: see
        # 'when the first run failed to link the vulnerability'.
        changed_output = Gitlab::Json::SafeParser.parse(output_json)
          .tap { |output| output['updated_files'].first['content'] += "\n# changed\n" }.to_json
        allow(Gitlab::Ci::ArtifactFileReader).to receive(:new)
          .and_return(instance_double(Gitlab::Ci::ArtifactFileReader, read: changed_output))

        expect(Gitlab::AppLogger).not_to receive(:warn)
          .with(hash_including(message: 'DependencyManagement: failed to link vulnerability to merge request'))
        expect_next_instance_of(Vulnerabilities::Reads::UpsertService) do |upsert|
          expect(upsert).to receive(:execute)
        end

        result = nil
        expect do
          result = described_class.new(project: project, pipeline: pipeline, vulnerability: vulnerability).execute
        end.not_to change { Vulnerabilities::MergeRequestLink.count }

        expect(result).to be_success
        expect(result.payload[:merge_request]).to eq(merge_request)
      end
    end

    context 'when the output.json artifact reader returns nil' do
      before do
        allow(Gitlab::Ci::ArtifactFileReader).to receive(:new)
          .with(build, max_archive_size: 5.megabytes)
          .and_return(instance_double(Gitlab::Ci::ArtifactFileReader, read: nil))
      end

      it 'returns an error' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('output.json artifact not found')
      end
    end

    context 'when build.variables is nil' do
      before do
        allow(build).to receive(:variables).and_return(nil)
      end

      it 'returns an error about the missing source ref' do
        result = execute

        expect(result).to be_error
        expect(result.message).to include('Source ref is not set on pipeline')
      end
    end

    context 'when merge_request is nil in link_vulnerability_to_merge_request' do
      before do
        allow_next_instance_of(described_class) do |svc|
          allow(svc).to receive(:create_or_update_merge_request)
            .and_return(ServiceResponse.success(payload: { merge_request: nil }))
        end
      end

      it 'skips linking and still returns success' do
        result = execute

        expect(result).to be_success
        expect(Vulnerabilities::MergeRequestLink.where(vulnerability: vulnerability)).not_to exist
      end
    end

    describe 'remediation dismissal' do
      context 'when a user dismissed a previous remediation' do
        # The valid output bumps `rack` 2.0.9 -> 2.2.0.
        let_it_be(:closer) { create(:user, organization: organization) }

        # The same service account the service provisions (idempotent), so it can push the
        # branch and authors the previously-dismissed MR.
        let(:service_account) do
          DependencyManagement::ProvisionServiceAccountService.new(project: project).execute.payload[:user]
        end

        before do
          # RemediationDismissalChecker derives the ecosystem from the vulnerability.
          allow(vulnerability).to receive(:sbom_occurrences)
            .and_return([instance_double(Sbom::Occurrence, purl_type: 'gem')])

          # These cover the merge request history path. The persisted record path
          # is covered in remediation_dismissal_checker_spec.rb.
          stub_feature_flags(dependency_management_persisted_remediations: false)
        end

        def create_dismissed_mr(version:, closed_by:, vulnerability_for_link: vulnerability)
          mr = create(:merge_request, :closed, :with_closed_by,
            target_project: project, source_project: project, author: service_account,
            source_branch: source_branch_name, target_branch: project.default_branch_or_main,
            title: "Security: Update rack from 2.0.9 to #{version}", skip_branch_existence_check: true,
            closed_by: closed_by)
          create(:vulnerabilities_merge_request_link,
            vulnerability: vulnerability_for_link, finding: vulnerability_for_link.finding, merge_request: mr)
          mr
        end

        context 'and the proposed version is not newer' do
          before do
            create_dismissed_mr(version: '2.2.0', closed_by: closer)
          end

          it 'does not create a merge request' do
            allow(DependencyManagement::SecurityUpdate::RescheduleWorker).to receive(:perform_async)

            expect { execute }.not_to change { project.merge_requests.opened.count }
          end

          it 'returns a skipped response and reschedules the next candidate' do
            expect(DependencyManagement::SecurityUpdate::RescheduleWorker)
              .to receive(:perform_async).with(project.id)

            result = execute

            expect(result).to be_success
            expect(result.payload[:skipped]).to be(true)
          end

          it 'does not look up the remediated occurrence' do
            allow(DependencyManagement::SecurityUpdate::RescheduleWorker).to receive(:perform_async)
            expect(DependencyManagement::SecurityUpdate::SbomOccurrenceFinder).not_to receive(:new)

            expect(execute.payload[:skipped]).to be(true)
          end
        end

        context 'and the proposed version is newer (resurface)' do
          before do
            create_dismissed_mr(version: '2.1.0', closed_by: closer)
          end

          it 'creates a merge request and does not reschedule' do
            expect(DependencyManagement::SecurityUpdate::RescheduleWorker).not_to receive(:perform_async)

            expect { execute }.to change { project.merge_requests.opened.count }.by(1)
          end
        end

        context 'when the service account closed it' do
          before do
            create_dismissed_mr(version: '2.2.0', closed_by: service_account)
          end

          it 'recreates the merge request so it is still retried' do
            expect { execute }.to change { project.merge_requests.opened.count }.by(1)
          end
        end

        context 'when the dismissal was for a different vulnerability' do
          let_it_be(:other_vulnerability) { create(:vulnerability, :with_finding, project: project, severity: :high) }

          before do
            create_dismissed_mr(version: '2.2.0', closed_by: closer, vulnerability_for_link: other_vulnerability)
          end

          it 'creates a merge request (a new finding is not suppressed)' do
            expect { execute }.to change { project.merge_requests.opened.count }.by(1)
          end
        end
      end
    end
  end
end
