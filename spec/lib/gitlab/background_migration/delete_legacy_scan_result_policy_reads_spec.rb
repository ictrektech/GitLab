# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundMigration::DeleteLegacyScanResultPolicyReads,
  feature_category: :security_policy_management do
  let(:organizations) { table(:organizations) }
  let(:namespaces) { table(:namespaces) }
  let(:projects) { table(:projects) }
  let(:merge_requests) { table(:merge_requests) }
  let(:policy_configurations) { table(:security_orchestration_policy_configurations) }
  let(:security_policies) { table(:security_policies) }
  let(:approval_policy_rules) { table(:approval_policy_rules) }
  let(:scan_result_policies) { table(:scan_result_policies) }
  let(:approval_project_rules) { table(:approval_project_rules) }
  let(:approval_merge_request_rules) { table(:approval_merge_request_rules) }
  let(:software_license_policies) { table(:software_license_policies) }
  let(:scan_result_policy_violations) { table(:scan_result_policy_violations) }
  let(:approval_merge_request_rule_sources) { table(:approval_merge_request_rule_sources) }

  let(:opened) { 1 }
  let(:closed) { 2 }
  let(:merged) { 3 }
  let(:locked) { 4 }

  let(:organization) { organizations.create!(name: 'organization', path: 'organization') }
  let(:group) { namespaces.create!(name: 'group', path: 'group', type: 'Group', organization_id: organization.id) }

  let(:project) do
    projects.create!(name: 'project', path: 'project', organization_id: organization.id,
      project_namespace_id: group.id, namespace_id: group.id)
  end

  let(:policy_configuration) do
    policy_configurations.create!(namespace_id: group.id, security_policy_management_project_id: project.id)
  end

  let(:other_policy_configuration) do
    policy_configurations.create!(project_id: project.id, security_policy_management_project_id: project.id)
  end

  let(:migration_args) do
    {
      start_cursor: [0],
      end_cursor: [scan_result_policies.maximum(:id)],
      batch_table: :scan_result_policies,
      batch_column: :id,
      sub_batch_size: 100,
      pause_ms: 0,
      connection: ApplicationRecord.connection
    }
  end

  describe '#perform' do
    before do
      # The job leaves configurations without any security_policies rows alone.
      [policy_configuration, other_policy_configuration].each do |configuration|
        create_security_policy(configuration: configuration, policy_index: 9, type: 1)
      end
    end

    it 'deletes legacy reads whose policy no longer exists' do
      legacy_read = create_read

      perform_migration

      expect(scan_result_policies.pluck(:id)).not_to include(legacy_read.id)
    end

    it 'keeps legacy reads when an enabled policy in the configuration has a rule at the rule index' do
      create_approval_policy_rule(policy_index: 2, rule_index: 1)
      kept_read = create_read(orchestration_policy_idx: 2, rule_idx: 1)
      other_rule_read = create_read(orchestration_policy_idx: 2, rule_idx: 0)
      other_policy_read = create_read(orchestration_policy_idx: 0, rule_idx: 1)
      other_configuration_read = create_read(
        orchestration_policy_idx: 2, rule_idx: 1, configuration: other_policy_configuration
      )

      perform_migration

      expect(scan_result_policies.pluck(:id)).to contain_exactly(kept_read.id, other_policy_read.id)
      expect(scan_result_policies.where(id: [other_rule_read.id, other_configuration_read.id])).to be_empty
    end

    it 'keeps a legacy read when its own policy is disabled but another enabled policy has the rule' do
      create_approval_policy_rule(policy_index: 0, rule_index: 1, enabled: false)
      create_approval_policy_rule(policy_index: 1, rule_index: 0)
      read = create_read(orchestration_policy_idx: 0, rule_idx: 0)

      perform_migration

      expect(scan_result_policies.pluck(:id)).to contain_exactly(read.id)
    end

    it 'keeps a legacy read whose stored index differs from the current policy order' do
      create_approval_policy_rule(policy_index: 0, rule_index: 1)
      read = create_read(orchestration_policy_idx: 2, rule_idx: 1)

      perform_migration

      expect(scan_result_policies.pluck(:id)).to contain_exactly(read.id)
    end

    it 'deletes a legacy read when only a disabled policy has a rule at the rule index' do
      create_approval_policy_rule(policy_index: 0, rule_index: 1, enabled: false)
      read = create_read(orchestration_policy_idx: 0, rule_idx: 1)

      perform_migration

      expect(scan_result_policies.pluck(:id)).not_to include(read.id)
    end

    it 'deletes a legacy read when only a soft-deleted policy has a rule at the rule index' do
      create_approval_policy_rule(policy_index: -1, rule_index: 1, enabled: false)
      read = create_read(orchestration_policy_idx: 0, rule_idx: 1)

      perform_migration

      expect(scan_result_policies.pluck(:id)).not_to include(read.id)
    end

    it 'deletes a legacy read without a rule index' do
      create_approval_policy_rule(policy_index: 0, rule_index: 0)
      read = create_read(rule_idx: nil)

      perform_migration

      expect(scan_result_policies.pluck(:id)).not_to include(read.id)
    end

    it 'does not treat a policy of another type as the read policy' do
      create_approval_policy_rule(policy_index: 0, rule_index: 0, type: 1)
      read = create_read(orchestration_policy_idx: 0, rule_idx: 0)

      perform_migration

      expect(scan_result_policies.pluck(:id)).not_to include(read.id)
    end

    it 'keeps legacy reads of a configuration without security policies' do
      other_group = namespaces.create!(name: 'other', path: 'other', type: 'Group', organization_id: organization.id)
      configuration = policy_configurations.create!(
        namespace_id: other_group.id, security_policy_management_project_id: project.id
      )
      read = create_read(configuration: configuration)
      merge_request_rule = create_merge_request_rule(read, create_merge_request(state_id: opened))

      perform_migration

      expect(scan_result_policies.pluck(:id)).to contain_exactly(read.id)
      expect(approval_merge_request_rules.find(merge_request_rule.id).scan_result_policy_id).to eq(read.id)
    end

    it 'keeps reads that have an approval policy rule' do
      rule = create_approval_policy_rule(policy_index: 1, rule_index: 0)
      read = create_read(approval_policy_rule_id: rule.id, orchestration_policy_idx: 5)

      perform_migration

      expect(scan_result_policies.pluck(:id)).to contain_exactly(read.id)
    end

    it 'deletes the project rules of deleted reads and keeps the others' do
      legacy_read = create_read(rule_idx: 1)
      rule = create_approval_policy_rule(policy_index: 1, rule_index: 0)
      current_read = create_read(approval_policy_rule_id: rule.id, orchestration_policy_idx: 1)
      legacy_project_rule = create_project_rule(legacy_read)
      current_project_rule = create_project_rule(current_read)

      perform_migration

      expect(approval_project_rules.pluck(:id)).to contain_exactly(current_project_rule.id)
      expect(approval_project_rules.where(id: legacy_project_rule.id)).to be_empty
    end

    it 'deletes the rules of deleted reads on unmerged merge requests' do
      legacy_read = create_read
      unmerged_rules = [opened, closed, locked].map do |state_id|
        create_merge_request_rule(legacy_read, create_merge_request(state_id: state_id))
      end

      perform_migration

      expect(approval_merge_request_rules.where(id: unmerged_rules.map(&:id))).to be_empty
    end

    it 'finishes a sub-batch that a previous run left half done' do
      legacy_read = create_read
      done_merged_rule = create_merge_request_rule(legacy_read, create_merge_request(state_id: merged))
      done_merged_rule.update!(scan_result_policy_id: nil)
      merged_rule = create_merge_request_rule(legacy_read, create_merge_request(state_id: merged))
      unmerged_rule = create_merge_request_rule(legacy_read, create_merge_request(state_id: opened))
      create_license_policy(legacy_read)

      perform_migration

      expect(scan_result_policies.where(id: legacy_read.id)).to be_empty
      expect(approval_merge_request_rules.where(id: unmerged_rule.id)).to be_empty
      merged_rule_ids = [done_merged_rule.id, merged_rule.id]
      expect(approval_merge_request_rules.where(id: merged_rule_ids).pluck(:scan_result_policy_id)).to eq([nil, nil])
      expect(software_license_policies.count).to eq(0)
    end

    it 'keeps the rules of deleted reads on merged merge requests without a read' do
      legacy_read = create_read
      merged_rule = create_merge_request_rule(legacy_read, create_merge_request(state_id: merged))

      perform_migration

      expect(approval_merge_request_rules.find(merged_rule.id).scan_result_policy_id).to be_nil
    end

    it 'keeps the rules of kept reads' do
      create_approval_policy_rule(policy_index: 0, rule_index: 0)
      kept_read = create_read(orchestration_policy_idx: 0, rule_idx: 0)
      project_rule = create_project_rule(kept_read)
      merge_request_rule = create_merge_request_rule(kept_read, create_merge_request(state_id: opened))

      perform_migration

      expect(approval_project_rules.pluck(:id)).to contain_exactly(project_rule.id)
      expect(approval_merge_request_rules.pluck(:id)).to contain_exactly(merge_request_rule.id)
    end

    it 'keeps the rules of a kept read that shares a sub-batch with a deleted read' do
      create_approval_policy_rule(policy_index: 0, rule_index: 1)
      deleted_read = create_read(rule_idx: 0)
      kept_read = create_read(rule_idx: 1)
      deleted_mr_rule = create_merge_request_rule(deleted_read, create_merge_request(state_id: opened))
      project_rule = create_project_rule(kept_read)
      open_rule = create_merge_request_rule(kept_read, create_merge_request(state_id: opened))
      merged_rule = create_merge_request_rule(kept_read, create_merge_request(state_id: merged))
      source = approval_merge_request_rule_sources.create!(
        approval_merge_request_rule_id: open_rule.id, approval_project_rule_id: project_rule.id, project_id: project.id
      )

      perform_migration

      expect(scan_result_policies.pluck(:id)).to contain_exactly(kept_read.id)
      expect(approval_project_rules.pluck(:id)).to contain_exactly(project_rule.id)
      expect(approval_merge_request_rule_sources.pluck(:id)).to contain_exactly(source.id)
      expect(approval_merge_request_rules.where(id: deleted_mr_rule.id)).to be_empty
      expect(approval_merge_request_rules.where(id: [open_rule.id, merged_rule.id]).pluck(:scan_result_policy_id))
        .to eq([kept_read.id, kept_read.id])
    end

    it 'deletes the license policies and violations of deleted reads and keeps the others' do
      legacy_read = create_read
      create_approval_policy_rule(policy_index: 0, rule_index: 1)
      kept_read = create_read(rule_idx: 1)
      merge_request = create_merge_request(state_id: opened)
      create_license_policy(legacy_read)
      create_violation(legacy_read, merge_request)
      kept_license_policy = create_license_policy(kept_read)
      kept_violation = create_violation(kept_read, merge_request)

      perform_migration

      expect(software_license_policies.pluck(:id)).to contain_exactly(kept_license_policy.id)
      expect(scan_result_policy_violations.pluck(:id)).to contain_exactly(kept_violation.id)
    end

    it 'handles dependent rows across chunks' do
      stub_const("#{described_class}::DEPENDENT_CHUNK_SIZE", 1)
      legacy_read = create_read
      opened_mr = create_merge_request(state_id: opened)
      merged_mr = create_merge_request(state_id: merged)
      project_rules = Array.new(2) do
        create_merge_request_rule(legacy_read, opened_mr)
        create_license_policy(legacy_read)
        create_project_rule(legacy_read)
      end
      merged_rules = Array.new(2) { create_merge_request_rule(legacy_read, merged_mr) }
      merged_rules.each do |rule|
        approval_merge_request_rule_sources.create!(
          approval_merge_request_rule_id: rule.id,
          approval_project_rule_id: project_rules.first.id,
          project_id: project.id
        )
      end
      create_violation(legacy_read, opened_mr)
      create_violation(legacy_read, merged_mr)

      perform_migration

      expect(scan_result_policies.where(id: legacy_read.id)).to be_empty
      expect(approval_project_rules.count).to eq(0)
      expect(approval_merge_request_rule_sources.count).to eq(0)
      expect(approval_merge_request_rules.pluck(:id, :scan_result_policy_id))
        .to match_array(merged_rules.map { |rule| [rule.id, nil] })
      expect(software_license_policies.count).to eq(0)
      expect(scan_result_policy_violations.count).to eq(0)
    end

    it 'deletes legacy reads across sub-batches' do
      legacy_reads = Array.new(3) { |index| create_read(rule_idx: index) }

      perform_migration(sub_batch_size: 1)

      expect(scan_result_policies.where(id: legacy_reads.map(&:id))).to be_empty
    end
  end

  def perform_migration(sub_batch_size: 100)
    described_class.new(**migration_args.merge(sub_batch_size: sub_batch_size)).perform
  end

  def create_security_policy(policy_index:, type: 0, enabled: true, configuration: policy_configuration)
    security_policies.create!(
      security_orchestration_policy_configuration_id: configuration.id,
      security_policy_management_project_id: project.id,
      policy_index: policy_index,
      type: type,
      enabled: enabled,
      name: 'Policy',
      checksum: SecureRandom.hex(32)
    )
  end

  def create_approval_policy_rule(
    policy_index:, rule_index:, type: 0, enabled: true,
    configuration: policy_configuration)
    policy = create_security_policy(
      policy_index: policy_index, type: type, enabled: enabled, configuration: configuration
    )

    approval_policy_rules.create!(
      security_policy_id: policy.id,
      security_policy_management_project_id: project.id,
      rule_index: rule_index,
      type: 0 # scan_finding
    )
  end

  def create_read(configuration: policy_configuration, orchestration_policy_idx: 0, rule_idx: 0, **attributes)
    scan_result_policies.create!(
      security_orchestration_policy_configuration_id: configuration.id,
      project_id: project.id,
      orchestration_policy_idx: orchestration_policy_idx,
      rule_idx: rule_idx,
      **attributes
    )
  end

  def create_project_rule(read)
    approval_project_rules.create!(
      project_id: project.id,
      name: 'Rule',
      scan_result_policy_id: read.id,
      security_orchestration_policy_configuration_id: read.security_orchestration_policy_configuration_id
    )
  end

  def create_license_policy(read)
    software_license_policies.create!(
      project_id: project.id,
      scan_result_policy_id: read.id,
      software_license_spdx_identifier: "MIT-#{SecureRandom.hex(4)}"
    )
  end

  def create_violation(read, merge_request)
    scan_result_policy_violations.create!(
      project_id: project.id,
      merge_request_id: merge_request.id,
      scan_result_policy_id: read.id
    )
  end

  def create_merge_request(state_id:)
    merge_requests.create!(
      target_project_id: project.id,
      target_branch: 'main',
      source_branch: "feature-#{SecureRandom.hex(4)}",
      state_id: state_id
    )
  end

  def create_merge_request_rule(read, merge_request)
    approval_merge_request_rules.create!(
      merge_request_id: merge_request.id,
      project_id: project.id,
      name: 'Rule',
      scan_result_policy_id: read.id,
      security_orchestration_policy_configuration_id: read.security_orchestration_policy_configuration_id
    )
  end
end
