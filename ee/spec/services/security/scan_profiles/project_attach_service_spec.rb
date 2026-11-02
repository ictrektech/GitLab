# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::ScanProfiles::ProjectAttachService, feature_category: :security_testing_configuration do
  let_it_be(:root_group) { create(:group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:project1) { create(:project, namespace: root_group) }
  let_it_be(:project2) { create(:project, namespace: root_group) }
  let_it_be(:project_at_limit) { create(:project, namespace: root_group) }
  let_it_be(:profile) do
    create(:security_scan_profile, namespace: root_group, scan_type: :secret_detection, name: 'Test Profile')
  end

  let_it_be(:other_profile) { create(:security_scan_profile, namespace: root_group, scan_type: :sast) }
  let_it_be(:at_limit_association) do
    create(:security_scan_profile_project, project: project_at_limit, scan_profile: other_profile)
  end

  let_it_be(:old_profile) do
    create(:security_scan_profile, namespace: root_group, scan_type: :secret_detection, name: 'Old Profile')
  end

  let_it_be(:other_type_profile) do
    create(:security_scan_profile, namespace: root_group, scan_type: :dependency_scanning)
  end

  shared_examples 'returns empty errors' do
    it 'returns empty errors' do
      result = execute_service

      expect(result[:errors]).to be_empty
    end
  end

  shared_examples 'does not schedule the analyzer status update worker' do
    it 'does not schedule the analyzer status update worker' do
      expect(Security::AnalyzersStatus::ScheduleSettingChangedUpdateWorker).not_to receive(:perform_async)

      execute_service
    end
  end

  describe '.execute' do
    subject(:execute_service) do
      described_class.execute(profile: profile, current_user: current_user, projects: projects)
    end

    let(:current_user) { user }

    context 'when no projects are provided' do
      let(:projects) { [] }

      it 'returns an error' do
        result = execute_service

        expect(result[:errors]).to include('At least one project must be provided')
      end

      it 'does not create any associations' do
        expect { execute_service }.not_to change { Security::ScanProfileProject.count }
      end
    end

    context 'when an archived project is provided' do
      let_it_be(:archived_group) { create(:group, :archived, parent: root_group) }
      let_it_be(:self_archived_project) { create(:project, :archived, namespace: root_group) }
      let_it_be(:ancestor_archived_project) { create(:project, namespace: archived_group) }

      let_it_be(:more_self_archived_projects) { create_list(:project, 2, :archived, namespace: root_group) }
      let_it_be(:n_plus_one_profile) { create(:security_scan_profile, namespace: root_group, name: 'N+1 Profile') }

      let(:projects) { [project1, self_archived_project, ancestor_archived_project] }

      it 'records the effective archived state on each new association' do
        execute_service

        archived_by_project_id = Security::ScanProfileProject
          .where(scan_profile: profile)
          .pluck(:project_id, :archived)
          .to_h

        expect(archived_by_project_id).to eq(
          project1.id => false,
          self_archived_project.id => true,
          ancestor_archived_project.id => true
        )
      end

      # `self_or_ancestors_archived?` reaches `project_namespace` for a self-archived
      # project, so without that preload each one costs an extra query.
      it 'does not issue a query per archived project' do
        control = ActiveRecord::QueryRecorder.new do
          described_class.execute(
            profile: profile,
            current_user: nil,
            projects: Project.id_in(self_archived_project.id).to_a
          )
        end

        expect do
          described_class.execute(
            profile: n_plus_one_profile,
            current_user: nil,
            projects: Project.id_in(more_self_archived_projects.map(&:id)).to_a
          )
        end.not_to exceed_query_limit(control)
      end
    end

    context 'when projects are provided' do
      let(:projects) { [project1, project2] }

      it 'creates associations for all projects' do
        expect { execute_service }.to change { Security::ScanProfileProject.count }.by(projects.count)
      end

      it 'creates correct associations' do
        execute_service

        expect(Security::ScanProfileProject.where(project: project1, scan_profile: profile)).to exist
        expect(Security::ScanProfileProject.where(project: project2, scan_profile: profile)).to exist
      end

      it 'creates the associations as unarchived' do
        execute_service

        expect(Security::ScanProfileProject.where(scan_profile: profile).pluck(:archived)).to all(be(false))
      end

      it 'initializes profile status records for attached projects' do
        execute_service

        statuses = Security::ScanProfileProjectStatus.where(
          project_id: [project1.id, project2.id],
          security_scan_profile_id: profile.id
        ).index_by(&:project_id)

        expect(statuses.keys).to match_array([project1.id, project2.id])

        statuses.each_value do |status|
          expect(status).to have_attributes(
            status: 'success',
            consecutive_failure_count: 0,
            consecutive_success_count: 0
          )
        end
      end

      it 'schedules the analyzer status update worker' do
        expect(Security::AnalyzersStatus::ScheduleSettingChangedUpdateWorker).to receive(:perform_async)
          .with(contain_exactly(project1.id, project2.id), profile.scan_type)

        execute_service
      end

      it 'does not schedule the triage coverage update worker for a non-remediation scan type' do
        expect(Security::TriageCoverage::ScheduleUpdateWorker).not_to receive(:perform_async)

        execute_service
      end

      it_behaves_like 'returns empty errors'
    end

    context 'when profile scan_type is a remediation type' do
      let(:projects) { [project1, project2] }
      let(:profile) { create(:security_scan_profile, :triage_and_remediation, namespace: root_group) }

      it 'schedules the triage coverage update worker for attached projects' do
        expect(Security::TriageCoverage::ScheduleUpdateWorker).to receive(:perform_async)
          .with(contain_exactly(project1.id, project2.id))

        execute_service
      end
    end

    context 'when profile scan_type is dependency_scanning_post_processing' do
      let(:projects) { [project1, project2] }
      let(:profile) { create(:security_scan_profile, :dependency_scanning_post_processing, namespace: root_group) }

      it 'schedules the triage coverage update worker for attached projects' do
        expect(Security::TriageCoverage::ScheduleUpdateWorker).to receive(:perform_async)
          .with(contain_exactly(project1.id, project2.id))

        execute_service
      end
    end

    context 'when a project has reached the profile limit' do
      let(:projects) { [project1, project_at_limit] }

      before do
        stub_const('Security::ScanProfileProject::MAX_PROFILES_PER_PROJECT', 1)
      end

      it 'only attaches to the project under the limit' do
        expect { execute_service }.to change { Security::ScanProfileProject.count }.by(1)
        expect(Security::ScanProfileProject.where(project: project1, scan_profile: profile)).to exist
        expect(Security::ScanProfileProject.where(project: project_at_limit, scan_profile: profile)).not_to exist
      end

      it 'returns an error for the project at limit' do
        result = execute_service
        expect(result[:errors]).to include(
          match(/Project '#{project_at_limit.name}'.*#{project_at_limit.full_path}.*maximum limit/)
        )
      end

      it 'schedules the analyzer status update worker only for attached projects' do
        expect(Security::AnalyzersStatus::ScheduleSettingChangedUpdateWorker).to receive(:perform_async)
          .with([project1.id], profile.scan_type)

        execute_service
      end
    end

    context "when a project's only attachment is to a soft-deleted profile" do
      let(:projects) { [project_at_limit] }

      before do
        stub_const('Security::ScanProfileProject::MAX_PROFILES_PER_PROJECT', 1)
        ::Security::ScanProfile.find(other_profile.id).destroy!
      end

      it 'does not count the soft-deleted attachment toward the limit' do
        expect { execute_service }.to change { Security::ScanProfileProject.count }.by(1)
        expect(Security::ScanProfileProject.where(project: project_at_limit, scan_profile: profile)).to exist
      end

      it_behaves_like 'returns empty errors'
    end

    context 'when profile is already attached to a project' do
      let(:projects) { [project1] }

      before do
        create(:security_scan_profile_project, scan_profile: profile, project: project1)
      end

      it 'does not create duplicate associations' do
        expect { execute_service }.not_to change { Security::ScanProfileProject.count }
      end

      it_behaves_like 'does not schedule the analyzer status update worker'
      it_behaves_like 'returns empty errors'
    end

    context 'when a project is at the limit and has the specific profile attached already' do
      let(:projects) { [project_at_limit] }

      before do
        stub_const('Security::ScanProfileProject::MAX_PROFILES_PER_PROJECT', 1)
        create(:security_scan_profile_project, project: project_at_limit, scan_profile: profile)
      end

      it 'does not create a duplicate' do
        expect { execute_service }.not_to change { Security::ScanProfileProject.count }
      end

      it_behaves_like 'does not schedule the analyzer status update worker'
      it_behaves_like 'returns empty errors'
    end

    context 'when more than MAX_PROJECTS are provided' do
      let(:projects) { [project1, project2, project_at_limit] }

      before do
        stub_const("#{described_class}::MAX_PROJECTS", 2)
      end

      it 'returns an error' do
        result = execute_service
        expect(result[:errors]).to include('Cannot attach profile to more than 2 items at once.')
      end

      it_behaves_like 'does not schedule the analyzer status update worker'
    end

    context 'when an unexpected error occurs during insertion' do
      let(:projects) { [project1] }

      before do
        allow(Security::ScanProfileProject).to receive(:connection).and_raise(StandardError, 'DB connection failed')
      end

      it 'raises the error in development/test environment' do
        expect { execute_service }.to raise_error(StandardError, 'DB connection failed')
      end

      context 'when not in development environment' do
        before do
          allow(Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception) do |e|
            Gitlab::ErrorTracking.track_exception(e)
          end
        end

        it 'returns an error result without raising' do
          result = execute_service

          expect(result[:errors]).to include('An error has occurred during profile attachment')
        end

        it 'tracks the exception' do
          expect(Gitlab::ErrorTracking).to receive(:track_exception)
            .with(an_instance_of(StandardError))

          execute_service
        end
      end
    end

    describe 'mode', :request_store, :clean_gitlab_redis_queues do
      subject(:execute_service) do
        described_class.execute(
          profile: profile, current_user: user, projects: projects, mode: mode
        )
      end

      let_it_be_with_reload(:old_status) do
        create(:scan_profile_project_status, project: project1, scan_profile: old_profile,
          status: :success, consecutive_success_count: 3)
      end

      let_it_be_with_reload(:other_type_status) do
        create(:scan_profile_project_status, project: project1, scan_profile: other_type_profile,
          status: :success, consecutive_success_count: 5)
      end

      let_it_be_with_reload(:unlinked_old_status) do
        create(:scan_profile_project_status, project: project2, scan_profile: old_profile,
          status: :success, consecutive_success_count: 2)
      end

      let_it_be_with_reload(:other_profile_status) do
        create(:scan_profile_project_status, project: project2, scan_profile: other_profile,
          status: :success, consecutive_success_count: 4)
      end

      let(:projects) { [project1, project2] }
      let(:mode) { :set }

      before_all do
        create(:security_scan_profile_project, project: project1, scan_profile: old_profile)
        create(:security_scan_profile_project, project: project1, scan_profile: other_type_profile)
        create(:security_scan_profile_project, project: project2, scan_profile: other_profile)
      end

      def linked_profiles(project)
        Security::ScanProfileProject.where(project: project).map(&:scan_profile)
      end

      def audit_events
        AuditEventReader.where(entity_type: 'Project', entity_id: [project1.id, project2.id])
      end

      context 'when replacing' do
        let(:untouched_statuses) { [other_type_status, unlinked_old_status, other_profile_status] }
        let(:replaced_event) do
          audit_events.find { |event| event.details[:event_name] == 'security_scan_profile_replaced_on_project' }
        end

        let(:attached_event) do
          audit_events.find { |event| event.details[:event_name] == 'security_scan_profile_attached_to_project' }
        end

        let!(:untouched_attributes) { untouched_statuses.map(&:attributes) }

        before do
          execute_service
        end

        it 'replaces the same-type link and keeps the other types linked' do
          expect(linked_profiles(project1)).to contain_exactly(profile, other_type_profile)
          expect(linked_profiles(project2)).to contain_exactly(profile, other_profile)
        end

        it 'resets only the replaced status' do
          expect(old_status.reload).to have_attributes(
            status: 'not_configured', consecutive_success_count: 0, consecutive_failure_count: 0
          )
          expect(untouched_statuses.map { |status| status.reload.attributes }).to eq(untouched_attributes)
        end

        it 'schedules the analyzer status update once for both projects' do
          jobs = Security::AnalyzersStatus::ScheduleSettingChangedUpdateWorker.jobs

          expect(jobs.size).to eq(1)
          expect(jobs.first['args']).to match_array([contain_exactly(project1.id, project2.id), 'secret_detection'])
        end

        it 'audits the replacement on the project that had a same-type link' do
          expect(replaced_event).to have_attributes(author_id: user.id, project_id: project1.id)
          expect(replaced_event.details).to include(
            custom_message: "Replaced security scan profile 'Old Profile' with 'Test Profile' " \
              "on project '#{project1.full_path}'",
            organization_id: project1.organization_id,
            previous_profile_ids: [old_profile.id],
            previous_profile_names: ['Old Profile']
          )
        end

        it 'audits a plain attachment on the project without a same-type link' do
          expect(attached_event).to have_attributes(author_id: user.id, project_id: project2.id)
          expect(audit_events.size).to eq(2)
        end
      end

      context 'when a project has several same-type profiles (A and B replaced by C)' do
        let_it_be(:legacy_profile) do
          create(:security_scan_profile, namespace: root_group, scan_type: :secret_detection, name: 'Legacy Profile')
        end

        let(:untouched_statuses) { [other_type_status, unlinked_old_status, other_profile_status] }
        let!(:untouched_attributes) { untouched_statuses.map(&:attributes) }
        let(:replaced_events) do
          audit_events.select { |event| event.details[:event_name] == 'security_scan_profile_replaced_on_project' }
        end

        let_it_be_with_reload(:legacy_status) do
          create(:scan_profile_project_status, project: project1, scan_profile: legacy_profile, status: :success)
        end

        before_all do
          create(:security_scan_profile_project, project: project1, scan_profile: legacy_profile)
        end

        before do
          execute_service
        end

        it 'keeps only the new profile and the other type linked' do
          expect(linked_profiles(project1)).to contain_exactly(profile, other_type_profile)
        end

        it 'resets both old statuses and leaves unrelated statuses untouched' do
          expect([old_status, legacy_status].map { |status| status.reload.status }).to all(eq('not_configured'))
          expect(untouched_statuses.map { |status| status.reload.attributes }).to eq(untouched_attributes)
        end

        it 'emits one replacement event naming both old profiles' do
          old_names = [old_profile, legacy_profile].sort_by(&:id).map(&:name).to_sentence

          expect(replaced_events.size).to eq(1)
          expect(replaced_events.first.details).to include(
            custom_message: "Replaced security scan profile '#{old_names}' with 'Test Profile' " \
              "on project '#{project1.full_path}'",
            previous_profile_ids: contain_exactly(old_profile.id, legacy_profile.id),
            previous_profile_names: contain_exactly('Old Profile', 'Legacy Profile')
          )
        end
      end

      context 'when the profile is already attached next to a legacy same-type profile' do
        before_all do
          create(:security_scan_profile_project, project: project1, scan_profile: profile)
        end

        it 'converges to the profile and the other types only', :aggregate_failures do
          expect(execute_service[:errors]).to be_empty

          expect(linked_profiles(project1)).to contain_exactly(profile, other_type_profile)
          expect(old_status.reload.status).to eq('not_configured')
        end
      end

      context 'when the insert fails after the old links were removed' do
        before do
          allow(Gitlab::ErrorTracking).to receive(:track_and_raise_for_dev_exception)

          connection = Security::ScanProfileProject.connection
          allow(connection).to receive(:execute).and_wrap_original do |original, sql, *args|
            raise ActiveRecord::StatementInvalid, 'boom' if sql.include?('INSERT INTO security_scan_profiles_projects')

            original.call(sql, *args)
          end
        end

        it 'rolls the removal back and keeps the old status', :aggregate_failures do
          old_status_attributes = old_status.attributes

          expect(execute_service[:errors]).to eq(['An error has occurred during profile attachment'])

          expect(Security::ScanProfileProject.where(project: project1, scan_profile: old_profile)).to exist
          expect(linked_profiles(project1)).to contain_exactly(old_profile, other_type_profile)
          expect(old_status.reload.attributes).to eq(old_status_attributes)
          expect(audit_events).to be_empty
        end
      end

      context 'when appending' do
        let(:mode) { :append }

        it 'keeps existing links and statuses and emits only attach events', :aggregate_failures do
          old_status_attributes = old_status.attributes

          execute_service

          expect(linked_profiles(project1)).to contain_exactly(profile, old_profile, other_type_profile)
          expect(old_status.reload.attributes).to eq(old_status_attributes)

          event_names = audit_events.map { |event| event.details[:event_name] }
          expect(event_names).to match_array(%w[
            security_scan_profile_attached_to_project security_scan_profile_attached_to_project
          ])
          expect(event_names).not_to include(
            'security_scan_profile_replaced_on_project', 'security_scan_profile_detached_from_project'
          )
        end
      end
    end

    describe 'modes that filter the target projects' do
      using RSpec::Parameterized::TableSyntax

      subject(:execute_service) do
        described_class.execute(profile: profile, current_user: user, projects: projects, mode: mode)
      end

      let_it_be(:target) { create(:project, namespace: root_group) }
      let(:projects) { [target] }

      def attached?
        Security::ScanProfileProject.exists?(project: target, scan_profile: profile)
      end

      shared_examples 'attaches without errors' do
        it 'attaches the profile', :aggregate_failures do
          expect(execute_service[:errors]).to be_empty
          expect(attached?).to be(true)
        end
      end

      shared_examples 'skips without errors or changes' do
        it 'does not attach, report errors or schedule updates', :aggregate_failures do
          expect(Security::AnalyzersStatus::ScheduleSettingChangedUpdateWorker).not_to receive(:perform_async)
          result = nil
          expect { result = execute_service }.not_to change { Security::ScanProfileProject.count }
          expect(result[:errors]).to be_empty
        end
      end

      context 'when filling profile gaps' do
        let(:mode) { :fill_profile_gaps }

        context 'without a profile of the type' do
          it_behaves_like 'attaches without errors'
        end

        context 'with a success analyzer status but no profile' do
          before do
            create(:analyzer_project_status, :secret_detection, project: target, status: :success)
          end

          it_behaves_like 'attaches without errors'
        end

        context 'with a profile of a different type' do
          before do
            create(:security_scan_profile_project, project: target, scan_profile: other_type_profile)
          end

          it_behaves_like 'attaches without errors'
        end

        context 'with a soft-deleted profile of the same type' do
          before do
            deleted_profile = create(:security_scan_profile, namespace: root_group, scan_type: :secret_detection,
              name: 'Deleted Profile', deleted_at: Time.current)
            create(:security_scan_profile_project, project: target, scan_profile: deleted_profile)
          end

          it_behaves_like 'attaches without errors'
        end

        context 'with another profile of the same type' do
          before do
            create(:security_scan_profile_project, project: target, scan_profile: old_profile)
          end

          it_behaves_like 'skips without errors or changes'
        end
      end

      context 'when replacing existing profiles' do
        let(:mode) { :replace }
        let_it_be(:free) { create(:project, namespace: root_group) }
        let(:projects) { [target, free] }

        before do
          create(:security_scan_profile_project, project: target, scan_profile: old_profile)
        end

        it 'replaces the old profile only on the project that had one', :aggregate_failures do
          expect(execute_service[:errors]).to be_empty
          expect(Security::ScanProfileProject.where(scan_profile: profile).pluck(:project_id))
            .to contain_exactly(target.id)
          expect(Security::ScanProfileProject.exists?(project: target, scan_profile: old_profile)).to be(false)
          expect(Security::ScanProfileProject.where(project: free).map(&:scan_profile))
            .not_to include(profile, old_profile)
        end

        context 'when no project has a profile of the type' do
          let(:projects) { [free] }

          it_behaves_like 'skips without errors or changes'
        end
      end

      context 'when filling scan gaps' do
        let(:mode) { :fill_scan_gaps }

        context 'with a pipeline-based analyzer status for the type' do
          where(:status) { %i[success failed stale] }

          with_them do
            before do
              create(:analyzer_project_status, analyzer_type: :secret_detection_pipeline_based,
                project: target, status: status)
            end

            it_behaves_like 'skips without errors or changes'
          end
        end

        context 'with only setting-based coverage aggregated into the type' do
          before do
            create(:analyzer_project_status, :secret_detection, project: target, status: :success)
            create(:analyzer_project_status, analyzer_type: :secret_detection_secret_push_protection,
              project: target, status: :success)
          end

          it_behaves_like 'attaches without errors'
        end

        context 'with a not_configured analyzer status' do
          before do
            create(:analyzer_project_status, analyzer_type: :secret_detection_pipeline_based,
              project: target, status: :not_configured)
          end

          it_behaves_like 'attaches without errors'
        end

        context 'with a scan type that has no analyzer status type' do
          let(:profile) { create(:security_scan_profile, namespace: root_group, scan_type: :triage_and_remediation) }

          it 'returns an error and attaches nothing', :aggregate_failures do
            expect(execute_service[:errors]).to contain_exactly(/does not support the FILL_SCAN_GAPS mode/)
            expect(Security::ScanProfileProject.where(scan_profile: profile)).to be_empty
          end
        end

        context 'without an analyzer status' do
          it_behaves_like 'attaches without errors'
        end

        context 'with an analyzer status for another type' do
          before do
            create(:analyzer_project_status, :sast, project: target, status: :success)
          end

          it_behaves_like 'attaches without errors'
        end

        context 'with a profile of the same type but no analyzer status' do
          before do
            create(:security_scan_profile_project, project: target, scan_profile: old_profile)
          end

          it_behaves_like 'skips without errors or changes'
        end

        context 'with a mixed batch' do
          let_it_be(:free) { create(:project, namespace: root_group) }
          let(:projects) { [target, free] }

          before do
            create(:analyzer_project_status, analyzer_type: :secret_detection_pipeline_based,
              project: target, status: :success)
          end

          it 'attaches only the project without coverage', :aggregate_failures do
            expect(execute_service[:errors]).to be_empty
            expect(Security::ScanProfileProject.where(scan_profile: profile).pluck(:project_id))
              .to contain_exactly(free.id)
            expect(Security::AnalyzersStatus::ScheduleSettingChangedUpdateWorker.jobs.pluck('args'))
              .to contain_exactly([[free.id], 'secret_detection'])
          end

          context 'when the skipped project comes first and the attached one is archived' do
            let_it_be(:archived_free) { create(:project, :archived, namespace: root_group) }
            let(:projects) { [target, archived_free] }

            it 'keeps the archived flags aligned with the attached projects', :aggregate_failures do
              expect(execute_service[:errors]).to be_empty
              expect(Security::ScanProfileProject.find_by!(project: archived_free, scan_profile: profile).archived)
                .to be(true)
            end
          end
        end
      end
    end

    describe 'mode at the profile limit' do
      using RSpec::Parameterized::TableSyntax

      before do
        stub_const('Security::ScanProfileProject::MAX_PROFILES_PER_PROJECT', 1)
      end

      subject(:execute_service) do
        described_class.execute(
          profile: profile, current_user: user, projects: [project_at_limit], mode: mode
        )
      end

      context 'when the project is at the limit with a same-type profile' do
        let(:mode) { :set }

        before_all do
          create(:security_scan_profile_project, project: project_at_limit, scan_profile: old_profile)
          Security::ScanProfileProject.where(project: project_at_limit, scan_profile: other_profile).delete_all
        end

        it 'evaluates the limit after removal', :aggregate_failures do
          expect(execute_service[:errors]).to be_empty
          expect(Security::ScanProfileProject.where(project: project_at_limit).map(&:scan_profile))
            .to contain_exactly(profile)
        end
      end

      context 'when the project is at the limit with a different-type profile only' do
        where(:mode) { %i[set append] }

        with_them do
          it 'returns the limit error and creates nothing', :aggregate_failures do
            expect { execute_service }.not_to change { Security::ScanProfileProject.count }

            expect(execute_service[:errors]).to include(
              match(/Project '#{project_at_limit.name}'.*#{project_at_limit.full_path}.*maximum limit/)
            )
            expect(Security::ScanProfileProject.where(project: project_at_limit).map(&:scan_profile))
              .to contain_exactly(other_profile)
          end
        end
      end
    end

    context 'with audit events', :request_store do
      let(:projects) { [project1, project2] }

      it 'creates audit events for attached projects' do
        expect { execute_service }.to change { AuditEventReader.count }.by(2)
      end

      it 'creates audit events with correct attributes' do
        execute_service

        audit_event = AuditEventReader.last
        expect(audit_event.details).to include(
          event_name: 'security_scan_profile_attached_to_project',
          organization_id: project1.organization_id,
          author_name: user.name,
          profile_id: profile.id,
          profile_name: profile.name,
          scan_type: profile.scan_type
        )
        expect(audit_event.details[:project_id]).to be_in([project1.id, project2.id])
        expect(audit_event.details[:project_path]).to be_in([project1.full_path, project2.full_path])
        expect(audit_event.details[:custom_message]).to start_with("Attached security scan profile '#{profile.name}'")
      end

      context 'when no projects are successfully attached' do
        let(:projects) { [project_at_limit] }

        before do
          stub_const('Security::ScanProfileProject::MAX_PROFILES_PER_PROJECT', 1)
        end

        it 'does not create audit events' do
          expect { execute_service }.not_to change { AuditEventReader.count }
        end
      end

      context 'when attached project IDs do not match provided projects' do
        let(:projects) { [project1] }

        before do
          # Simulate a scenario where the insert returns IDs that don't match the provided projects
          allow_next_instance_of(described_class) do |instance|
            allow(instance).to receive(:insert_under_limit).and_return([999_999])
          end
        end

        it 'does not create audit events' do
          expect { execute_service }.not_to change { AuditEventReader.count }
        end
      end
    end
  end
end
