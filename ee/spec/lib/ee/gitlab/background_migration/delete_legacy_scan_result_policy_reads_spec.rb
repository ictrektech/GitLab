# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::BackgroundMigration::DeleteLegacyScanResultPolicyReads,
  feature_category: :security_policy_management do
  let(:organizations) { table(:organizations) }
  let(:namespaces) { table(:namespaces) }
  let(:projects) { table(:projects) }
  let(:policy_configurations) { table(:security_orchestration_policy_configurations) }
  let(:security_policies) { table(:security_policies) }
  let(:scan_result_policies) { table(:scan_result_policies) }

  let(:organization) { organizations.create!(name: 'organization', path: 'organization') }
  let(:group) { namespaces.create!(name: 'group', path: 'group', type: 'Group', organization_id: organization.id) }

  let(:project) do
    projects.create!(name: 'project', path: 'project', organization_id: organization.id,
      project_namespace_id: group.id, namespace_id: group.id)
  end

  let(:configuration_without_policies) do
    policy_configurations.create!(namespace_id: group.id, security_policy_management_project_id: project.id)
  end

  let(:configuration_with_policies) do
    policy_configurations.create!(project_id: project.id, security_policy_management_project_id: project.id).tap do |c|
      security_policies.create!(
        security_orchestration_policy_configuration_id: c.id,
        security_policy_management_project_id: project.id,
        policy_index: 0, type: 1, enabled: true, name: 'Policy', checksum: SecureRandom.hex(32)
      )
    end
  end

  describe '#perform' do
    it 'resyncs each configuration without security policies once, at a delay derived from its id' do
      reads = Array.new(2) { |index| create_read(configuration_without_policies, rule_idx: index) }
      create_read(configuration_with_policies)

      expect(Security::SyncScanPoliciesWorker)
        .to receive(:perform_in).once
        .with((configuration_without_policies.id % 6.hours.to_i).seconds, configuration_without_policies.id)

      described_class.new(
        start_cursor: [0],
        end_cursor: [scan_result_policies.maximum(:id)],
        batch_table: :scan_result_policies,
        batch_column: :id,
        sub_batch_size: 1,
        pause_ms: 0,
        connection: ApplicationRecord.connection
      ).perform

      expect(scan_result_policies.where(id: reads.map(&:id)).count).to eq(2)
    end
  end

  def create_read(configuration, rule_idx: 0)
    scan_result_policies.create!(
      security_orchestration_policy_configuration_id: configuration.id,
      project_id: project.id,
      orchestration_policy_idx: 0,
      rule_idx: rule_idx
    )
  end
end
