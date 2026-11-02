# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mcp::Tools::Security::AttachScanProfileService, feature_category: :mcp_server do
  let(:service) { described_class.new(name: 'attachScanProfile') }

  describe '.available_versions' do
    subject { described_class.available_versions }

    it { is_expected.to contain_exactly('0.1.0') }
  end

  describe '#annotations' do
    it 'declares the tool annotations' do
      expect(service.annotations).to eq(
        title: 'Attach security scan profile',
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: false
      )
    end
  end

  describe 'input schema' do
    it 'locks the full input schema for version 0.1.0' do
      expect(described_class.version_metadata('0.1.0')[:input_schema]).to eq({
        type: 'object',
        properties: {
          security_scan_profile_id: {
            type: 'string',
            description: 'Global ID of the security scan profile to attach.'
          },
          project_ids: {
            type: 'array',
            description: 'Array of Global IDs of the projects. Required if `group_ids` not provided. ' \
              'Together with group_ids, at most 100 ids.',
            items: {
              type: 'string'
            },
            minItems: 1,
            maxItems: 100
          },
          group_ids: {
            type: 'array',
            description: 'Array of Global IDs of the groups. Required if `project_ids` not provided. ' \
              'Together with project_ids, at most 100 ids.',
            items: {
              type: 'string'
            },
            minItems: 1,
            maxItems: 100
          }
        },
        required: %w[security_scan_profile_id],
        additionalProperties: false
      })
    end
  end

  describe '#execute' do
    let_it_be(:user) { create(:user) }
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:scan_profile) { create(:security_scan_profile, namespace: group) }

    let(:request) { instance_double(ActionDispatch::Request) }

    subject(:attach_profile) { service.execute(request: request, params: params) }

    before_all do
      group.add_maintainer(user)
    end

    before do
      service.set_cred(current_user: user)

      stub_licensed_features(security_scan_profiles: true)
    end

    context 'when only project IDs provided' do
      let(:params) do
        {
          arguments: {
            security_scan_profile_id: scan_profile.to_global_id.to_s,
            project_ids: [project.to_global_id.to_s]
          }
        }
      end

      it 'attaches the given profile to given project' do
        expect { attach_profile }.to change { project.reload.security_scan_profiles.to_a }.to([scan_profile])
      end
    end

    context 'when only group IDs provided' do
      let(:params) do
        {
          arguments: {
            security_scan_profile_id: scan_profile.to_global_id.to_s,
            group_ids: [group.to_global_id.to_s]
          }
        }
      end

      before do
        allow(Security::ScanProfiles::AttachWorker).to receive(:bulk_perform_async_with_contexts)
      end

      it 'schedules attaching scan profile to the entire group' do
        attach_profile

        expect(Security::ScanProfiles::AttachWorker)
          .to have_received(:bulk_perform_async_with_contexts)
                .with([group], arguments_proc: an_instance_of(Proc), context_proc: an_instance_of(Proc))
      end
    end

    context 'when both project IDs and group IDs provided' do
      let(:params) do
        {
          arguments: {
            security_scan_profile_id: scan_profile.to_global_id.to_s,
            project_ids: [project.to_global_id.to_s],
            group_ids: [group.to_global_id.to_s]
          }
        }
      end

      before do
        allow(Security::ScanProfiles::AttachWorker).to receive(:bulk_perform_async_with_contexts)
      end

      it 'schedules attaching scan profile to the entire group' do
        attach_profile

        expect(Security::ScanProfiles::AttachWorker)
          .to have_received(:bulk_perform_async_with_contexts)
                .with([group], arguments_proc: an_instance_of(Proc), context_proc: an_instance_of(Proc))
      end

      it 'attaches the given profile to given project' do
        expect { attach_profile }.to change { project.reload.security_scan_profiles.to_a }.to([scan_profile])
      end
    end
  end

  describe '#governed_containers' do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }
    let_it_be(:scan_profile) { create(:security_scan_profile, namespace: group) }

    it 'governs by the namespace holding the scan profile', :aggregate_failures do
      arguments = { security_scan_profile_id: scan_profile.to_global_id.to_s }.with_indifferent_access
      resolved = service.governed_containers(arguments)

      expect(resolved.containers).to contain_exactly(group)
      expect(resolved.named).to eq(1)
    end

    it 'governs the named projects alongside the profile namespace', :aggregate_failures do
      arguments = {
        security_scan_profile_id: scan_profile.to_global_id.to_s,
        project_ids: [project.to_global_id.to_s]
      }.with_indifferent_access
      resolved = service.governed_containers(arguments)

      expect(resolved.containers).to contain_exactly(project, group)
      expect(resolved.named).to eq(2)
    end

    it 'does not read the id out of a Global ID naming another model, so the call is refused',
      :aggregate_failures do
      arguments = { security_scan_profile_id: "gid://gitlab/Project/#{scan_profile.id}" }.with_indifferent_access
      resolved = service.governed_containers(arguments)

      expect(resolved.containers).to be_empty
      expect(resolved.named).to eq(1)
    end

    it 'counts an unknown profile as named so the call is refused', :aggregate_failures do
      arguments = { security_scan_profile_id: non_existing_record_id.to_s }.with_indifferent_access
      resolved = service.governed_containers(arguments)

      expect(resolved.containers).to be_empty
      expect(resolved.named).to eq(1)
    end

    context 'when project_ids and group_ids together name more ids than the mutation accepts' do
      let(:arguments) do
        {
          security_scan_profile_id: scan_profile.to_global_id.to_s,
          project_ids: Array.new(60) { project.to_global_id.to_s },
          group_ids: Array.new(60) { group.to_global_id.to_s }
        }.with_indifferent_access
      end

      it 'refuses the call before resolving any id', :aggregate_failures do
        expect(service).not_to receive(:lookup_projects)
        expect(service).not_to receive(:lookup_groups)

        expect { service.governed_containers(arguments) }
          .to raise_error(ArgumentError, 'project_ids and group_ids together cannot name more than 100 ids')
      end
    end

    it 'resolves project_ids and group_ids that together reach the limit' do
      arguments = {
        project_ids: Array.new(50) { project.to_global_id.to_s },
        group_ids: Array.new(50) { group.to_global_id.to_s }
      }.with_indifferent_access

      expect(service.governed_containers(arguments).containers).to contain_exactly(project, group)
    end
  end
end
