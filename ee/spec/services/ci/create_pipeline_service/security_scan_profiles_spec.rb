# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ci::CreatePipelineService, feature_category: :security_asset_inventories do # rubocop:disable RSpec/SpecFilePathFormat -- grouped with other CreatePipelineService specs
  let_it_be(:group) { create(:group) }
  let_it_be_with_refind(:project) { create(:project, :small_repo, :auto_devops_disabled, group: group) }
  let_it_be(:user) { create(:user, developer_of: project) }
  let_it_be(:scan_profile) do
    create(:security_scan_profile, namespace: group, scan_type: :sast, projects: [project])
  end

  let_it_be(:trigger) { create(:security_scan_profile_trigger, namespace: group, scan_profile: scan_profile) }

  let(:service) { described_class.new(project, user, { ref: project.default_branch }) }

  subject(:execute) { service.execute(:push) }

  describe 'security scan profile configuration errors' do
    before do
      stub_licensed_features(security_scan_profiles: true)

      allow_next_instance_of(::Security::SecurityOrchestrationPolicies::ScanPipelineService) do |scan_service|
        allow(scan_service).to receive(:execute)
          .and_raise(Gitlab::Ci::Config::ConfigError, 'secret-internal-detail')
      end
    end

    it 'fails the pipeline with a generic error that does not disclose the original details', :aggregate_failures do
      result = execute
      pipeline = result.payload

      # Config should come from the profile source, not from a repository file.
      expect(project.repository.blob_at(project.default_branch, '.gitlab-ci.yml')).to be_nil
      expect(pipeline).to be_persisted
      expect(pipeline).to be_failed
      expect(pipeline.failure_reason).to eq('config_error')
      messages = pipeline.error_messages.map(&:content).join

      expect(result.message).not_to include('secret-internal-detail')
      expect(messages).to include('Security scan profile configuration is invalid')
      expect(messages).not_to include('secret-internal-detail')
    end
  end
end
