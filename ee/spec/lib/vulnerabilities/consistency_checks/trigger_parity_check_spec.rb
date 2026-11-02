# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Vulnerabilities::ConsistencyChecks::TriggerParityCheck, factory_default: :keep, feature_category: :vulnerability_management do
  let_it_be(:namespace) { create_default(:namespace) }
  let_it_be(:project)   { create_default(:project) }

  subject(:execute) { described_class.execute(project) }

  describe '#execute' do
    context 'when vulnerability_occurrence_id differs from finding_id but points to valid occurrence' do
      let!(:vulnerability) { create(:vulnerability, :with_finding, project: project) }
      let(:finding) { vulnerability.vulnerability_finding }
      let!(:other_finding) { create(:vulnerabilities_finding, project: project) }

      before do
        vulnerability.vulnerability_read.update_column(:vulnerability_occurrence_id, other_finding.id)
      end

      it 'fixes the vulnerability_occurrence_id to match vulnerabilities.finding_id' do
        expect { execute }.to change { vulnerability.vulnerability_read.reload.vulnerability_occurrence_id }
          .from(other_finding.id).to(finding.id)
      end
    end

    context 'when vulnerability_occurrence_id is NULL' do
      let!(:vulnerability) { create(:vulnerability, :with_finding, project: project) }
      let(:finding) { vulnerability.vulnerability_finding }

      before do
        vulnerability.vulnerability_read.update_column(:vulnerability_occurrence_id, nil)
      end

      it 'backfills the vulnerability_occurrence_id' do
        expect { execute }.to change { vulnerability.vulnerability_read.reload.vulnerability_occurrence_id }
          .from(nil).to(finding.id)
      end
    end

    context 'when has_issues flag mismatches actual issue links' do
      let_it_be_with_reload(:vulnerability) { create(:vulnerability, :with_finding, project: project) }
      let(:finding) { vulnerability.vulnerability_finding }

      context 'when has_issues is false but issue links exist with vulnerability_occurrence_id' do
        before do
          create(:vulnerabilities_issue_link, vulnerability: vulnerability,
            vulnerability_occurrence_id: finding.id)
          vulnerability.vulnerability_read.update_column(:has_issues, false)
        end

        it 'sets has_issues to true' do
          expect { execute }.to change { vulnerability.vulnerability_read.reload.has_issues }
            .from(false).to(true)
        end
      end

      context 'when has_issues is false and issue link has no vulnerability_occurrence_id' do
        before do
          create(:vulnerabilities_issue_link, vulnerability: vulnerability,
            vulnerability_occurrence_id: nil)
          vulnerability.vulnerability_read.update_column(:has_issues, false)
        end

        it 'sets has_issues to true, matching the vulnerability_id triggers' do
          expect { execute }.to change { vulnerability.vulnerability_read.reload.has_issues }
            .from(false).to(true)
        end
      end

      context 'when has_issues is true but no issue links exist' do
        before do
          vulnerability.vulnerability_read.update_column(:has_issues, true)
        end

        it 'sets has_issues to false' do
          expect { execute }.to change { vulnerability.vulnerability_read.reload.has_issues }
            .from(true).to(false)
        end
      end

      context 'when the only link is to an external issue tracker' do
        before do
          create(:vulnerabilities_external_issue_link, vulnerability: vulnerability, author: vulnerability.author)
        end

        it 'keeps has_issues true' do
          vulnerability.vulnerability_read.update_column(:has_issues, true)

          expect { execute }.not_to change { vulnerability.vulnerability_read.reload.has_issues }.from(true)
        end

        it 'sets has_issues to true when it is false' do
          vulnerability.vulnerability_read.update_column(:has_issues, false)

          expect { execute }.to change { vulnerability.vulnerability_read.reload.has_issues }
            .from(false).to(true)
        end
      end
    end

    context 'when has_merge_request flag mismatches actual MR links' do
      let_it_be_with_reload(:vulnerability) { create(:vulnerability, :with_finding, project: project) }
      let(:finding) { vulnerability.vulnerability_finding }

      context 'when has_merge_request is false but MR links exist with vulnerability_occurrence_id' do
        before do
          create(:vulnerabilities_merge_request_link, vulnerability: vulnerability,
            vulnerability_occurrence_id: finding.id)
          vulnerability.vulnerability_read.update_column(:has_merge_request, false)
        end

        it 'sets has_merge_request to true' do
          expect { execute }.to change { vulnerability.vulnerability_read.reload.has_merge_request }
            .from(false).to(true)
        end
      end

      context 'when has_merge_request is false and MR link has no vulnerability_occurrence_id' do
        before do
          create(:vulnerabilities_merge_request_link, vulnerability: vulnerability,
            vulnerability_occurrence_id: nil)
          vulnerability.vulnerability_read.update_column(:has_merge_request, false)
        end

        it 'sets has_merge_request to true, matching the vulnerability_id triggers' do
          expect { execute }.to change { vulnerability.vulnerability_read.reload.has_merge_request }
            .from(false).to(true)
        end
      end

      context 'when has_merge_request is true but no MR links exist' do
        before do
          vulnerability.vulnerability_read.update_column(:has_merge_request, true)
        end

        it 'sets has_merge_request to false' do
          expect { execute }.to change { vulnerability.vulnerability_read.reload.has_merge_request }
            .from(true).to(false)
        end
      end
    end

    context 'when vulnerability_read is missing for a vulnerability' do
      let_it_be_with_reload(:vulnerability) do
        create(:vulnerability, :with_finding, project: project, present_on_default_branch: true)
      end

      let(:finding) { vulnerability.findings.first }

      before do
        Vulnerabilities::Read.where(vulnerability_id: vulnerability.id).delete_all
      end

      it 'creates the missing vulnerability_read' do
        expect { execute }.to change { Vulnerabilities::Read.exists?(vulnerability_id: vulnerability.id) }
          .from(false).to(true)
      end

      it 'creates the read with correct attributes from trigger logic' do
        execute

        read = Vulnerabilities::Read.find_by(vulnerability_id: vulnerability.id)
        expect(read).to have_attributes(
          project_id: vulnerability.project_id,
          scanner_id: finding.scanner_id,
          report_type: vulnerability.report_type,
          severity: vulnerability.severity,
          state: vulnerability.state,
          resolved_on_default_branch: vulnerability.resolved_on_default_branch,
          uuid: finding.uuid,
          vulnerability_occurrence_id: finding.id,
          has_issues: false,
          has_merge_request: false
        )
      end

      context 'when issue and MR links exist' do
        before do
          create(:vulnerabilities_issue_link, vulnerability: vulnerability)
          create(:vulnerabilities_merge_request_link, vulnerability: vulnerability)
        end

        it 'sets has_issues and has_merge_request' do
          execute

          read = Vulnerabilities::Read.find_by(vulnerability_id: vulnerability.id)
          expect(read).to have_attributes(has_issues: true, has_merge_request: true)
        end
      end

      context 'when only an external issue link exists' do
        before do
          create(:vulnerabilities_external_issue_link, vulnerability: vulnerability, author: vulnerability.author)
        end

        it 'sets has_issues' do
          execute

          expect(Vulnerabilities::Read.find_by(vulnerability_id: vulnerability.id).has_issues).to be(true)
        end
      end
    end

    context 'when creating missing vulnerability reads' do
      def create_vulnerability_without_read
        vulnerability = create(:vulnerability, :with_finding, project: project, present_on_default_branch: true)
        Vulnerabilities::Read.where(vulnerability_id: vulnerability.id).delete_all
        vulnerability
      end

      it 'does not have N+1 queries for loading associations' do
        create_vulnerability_without_read

        control = ActiveRecord::QueryRecorder.new { described_class.execute(project) }

        2.times do
          vulnerability = create_vulnerability_without_read
          create(:vulnerabilities_external_issue_link, vulnerability: vulnerability, author: vulnerability.author)
        end

        # Match only the ActiveRecord association preloads (quoted table names) triggered
        # by `includes(:issue_links, :external_issue_links, :merge_request_links)` in
        # create_missing_vulnerability_reads. The bounded fix_has_issues/fix_has_merge_request UPDATEs
        # reference the same tables via unquoted aliased subqueries and are constant per keyset window,
        # so they are excluded here.
        expect { described_class.execute(project) }
          .not_to exceed_query_limit(control)
          .for_query(
            /FROM "(vulnerability_issue_links|vulnerability_external_issue_links|vulnerability_merge_request_links)"/
          )
      end
    end

    context 'when vulnerability is not present_on_default_branch' do
      let!(:vulnerability) do
        create(:vulnerability, :with_finding, project: project, present_on_default_branch: false)
      end

      before do
        Vulnerabilities::Read.where(vulnerability_id: vulnerability.id).delete_all
      end

      it 'does not create a vulnerability_read' do
        expect { execute }.not_to change { Vulnerabilities::Read.count }
      end
    end

    context 'when vulnerability has no associated finding' do
      let!(:vulnerability) do
        create(:vulnerability, :with_finding, project: project, present_on_default_branch: true)
      end

      before do
        Vulnerabilities::Read.where(vulnerability_id: vulnerability.id).delete_all
        Vulnerabilities::Finding.where(vulnerability_id: vulnerability.id).delete_all
      end

      it 'skips creating a vulnerability_read' do
        expect { execute }.not_to change { Vulnerabilities::Read.count }
      end
    end

    context 'when finding location determines vulnerability_read fields' do
      let_it_be_with_reload(:vulnerability) do
        create(:vulnerability, :with_finding, project: project, present_on_default_branch: true)
      end

      let(:finding) { vulnerability.findings.first }

      before do
        Vulnerabilities::Read.where(vulnerability_id: vulnerability.id).delete_all
      end

      context 'when finding has empty location' do
        before do
          finding.update_column(:location, {})
        end

        it 'creates vulnerability_read with nil location fields' do
          execute

          read = Vulnerabilities::Read.find_by(vulnerability_id: vulnerability.id)
          expect(read).to have_attributes(
            location_image: nil,
            cluster_agent_id: nil,
            casted_cluster_agent_id: nil
          )
        end
      end

      context 'when finding location has no image key' do
        before do
          finding.update_column(:location, { 'file' => 'test.rb' })
        end

        it 'creates vulnerability_read with nil location_image' do
          execute

          read = Vulnerabilities::Read.find_by(vulnerability_id: vulnerability.id)
          expect(read.location_image).to be_nil
        end
      end

      context 'when finding location has no kubernetes_resource' do
        before do
          finding.update_column(:location, { 'image' => 'alpine:3.7' })
        end

        it 'creates vulnerability_read with nil cluster_agent_id fields' do
          execute

          read = Vulnerabilities::Read.find_by(vulnerability_id: vulnerability.id)
          expect(read).to have_attributes(
            location_image: 'alpine:3.7',
            cluster_agent_id: nil,
            casted_cluster_agent_id: nil
          )
        end
      end

      context 'when finding location has kubernetes_resource without agent_id' do
        before do
          finding.update_column(:location,
            { 'image' => 'alpine:3.7', 'kubernetes_resource' => { 'cluster_id' => '1' } })
        end

        it 'creates vulnerability_read with nil agent_id but populated location_image' do
          execute

          read = Vulnerabilities::Read.find_by(vulnerability_id: vulnerability.id)
          expect(read).to have_attributes(
            location_image: 'alpine:3.7',
            cluster_agent_id: nil,
            casted_cluster_agent_id: nil
          )
        end
      end

      context 'when finding location has kubernetes_resource with agent_id' do
        before do
          finding.update_column(:location, {
            'image' => 'nginx:latest',
            'kubernetes_resource' => { 'agent_id' => '42', 'cluster_id' => '1' }
          })
        end

        it 'creates vulnerability_read with populated cluster_agent_id fields' do
          execute

          read = Vulnerabilities::Read.find_by(vulnerability_id: vulnerability.id)
          expect(read).to have_attributes(
            location_image: 'nginx:latest',
            cluster_agent_id: '42',
            casted_cluster_agent_id: 42
          )
        end
      end

      context 'when the location column is blank but raw_metadata carries the location' do
        before do
          finding.update_columns(
            location: {},
            raw_metadata: { location: { image: 'from-metadata:1.0' } }.to_json
          )
        end

        it 'derives location_image from Finding#location metadata fallback (AR-hydrated path)' do
          execute

          read = Vulnerabilities::Read.find_by(vulnerability_id: vulnerability.id)
          expect(read.location_image).to eq('from-metadata:1.0')
        end
      end
    end

    context 'when all data is consistent' do
      let!(:vulnerability) { create(:vulnerability, :with_finding, project: project) }
      let(:finding) { vulnerability.vulnerability_finding }

      before do
        vulnerability.vulnerability_read.update_columns(
          scanner_id: finding.scanner_id,
          uuid: finding.uuid,
          vulnerability_occurrence_id: vulnerability.finding_id
        )
      end

      it 'does not modify the vulnerability_read' do
        expect { execute }.not_to change { vulnerability.vulnerability_read.reload.attributes }
      end
    end

    context 'when scanner_id mismatches' do
      let!(:vulnerability) { create(:vulnerability, :with_finding, project: project) }
      let!(:other_scanner) { create(:vulnerabilities_scanner, project: project) }
      let(:finding) { vulnerability.vulnerability_finding }

      before do
        vulnerability.vulnerability_read.update_column(:scanner_id, other_scanner.id)
      end

      it 'fixes the scanner_id to match the finding linked via vulnerability_occurrence_id' do
        expect { execute }.to change { vulnerability.vulnerability_read.reload.scanner_id }
          .from(other_scanner.id).to(finding.scanner_id)
      end
    end

    context 'when uuid mismatches' do
      let!(:vulnerability) { create(:vulnerability, :with_finding, project: project) }
      let(:finding) { vulnerability.vulnerability_finding }
      let(:wrong_uuid) { SecureRandom.uuid }

      before do
        vulnerability.vulnerability_read.update_column(:uuid, wrong_uuid)
      end

      it 'fixes the uuid to match the finding linked via vulnerability_occurrence_id' do
        expect { execute }.to change { vulnerability.vulnerability_read.reload.uuid }
          .from(wrong_uuid).to(finding.uuid)
      end
    end

    context 'when a fix method raises a StandardError' do
      let(:error) { StandardError.new('something went wrong') }

      before do
        allow_next_instance_of(described_class) do |instance|
          allow(instance).to receive(:fix_vulnerability_occurrence_id_mismatches).and_raise(error)
        end
      end

      it 'logs the error and re-raises' do
        expect(Gitlab::AppLogger).to receive(:info).with(
          hash_including(message: 'Failed to fix vulnerability_reads', error_message: error.message)
        )

        expect { execute }.to raise_error(StandardError, 'something went wrong')
      end

      it 'still runs the independent fix steps before re-raising (failure isolation)' do
        expect_next_instance_of(described_class) do |instance|
          allow(instance).to receive(:fix_vulnerability_occurrence_id_mismatches).and_raise(error)
          expect(instance).to receive(:fix_has_issues_mismatches).and_call_original
          expect(instance).to receive(:fix_has_merge_request_mismatches).and_call_original
          expect(instance).to receive(:create_missing_vulnerability_reads).and_call_original
        end

        expect { execute }.to raise_error(StandardError, 'something went wrong')
      end

      it 'skips the steps that depend on vulnerability_occurrence_id' do
        expect_next_instance_of(described_class) do |instance|
          allow(instance).to receive(:fix_vulnerability_occurrence_id_mismatches).and_raise(error)
          expect(instance).not_to receive(:fix_scanner_id_mismatches)
          expect(instance).not_to receive(:fix_uuid_mismatches)
        end

        expect { execute }.to raise_error(StandardError, 'something went wrong')
      end

      context 'when the read points at a stale occurrence' do
        let!(:vulnerability) { create(:vulnerability, :with_finding, project: project) }
        let(:finding) { vulnerability.vulnerability_finding }
        let!(:stale_finding) { create(:vulnerabilities_finding, project: project) }

        before do
          vulnerability.vulnerability_read.update_columns(
            vulnerability_occurrence_id: stale_finding.id,
            uuid: finding.uuid,
            scanner_id: finding.scanner_id
          )
        end

        it 'does not overwrite the correct uuid and scanner_id from the stale finding' do
          read = vulnerability.vulnerability_read

          expect { execute }.to raise_error(StandardError, 'something went wrong')
            .and not_change { read.reload.uuid }.from(finding.uuid)
            .and not_change { read.reload.scanner_id }.from(finding.scanner_id)
        end
      end

      context 'when an independent step raises' do
        it 'still runs the steps that depend on vulnerability_occurrence_id' do
          expect_next_instance_of(described_class) do |instance|
            expect(instance).to receive(:fix_vulnerability_occurrence_id_mismatches).and_call_original
            allow(instance).to receive(:fix_has_issues_mismatches).and_raise(error)
            expect(instance).to receive(:fix_scanner_id_mismatches).and_call_original
            expect(instance).to receive(:fix_uuid_mismatches).and_call_original
          end

          expect { execute }.to raise_error(StandardError, 'something went wrong')
        end
      end

      context 'when multiple fix methods raise' do
        let(:second_error) { StandardError.new('second failure') }

        it 'runs every step and raises the first error' do
          expect_next_instance_of(described_class) do |instance|
            allow(instance).to receive(:fix_vulnerability_occurrence_id_mismatches).and_raise(error)
            allow(instance).to receive(:fix_uuid_mismatches).and_raise(second_error)
            expect(instance).to receive(:create_missing_vulnerability_reads).and_call_original
          end

          expect { execute }.to raise_error(StandardError, 'something went wrong')
        end
      end
    end

    context 'when enumerating the keyset windows raises' do
      let(:error) { ActiveRecord::QueryCanceled.new('canceling statement due to statement timeout') }

      it 'reports the failure exactly once without running any step, then re-raises' do
        expect_next_instance_of(described_class) do |instance|
          expect(instance).to receive(:reads_windows).once.and_raise(error)
          expect(instance).not_to receive(:fix_vulnerability_occurrence_id_mismatches)
          expect(instance).not_to receive(:fix_scanner_id_mismatches)
          expect(instance).not_to receive(:fix_uuid_mismatches)
          expect(instance).not_to receive(:fix_has_issues_mismatches)
          expect(instance).not_to receive(:fix_has_merge_request_mismatches)
          expect(instance).not_to receive(:create_missing_vulnerability_reads)
        end

        allow(Gitlab::AppLogger).to receive(:info)
        expect(Gitlab::ErrorTracking).to receive(:track_exception)
          .with(error, project_id: project.id, step: :reads_windows).once
        expect(Gitlab::AppLogger).to receive(:info).with(
          hash_including(
            message: 'Failed to fix vulnerability_reads', error_message: error.message, step: :reads_windows
          )
        ).once

        expect { execute }.to raise_error(error)
      end
    end

    context 'when the project has many vulnerability_reads spanning multiple keyset windows' do
      before do
        stub_const("#{described_class}::BATCH_SIZE", 1)
      end

      let!(:vulnerabilities) do
        create_list(:vulnerability, 3, :with_finding, project: project)
      end

      it 'fixes mismatches across all windows' do
        vulnerabilities.each do |vulnerability|
          vulnerability.vulnerability_read.update_column(:vulnerability_occurrence_id, nil)
        end

        execute

        vulnerabilities.each do |vulnerability|
          expect(vulnerability.vulnerability_read.reload.vulnerability_occurrence_id)
            .to eq(vulnerability.finding_id)
        end
      end

      it 'skips a window whose reads are deleted after its bounds are computed' do
        vulnerabilities.each do |vulnerability|
          vulnerability.vulnerability_read.update_column(:vulnerability_occurrence_id, nil)
        end
        deleted_read = vulnerabilities.second.vulnerability_read

        allow(Vulnerabilities::Read).to receive(:by_projects).and_wrap_original do |by_projects, *args|
          relation = by_projects.call(*args)
          allow(relation).to receive(:each_batch).and_wrap_original do |each_batch, **options, &block|
            each_batch.call(**options) do |batch, index|
              deleted_read.delete if batch.pluck(:vulnerability_id) == [deleted_read.vulnerability_id]
              block.call(batch, index)
            end
          end
          relation
        end

        execute

        [vulnerabilities.first, vulnerabilities.third].each do |vulnerability|
          expect(vulnerability.vulnerability_read.reload.vulnerability_occurrence_id)
            .to eq(vulnerability.finding_id)
        end
      end

      it 'logs the correct total count across windows' do
        vulnerabilities.each do |vulnerability|
          vulnerability.vulnerability_read.update_column(:vulnerability_occurrence_id, nil)
        end

        expect(Gitlab::AppLogger).to receive(:info).with(
          hash_including(message: 'Fixed vulnerability_occurrence_id mismatches', count: 3)
        )
        allow(Gitlab::AppLogger).to receive(:info)

        execute
      end

      it 'only counts rows actually changed for has_issues (mismatch pushed into UPDATE WHERE)' do
        vulnerability = vulnerabilities.first
        finding = vulnerability.vulnerability_finding
        create(:vulnerabilities_issue_link, vulnerability: vulnerability, vulnerability_occurrence_id: finding.id)
        vulnerability.vulnerability_read.update_column(:has_issues, false)

        expect(Gitlab::AppLogger).to receive(:info).with(
          hash_including(message: 'Fixed has_issues mismatches', count: 1)
        )
        allow(Gitlab::AppLogger).to receive(:info)

        execute
      end

      it 'counts each read once for has_issues even when multiple issue links share an occurrence' do
        vulnerability = vulnerabilities.first
        finding = vulnerability.vulnerability_finding
        create(:vulnerabilities_issue_link, vulnerability: vulnerability, vulnerability_occurrence_id: finding.id)
        create(:vulnerabilities_issue_link, vulnerability: vulnerability, vulnerability_occurrence_id: finding.id)
        vulnerability.vulnerability_read.update_column(:has_issues, false)

        expect(Gitlab::AppLogger).to receive(:info).with(
          hash_including(message: 'Fixed has_issues mismatches', count: 1)
        )
        allow(Gitlab::AppLogger).to receive(:info)

        expect { execute }.to change { vulnerability.vulnerability_read.reload.has_issues }.from(false).to(true)
      end

      it 'only counts rows actually changed for has_merge_request (mismatch pushed into UPDATE WHERE)' do
        vulnerability = vulnerabilities.first
        finding = vulnerability.vulnerability_finding
        create(:vulnerabilities_merge_request_link, vulnerability: vulnerability,
          vulnerability_occurrence_id: finding.id)
        vulnerability.vulnerability_read.update_column(:has_merge_request, false)

        expect(Gitlab::AppLogger).to receive(:info).with(
          hash_including(message: 'Fixed has_merge_request mismatches', count: 1)
        )
        allow(Gitlab::AppLogger).to receive(:info)

        execute
      end

      it 'does not count reads whose has_issues already matches (no double-eval false positive)' do
        vulnerability = vulnerabilities.first
        finding = vulnerability.vulnerability_finding
        create(:vulnerabilities_issue_link, vulnerability: vulnerability, vulnerability_occurrence_id: finding.id)
        vulnerability.vulnerability_read.update_column(:has_issues, true)

        expect(Gitlab::AppLogger).not_to receive(:info).with(
          hash_including(message: 'Fixed has_issues mismatches')
        )
        allow(Gitlab::AppLogger).to receive(:info)

        expect { execute }.not_to change { vulnerability.vulnerability_read.reload.has_issues }
      end

      it 'fixes has_issues across every window via the vulnerability_id probe' do
        vulnerabilities.each do |vulnerability|
          finding = vulnerability.vulnerability_finding
          create(:vulnerabilities_issue_link, vulnerability: vulnerability, vulnerability_occurrence_id: finding.id)
          vulnerability.vulnerability_read.update_column(:has_issues, false)
        end

        execute

        vulnerabilities.each do |vulnerability|
          expect(vulnerability.vulnerability_read.reload.has_issues).to be(true)
        end
      end

      it 'fixes has_merge_request across every window' do
        vulnerabilities.each do |vulnerability|
          merge_request = create(:merge_request, source_project: project, source_branch: "mr-#{vulnerability.id}")
          create(:vulnerabilities_merge_request_link, vulnerability: vulnerability, merge_request: merge_request)
          vulnerability.vulnerability_read.update_column(:has_merge_request, false)
        end

        execute

        vulnerabilities.each do |vulnerability|
          expect(vulnerability.vulnerability_read.reload.has_merge_request).to be(true)
        end
      end

      it 'fixes scanner_id across every window' do
        other_scanner = create(:vulnerabilities_scanner, project: project)
        vulnerabilities.each do |vulnerability|
          vulnerability.vulnerability_read.update_column(:scanner_id, other_scanner.id)
        end

        execute

        vulnerabilities.each do |vulnerability|
          expect(vulnerability.vulnerability_read.reload.scanner_id)
            .to eq(vulnerability.vulnerability_finding.scanner_id)
        end
      end

      it 'fixes uuid across every window' do
        vulnerabilities.each do |vulnerability|
          vulnerability.vulnerability_read.update_column(:uuid, SecureRandom.uuid)
        end

        execute

        vulnerabilities.each do |vulnerability|
          expect(vulnerability.vulnerability_read.reload.uuid)
            .to eq(vulnerability.vulnerability_finding.uuid)
        end
      end

      it 'creates missing reads across every window' do
        vulnerabilities.each do |vulnerability|
          Vulnerabilities::Read.where(vulnerability_id: vulnerability.id).delete_all
        end

        execute

        vulnerabilities.each do |vulnerability|
          expect(Vulnerabilities::Read.exists?(vulnerability_id: vulnerability.id)).to be(true)
        end
      end
    end

    context 'when a second project has interleaved vulnerability_ids' do
      let_it_be(:other_project) { create(:project, namespace: namespace) }

      let!(:vulnerability) do
        create(:vulnerability, :with_finding, project: project)
      end

      let!(:other_vulnerability) do
        create(:vulnerability, :with_finding, project: other_project)
      end

      let!(:later_vulnerability) do
        create(:vulnerability, :with_finding, project: project)
      end

      it 'interleaves the other project inside the checked project keyset window' do
        expect(other_vulnerability.id).to be > vulnerability.id
        expect(other_vulnerability.id).to be < later_vulnerability.id
      end

      it 'only repairs reads belonging to the checked project' do
        create(:vulnerabilities_issue_link, vulnerability: vulnerability)
        vulnerability.vulnerability_read.update_column(:has_issues, false)

        create(:vulnerabilities_issue_link, vulnerability: other_vulnerability)
        other_vulnerability.vulnerability_read.update_column(:has_issues, false)

        execute

        expect(vulnerability.vulnerability_read.reload.has_issues).to be(true)
        expect(other_vulnerability.vulnerability_read.reload.has_issues).to be(false)
      end
    end
  end
end
