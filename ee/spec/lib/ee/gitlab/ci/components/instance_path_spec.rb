# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Ci::Components::InstancePath, feature_category: :pipeline_composition do
  let_it_be(:project) { create(:project, :custom_repo, files: { 'templates/test.yml' => 'test: content' }) }
  let_it_be(:member) { create(:user, developer_of: project) }
  let_it_be(:non_member) { create(:user) }

  let(:address) { "acme.com/#{project.full_path}/test@master" }
  let(:logger) { instance_double(Gitlab::Ci::Pipeline::Logger) }
  let(:execution_context) do
    instance_double(Gitlab::Ci::Pipeline::PipelineExecutionPolicies::PipelineContext,
      ci_config_access_allowed?: false)
  end

  let(:pipeline_policy_context) do
    instance_double(Gitlab::Ci::Pipeline::ExecutionPolicies::PipelineContext,
      pipeline_execution_context: execution_context)
  end

  let(:path) do
    described_class.new(address: address, logger: logger, pipeline_policy_context: pipeline_policy_context)
  end

  before do
    allow(Gitlab.config.gitlab).to receive(:server_fqdn).and_return('acme.com')
    allow(logger).to receive(:instrument) { |_operation, &block| block.call }
  end

  around do |example|
    ::Gitlab::Ci::Config::FeatureFlags.with_actor(nil) { example.run }
  end

  describe '#fetch_content!' do
    subject(:fetch_content) { path.fetch_content!(current_user: current_user) }

    context 'when the user can download code' do
      let(:current_user) { member }

      it 'does not check the pipeline execution policy grant' do
        expect(fetch_content.content).to eq('test: content')
        expect(execution_context).not_to have_received(:ci_config_access_allowed?)
      end
    end

    context 'when the user cannot download code' do
      let(:current_user) { non_member }

      it 'raises AccessDeniedError when the policy does not grant access' do
        expect { fetch_content }.to raise_error(Gitlab::Access::AccessDeniedError)
      end

      context 'when the policy grants access to the template path that is served' do
        before do
          allow(execution_context).to receive(:ci_config_access_allowed?)
            .with(config_project: project, file_path: 'templates/test.yml').and_return(true)
        end

        it 'returns the content and instruments the check' do
          expect(fetch_content.content).to eq('test: content')
          expect(logger).to have_received(:instrument).with(:config_component_validate_policy_access)
        end
      end

      context 'without a pipeline policy context' do
        let(:pipeline_policy_context) { nil }

        it 'raises AccessDeniedError' do
          expect { fetch_content }.to raise_error(Gitlab::Access::AccessDeniedError)
        end
      end
    end
  end
end
