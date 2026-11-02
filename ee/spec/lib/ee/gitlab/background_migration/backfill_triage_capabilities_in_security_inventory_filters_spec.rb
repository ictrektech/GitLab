# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundMigration::BackfillTriageCapabilitiesInSecurityInventoryFilters,
  feature_category: :security_asset_inventories do
  let(:security_inventory_filters_table) { table(:security_inventory_filters, database: :sec) }
  let(:migration_instance) do
    described_class.new(
      start_id: security_scan_profiles_projects_table.minimum(:id),
      end_id: security_scan_profiles_projects_table.maximum(:id),
      batch_table: :security_scan_profiles_projects,
      batch_column: :id,
      sub_batch_size: 100,
      pause_ms: 0,
      connection: SecApplicationRecord.connection
    )
  end

  let(:security_scan_profiles_table) { table(:security_scan_profiles, database: :sec) }
  let(:security_scan_profiles_projects_table) { table(:security_scan_profiles_projects, database: :sec) }
  let(:security_scan_profile_triggers_table) { table(:security_scan_profile_triggers, database: :sec) }
  let(:security_scan_profile_configurations_table) { table(:security_scan_profile_configurations, database: :sec) }
  let(:organizations_table) { table(:organizations) }
  let(:namespaces_table) { table(:namespaces) }
  let(:projects_table) { table(:projects) }

  let(:organization) { organizations_table.create!(name: 'organization', path: 'organization') }
  let(:group) do
    namespaces_table.create!(
      name: 'group', path: 'group', type: 'Group',
      organization_id: organization.id, traversal_ids: []
    ).tap { |g| g.update!(traversal_ids: [g.id]) }
  end

  let(:sast_scan_type) { 0 }
  let(:dependency_scanning_post_processing_type) { 20 }
  let(:triage_and_remediation_type) { 30 }

  let(:default_branch_pipeline_trigger) { 0 }
  let(:sbom_ingested_trigger) { 3 }
  let(:sast_false_positive_trigger) { 10 }
  let(:sast_vulnerability_resolution_trigger) { 11 }

  # an arbitrary nonzero seed, distinct from any trigger under test, to prove overwrite
  let(:stale_bits) { 8 }

  def mask_for(trigger_type)
    described_class::TRIGGER_MASKS.fetch(trigger_type)
  end

  def create_project(name:)
    project_namespace = namespaces_table.create!(
      name: "#{name}-ns", path: "#{name}-ns", type: 'Project',
      parent_id: group.id, organization_id: organization.id,
      traversal_ids: group.traversal_ids + [0]
    )
    project_namespace.update!(traversal_ids: group.traversal_ids + [project_namespace.id])

    projects_table.create!(
      name: name, path: name, namespace_id: group.id,
      project_namespace_id: project_namespace.id,
      organization_id: organization.id
    )
  end

  def create_inventory_filter(project:, **overrides)
    security_inventory_filters_table.create!(
      project_id: project.id,
      project_name: project.name,
      traversal_ids: [group.id],
      archived: false,
      **overrides
    )
  end

  def create_profile(name:, scan_type:, deleted_at: nil)
    security_scan_profiles_table.create!(
      namespace_id: group.id, name: name, scan_type: scan_type, deleted_at: deleted_at
    )
  end

  def attach_profile(project:, profile:)
    security_scan_profiles_projects_table.create!(project_id: project.id, security_scan_profile_id: profile.id)
  end

  def add_trigger(profile:, trigger_type:, run_mode: nil)
    configuration_id =
      if run_mode
        security_scan_profile_configurations_table.create!(
          security_scan_profile_id: profile.id, namespace_id: group.id, configuration: { run_mode: run_mode }
        ).id
      end

    security_scan_profile_triggers_table.create!(
      security_scan_profile_id: profile.id, namespace_id: group.id, trigger_type: trigger_type,
      security_scan_profile_configuration_id: configuration_id
    )
  end

  describe '#perform' do
    context 'when a project has a triage_and_remediation profile with a defaulted trigger' do
      let!(:project) { create_project(name: 'defaulted') }
      let!(:profile) { create_profile(name: 'profile', scan_type: triage_and_remediation_type) }
      let!(:sif) { create_inventory_filter(project: project) }

      before do
        attach_profile(project: project, profile: profile)
        add_trigger(profile: profile, trigger_type: sast_false_positive_trigger)
      end

      it 'sets both bits, since no override means the default run_mode (auto)' do
        migration_instance.perform

        expect(sif.reload).to have_attributes(
          triage_capabilities_on: mask_for(sast_false_positive_trigger),
          triage_capabilities_auto: mask_for(sast_false_positive_trigger)
        )
      end
    end

    context 'when the trigger has an explicit manual override' do
      let!(:project) { create_project(name: 'manual') }
      let!(:profile) { create_profile(name: 'profile', scan_type: triage_and_remediation_type) }
      let!(:sif) { create_inventory_filter(project: project) }

      before do
        attach_profile(project: project, profile: profile)
        add_trigger(profile: profile, trigger_type: sast_false_positive_trigger, run_mode: 'manual')
      end

      it 'sets the on bit but not the auto bit' do
        migration_instance.perform

        expect(sif.reload).to have_attributes(triage_capabilities_on: mask_for(sast_false_positive_trigger),
          triage_capabilities_auto: 0)
      end
    end

    context 'when sbom_ingested is attached via a dependency_scanning_post_processing profile' do
      let!(:project) { create_project(name: 'dspp') }
      let!(:profile) { create_profile(name: 'profile', scan_type: dependency_scanning_post_processing_type) }
      let!(:sif) { create_inventory_filter(project: project) }

      before do
        attach_profile(project: project, profile: profile)
        add_trigger(profile: profile, trigger_type: sbom_ingested_trigger)
      end

      it 'sets both bits, since sbom_ingested has no independent run_mode' do
        migration_instance.perform

        expect(sif.reload).to have_attributes(
          triage_capabilities_on: mask_for(sbom_ingested_trigger),
          triage_capabilities_auto: mask_for(sbom_ingested_trigger)
        )
      end
    end

    context 'when two profiles attach the same trigger type' do
      let!(:project) { create_project(name: 'lowest-id') }
      let!(:lower_profile) { create_profile(name: 'lower', scan_type: triage_and_remediation_type) }
      let!(:higher_profile) { create_profile(name: 'higher', scan_type: triage_and_remediation_type) }
      let!(:sif) { create_inventory_filter(project: project) }

      before do
        attach_profile(project: project, profile: lower_profile)
        attach_profile(project: project, profile: higher_profile)
        add_trigger(profile: lower_profile, trigger_type: sast_false_positive_trigger, run_mode: 'manual')
        add_trigger(profile: higher_profile, trigger_type: sast_false_positive_trigger, run_mode: 'auto')
      end

      it "uses the lower-id profile's run_mode" do
        migration_instance.perform

        expect(sif.reload).to have_attributes(triage_capabilities_on: mask_for(sast_false_positive_trigger),
          triage_capabilities_auto: 0)
      end
    end

    context 'when the profile is soft-deleted' do
      let!(:project) { create_project(name: 'deleted') }
      let!(:profile) do
        create_profile(name: 'profile', scan_type: triage_and_remediation_type, deleted_at: Time.current)
      end

      let!(:sif) do
        create_inventory_filter(project: project, triage_capabilities_on: stale_bits,
          triage_capabilities_auto: stale_bits)
      end

      before do
        attach_profile(project: project, profile: profile)
        add_trigger(profile: profile, trigger_type: sast_false_positive_trigger)
      end

      it 'clears the stale bits instead of counting the deleted profile' do
        migration_instance.perform

        expect(sif.reload).to have_attributes(triage_capabilities_on: 0, triage_capabilities_auto: 0)
      end
    end

    context 'when a non-remediation profile is attached' do
      let!(:project) { create_project(name: 'sast-only') }
      let!(:profile) { create_profile(name: 'profile', scan_type: sast_scan_type) }
      let!(:sif) do
        create_inventory_filter(project: project, triage_capabilities_on: stale_bits,
          triage_capabilities_auto: stale_bits)
      end

      before do
        attach_profile(project: project, profile: profile)
        add_trigger(profile: profile, trigger_type: default_branch_pipeline_trigger)
      end

      it 'clears the stale bits instead of counting the non-remediation profile' do
        migration_instance.perform

        expect(sif.reload).to have_attributes(triage_capabilities_on: 0, triage_capabilities_auto: 0)
      end
    end

    context 'when the existing row has stale, incorrect bits' do
      let!(:project) { create_project(name: 'stale-bits') }
      let!(:profile) { create_profile(name: 'profile', scan_type: triage_and_remediation_type) }
      let!(:sif) do
        create_inventory_filter(project: project, triage_capabilities_on: stale_bits,
          triage_capabilities_auto: stale_bits)
      end

      before do
        attach_profile(project: project, profile: profile)
        add_trigger(profile: profile, trigger_type: sast_vulnerability_resolution_trigger)
      end

      it 'overwrites them with the recomputed value rather than merging' do
        migration_instance.perform

        expect(sif.reload).to have_attributes(
          triage_capabilities_on: mask_for(sast_vulnerability_resolution_trigger),
          triage_capabilities_auto: mask_for(sast_vulnerability_resolution_trigger)
        )
      end
    end

    context 'with multiple projects in the same batch' do
      let!(:project1) { create_project(name: 'multi-1') }
      let!(:project2) { create_project(name: 'multi-2') }
      let!(:profile1) { create_profile(name: 'profile1', scan_type: triage_and_remediation_type) }
      let!(:profile2) { create_profile(name: 'profile2', scan_type: triage_and_remediation_type) }
      let!(:sif1) { create_inventory_filter(project: project1) }
      let!(:sif2) { create_inventory_filter(project: project2) }

      before do
        attach_profile(project: project1, profile: profile1)
        add_trigger(profile: profile1, trigger_type: sbom_ingested_trigger)

        attach_profile(project: project2, profile: profile2)
        add_trigger(profile: profile2, trigger_type: sast_false_positive_trigger, run_mode: 'manual')
      end

      it 'updates each project independently' do
        migration_instance.perform

        expect(sif1.reload).to have_attributes(
          triage_capabilities_on: mask_for(sbom_ingested_trigger),
          triage_capabilities_auto: mask_for(sbom_ingested_trigger)
        )
        expect(sif2.reload).to have_attributes(
          triage_capabilities_on: mask_for(sast_false_positive_trigger), triage_capabilities_auto: 0
        )
      end
    end

    context 'when a project has multiple trigger types attached' do
      let(:secret_detection_false_positive_trigger) { 12 }
      let(:vulnerability_enrichment_trigger) { 13 }

      let!(:project) { create_project(name: 'multi-trigger') }
      let!(:profile) { create_profile(name: 'profile', scan_type: triage_and_remediation_type) }
      let!(:sif) { create_inventory_filter(project: project) }

      before do
        attach_profile(project: project, profile: profile)
        add_trigger(profile: profile, trigger_type: secret_detection_false_positive_trigger)
        add_trigger(profile: profile, trigger_type: vulnerability_enrichment_trigger, run_mode: 'manual')
      end

      it 'ORs the bits together' do
        migration_instance.perform

        expect(sif.reload).to have_attributes(
          triage_capabilities_on:
            mask_for(secret_detection_false_positive_trigger) | mask_for(vulnerability_enrichment_trigger),
          triage_capabilities_auto: mask_for(secret_detection_false_positive_trigger)
        )
      end
    end

    context 'when sbom_ingested is attached via a triage_and_remediation profile' do
      let!(:project) { create_project(name: 'sbom-via-tr') }
      let!(:profile) { create_profile(name: 'profile', scan_type: triage_and_remediation_type) }
      let!(:sif) { create_inventory_filter(project: project) }

      before do
        attach_profile(project: project, profile: profile)
        add_trigger(profile: profile, trigger_type: sbom_ingested_trigger)
      end

      it 'sets both bits, same as via a dependency_scanning_post_processing profile' do
        migration_instance.perform

        expect(sif.reload).to have_attributes(
          triage_capabilities_on: mask_for(sbom_ingested_trigger),
          triage_capabilities_auto: mask_for(sbom_ingested_trigger)
        )
      end
    end

    context 'when the configuration row exists but has no run_mode key' do
      let!(:project) { create_project(name: 'no-run-mode-key') }
      let!(:profile) { create_profile(name: 'profile', scan_type: triage_and_remediation_type) }
      let!(:sif) { create_inventory_filter(project: project) }
      let!(:configuration) do
        security_scan_profile_configurations_table.create!(
          security_scan_profile_id: profile.id, namespace_id: group.id, configuration: { severity_level: 'high' }
        )
      end

      before do
        attach_profile(project: project, profile: profile)
        security_scan_profile_triggers_table.create!(
          security_scan_profile_id: profile.id, namespace_id: group.id,
          trigger_type: sast_false_positive_trigger, security_scan_profile_configuration_id: configuration.id
        )
      end

      it 'falls back to the default run_mode (auto)' do
        migration_instance.perform

        expect(sif.reload).to have_attributes(
          triage_capabilities_on: mask_for(sast_false_positive_trigger),
          triage_capabilities_auto: mask_for(sast_false_positive_trigger)
        )
      end
    end

    context 'when the project has no existing security_inventory_filters row' do
      let!(:project) { create_project(name: 'no-sif-row') }
      let!(:profile) { create_profile(name: 'profile', scan_type: triage_and_remediation_type) }

      before do
        attach_profile(project: project, profile: profile)
        add_trigger(profile: profile, trigger_type: sast_false_positive_trigger)
      end

      it 'does not raise and creates no row' do
        expect { migration_instance.perform }.not_to raise_error

        expect(security_inventory_filters_table.where(project_id: project.id)).not_to exist
      end
    end

    context 'when run twice' do
      let!(:project) { create_project(name: 'idempotent') }
      let!(:profile) { create_profile(name: 'profile', scan_type: triage_and_remediation_type) }
      let!(:sif) { create_inventory_filter(project: project) }

      before do
        attach_profile(project: project, profile: profile)
        add_trigger(profile: profile, trigger_type: sast_false_positive_trigger)
      end

      it 'produces the same result' do
        migration_instance.perform
        migration_instance.perform

        expect(sif.reload).to have_attributes(
          triage_capabilities_on: mask_for(sast_false_positive_trigger),
          triage_capabilities_auto: mask_for(sast_false_positive_trigger)
        )
      end
    end
  end
end
