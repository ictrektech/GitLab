# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Security::TriageCoverage::RecomputeService, feature_category: :security_asset_inventories do
  let_it_be(:group) { create(:group) }
  let_it_be(:project) { create(:project, namespace: group) }

  before do
    stub_licensed_features(security_scan_profiles: true)
    stub_feature_flags(triage_and_remediation_profile: true)
  end

  def attach!(profile, project, trigger_type, configuration_values: nil)
    trigger = create(:security_scan_profile_trigger, scan_profile: profile, trigger_type: trigger_type,
      configuration_values: configuration_values)
    Security::ScanProfileProject.find_or_create_by!(scan_profile: profile, project: project)
    trigger
  end

  describe '.execute' do
    it 'delegates to a new instance' do
      instance = instance_double(described_class, execute: nil)
      expect(described_class).to receive(:new).with([project.id]).and_return(instance)

      described_class.execute([project.id])
    end
  end

  describe '#execute' do
    subject(:execute) { described_class.execute(project_ids) }

    context 'when project_ids is empty' do
      let(:project_ids) { [] }

      it 'does not call TriageCapabilitiesUpdateService' do
        expect(Security::InventoryFilters::TriageCapabilitiesUpdateService).not_to receive(:execute)

        execute
      end
    end

    context 'when no profile is attached to the project' do
      let(:project_ids) { [project.id] }

      it 'writes zeroed-out bitmasks' do
        execute

        filter = Security::InventoryFilter.find_by(project: project)
        expect(filter).to have_attributes(triage_capabilities_on: 0, triage_capabilities_auto: 0)
      end
    end

    context 'when sbom_ingested is attached via a dependency_scanning_post_processing profile' do
      let(:project_ids) { [project.id] }
      let(:profile) { create(:security_scan_profile, :dependency_scanning_post_processing, namespace: group) }

      before do
        attach!(profile, project, :sbom_ingested)
      end

      it 'sets the sbom_ingested bit in both masks, since it is always auto when attached' do
        execute

        filter = Security::InventoryFilter.find_by(project: project)
        expect(filter.triage_capabilities_on).to eq(0b1)
        expect(filter.triage_capabilities_auto).to eq(0b1)
      end
    end

    context 'when a triage_and_remediation trigger is attached with default (auto) run_mode' do
      let(:project_ids) { [project.id] }
      let(:profile) { create(:security_scan_profile, :triage_and_remediation, namespace: group) }

      before do
        attach!(profile, project, :sast_false_positive)
      end

      it 'sets both the on and auto bits for that trigger' do
        execute

        filter = Security::InventoryFilter.find_by(project: project)
        mask = Security::TriageCoverage::CapabilityBitmask.mask_for(:sast_false_positive)
        expect(filter.triage_capabilities_on & mask).not_to eq(0)
        expect(filter.triage_capabilities_auto & mask).not_to eq(0)
      end
    end

    context 'when a triage_and_remediation trigger is attached with manual run_mode' do
      let(:project_ids) { [project.id] }
      let(:profile) { create(:security_scan_profile, :triage_and_remediation, namespace: group) }

      before do
        attach!(profile, project, :sast_false_positive, configuration_values: { run_mode: 'manual' })
      end

      it 'sets only the on bit, not the auto bit' do
        execute

        filter = Security::InventoryFilter.find_by(project: project)
        mask = Security::TriageCoverage::CapabilityBitmask.mask_for(:sast_false_positive)
        expect(filter.triage_capabilities_on & mask).not_to eq(0)
        expect(filter.triage_capabilities_auto & mask).to eq(0)
      end
    end

    context 'when the triage_and_remediation_profile feature flag is disabled' do
      let(:project_ids) { [project.id] }
      let(:profile) { create(:security_scan_profile, :triage_and_remediation, namespace: group) }

      before do
        stub_feature_flags(triage_and_remediation_profile: false)
        attach!(profile, project, :sast_false_positive)
      end

      it 'does not set the bit for the gated trigger' do
        execute

        filter = Security::InventoryFilter.find_by(project: project)
        expect(filter.triage_capabilities_on).to eq(0)
      end
    end

    context 'with multiple projects' do
      let_it_be(:other_project) { create(:project, namespace: group) }
      let(:project_ids) { [project.id, other_project.id] }
      let(:profile) { create(:security_scan_profile, :dependency_scanning_post_processing, namespace: group) }

      before do
        attach!(profile, project, :sbom_ingested)
      end

      it 'computes capabilities independently per project' do
        execute

        expect(Security::InventoryFilter.find_by(project: project).triage_capabilities_on).to eq(0b1)
        expect(Security::InventoryFilter.find_by(project: other_project).triage_capabilities_on).to eq(0)
      end
    end

    describe 'auto/on subset invariant' do
      let(:project_ids) { [project.id] }

      where(:trigger_type, :configuration_values, :expected_on_bit, :expected_auto_bit) do
        [
          [:sbom_ingested, nil, true, true],
          [:sast_false_positive, nil, true, true],
          [:sast_false_positive, { run_mode: 'manual' }, true, false],
          [:sast_vulnerability_resolution, { run_mode: 'manual' }, true, false],
          [:secret_detection_false_positive, { run_mode: 'auto' }, true, true],
          [:vulnerability_enrichment, { run_mode: 'manual' }, true, false]
        ]
      end

      with_them do
        let(:profile) do
          preset_trait = trigger_type == :sbom_ingested ? :dependency_scanning_post_processing : :triage_and_remediation
          create(:security_scan_profile, preset_trait, namespace: group)
        end

        before do
          attach!(profile, project, trigger_type, configuration_values: configuration_values)
        end

        it 'never sets an auto bit without the corresponding on bit' do
          execute

          filter = Security::InventoryFilter.find_by(project: project)
          expect(filter.triage_capabilities_auto & ~filter.triage_capabilities_on).to eq(0)

          mask = Security::TriageCoverage::CapabilityBitmask.mask_for(trigger_type)
          expect(filter.triage_capabilities_on & mask != 0).to eq(expected_on_bit)
          expect(filter.triage_capabilities_auto & mask != 0).to eq(expected_auto_bit)
        end
      end

      context 'when multiple triggers are attached to the same project at once' do
        let(:sbom_profile) { create(:security_scan_profile, :dependency_scanning_post_processing, namespace: group) }
        let(:triage_profile) { create(:security_scan_profile, :triage_and_remediation, namespace: group) }

        before do
          attach!(sbom_profile, project, :sbom_ingested)
          attach!(triage_profile, project, :sast_false_positive, configuration_values: { run_mode: 'manual' })
          attach!(triage_profile, project, :vulnerability_enrichment)
        end

        it 'accumulates the bits independently instead of overwriting them' do
          execute

          filter = Security::InventoryFilter.find_by(project: project)
          bitmask = Security::TriageCoverage::CapabilityBitmask
          expected_on = bitmask.mask_for(:sbom_ingested) | bitmask.mask_for(:sast_false_positive) |
            bitmask.mask_for(:vulnerability_enrichment)
          expected_auto = bitmask.mask_for(:sbom_ingested) | bitmask.mask_for(:vulnerability_enrichment)

          expect(filter.triage_capabilities_on).to eq(expected_on)
          expect(filter.triage_capabilities_auto).to eq(expected_auto)
          expect(filter.triage_capabilities_auto & ~filter.triage_capabilities_on).to eq(0)
        end
      end
    end

    describe 'recomputing after the underlying configuration shrinks' do
      let(:project_ids) { [project.id] }
      let(:profile) { create(:security_scan_profile, :triage_and_remediation, namespace: group) }

      it 'clears both bits once the profile is detached, not just the on bit' do
        attach!(profile, project, :sast_false_positive)
        execute

        filter = Security::InventoryFilter.find_by(project: project)
        expect(filter.triage_capabilities_on).not_to eq(0)
        expect(filter.triage_capabilities_auto).not_to eq(0)

        Security::ScanProfileProject.find_by!(scan_profile: profile, project: project).destroy!
        described_class.execute([project.id])

        filter.reload
        expect(filter.triage_capabilities_on).to eq(0)
        expect(filter.triage_capabilities_auto).to eq(0)
      end

      it 'clears only the auto bit when run_mode downgrades from auto to manual' do
        attach!(profile, project, :sast_false_positive)
        execute

        filter = Security::InventoryFilter.find_by(project: project)
        expect(filter.triage_capabilities_on).not_to eq(0)
        expect(filter.triage_capabilities_auto).not_to eq(0)

        Security::ScanProfileTrigger.find_by!(scan_profile: profile, trigger_type: 'sast_false_positive').destroy!
        attach!(profile, project, :sast_false_positive, configuration_values: { run_mode: 'manual' })
        described_class.execute([project.id])

        filter.reload
        expect(filter.triage_capabilities_on).not_to eq(0)
        expect(filter.triage_capabilities_auto).to eq(0)
      end
    end

    describe 'composing multiple profiles for the same trigger' do
      let(:project_ids) { [project.id] }
      let!(:manual_profile) do
        create(:security_scan_profile, :triage_and_remediation, namespace: group, name: 'Manual profile')
      end

      let!(:auto_profile) do
        create(:security_scan_profile, :triage_and_remediation, namespace: group, name: 'Auto profile')
      end

      before do
        attach!(manual_profile, project, :sast_false_positive, configuration_values: { run_mode: 'manual' })
        attach!(auto_profile, project, :sast_false_positive)
      end

      it "lets the lowest-id profile govern both the on and auto bits" do
        expect(manual_profile.id).to be < auto_profile.id

        execute

        filter = Security::InventoryFilter.find_by(project: project)
        mask = Security::TriageCoverage::CapabilityBitmask.mask_for(:sast_false_positive)
        expect(filter.triage_capabilities_on & mask).not_to eq(0)
        expect(filter.triage_capabilities_auto & mask).to eq(0)
      end
    end

    describe 'query efficiency across a batch of projects' do
      let_it_be(:profile) { create(:security_scan_profile, :triage_and_remediation, namespace: group) }
      let_it_be(:sbom_profile) do
        create(:security_scan_profile, :dependency_scanning_post_processing, namespace: group)
      end

      let_it_be(:sast_trigger) do
        create(:security_scan_profile_trigger, scan_profile: profile, trigger_type: :sast_false_positive)
      end

      let_it_be(:enrichment_trigger) do
        create(:security_scan_profile_trigger, scan_profile: profile, trigger_type: :vulnerability_enrichment,
          configuration_values: { run_mode: 'manual' })
      end

      let_it_be(:sbom_trigger) do
        create(:security_scan_profile_trigger, scan_profile: sbom_profile, trigger_type: :sbom_ingested)
      end

      def build_project_with_triggers
        proj = create(:project, namespace: group)
        Security::ScanProfileProject.find_or_create_by!(scan_profile: profile, project: proj)
        Security::ScanProfileProject.find_or_create_by!(scan_profile: sbom_profile, project: proj)
        proj
      end

      it 'does not issue more queries per project as the batch grows' do
        warmup_project = build_project_with_triggers
        one_project_ids = [build_project_with_triggers.id]
        five_project_ids = Array.new(5) { build_project_with_triggers.id }

        described_class.execute([warmup_project.id]) # warm schema/column caches so they don't skew the comparison

        control = ActiveRecord::QueryRecorder.new { described_class.execute(one_project_ids) }

        expect { described_class.execute(five_project_ids) }.not_to exceed_query_limit(control)
      end
    end
  end
end
