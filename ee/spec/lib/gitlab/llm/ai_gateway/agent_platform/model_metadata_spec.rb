# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Llm::AiGateway::AgentPlatform::ModelMetadata, feature_category: :duo_agent_platform do
  let(:feature_setting) { build(:ai_feature_setting, :duo_agent_platform) }
  let(:service) { described_class.new(feature_setting: feature_setting) }

  describe '#initialize' do
    it 'sets the feature_setting' do
      expect(service.send(:feature_setting)).to eq(feature_setting)
    end

    it 'allows nil feature_setting' do
      service = described_class.new(feature_setting: nil)
      expect(service.send(:feature_setting)).to be_nil
    end
  end

  describe '#execute' do
    subject(:execute) { service.execute }

    it 'creates ModelMetadata with the provided feature_setting' do
      allow_next_instance_of(::Gitlab::Llm::AiGateway::ModelMetadata) do |metadata|
        allow(metadata).to receive(:to_params).and_return({ provider: :gitlab })
      end

      expect(::Gitlab::Llm::AiGateway::ModelMetadata).to receive(:new)
        .with(feature_setting: feature_setting)
        .and_call_original

      execute
    end

    context 'when ModelMetadata returns blank values' do
      where(:blank_value) do
        [nil, {}, [], '', '   ', false]
      end

      with_them do
        before do
          allow_next_instance_of(::Gitlab::Llm::AiGateway::ModelMetadata) do |metadata|
            allow(metadata).to receive(:to_params).and_return(blank_value)
          end
        end

        it 'returns {} for blank values' do
          expect(execute).to eq({})
        end
      end
    end

    context 'when ModelMetadata returns valid data' do
      let(:model_metadata) do
        {
          provider: 'gitlab',
          name: 'claude-3-sonnet',
          identifier: 'claude-3-7-sonnet-20250219'
        }
      end

      before do
        allow_next_instance_of(::Gitlab::Llm::AiGateway::ModelMetadata) do |metadata|
          allow(metadata).to receive(:to_params).and_return(model_metadata)
        end
      end

      it 'returns model metadata header with JSON serialized data' do
        expect(execute).to eq({
          'x-gitlab-agent-platform-model-metadata' => model_metadata.to_json
        })
      end
    end

    context 'with different types of valid model metadata' do
      it 'serializes minimal metadata correctly' do
        test_data = { provider: 'gitlab' }

        allow_next_instance_of(::Gitlab::Llm::AiGateway::ModelMetadata) do |metadata|
          allow(metadata).to receive(:to_params).and_return(test_data)
        end

        expect(execute).to eq({
          'x-gitlab-agent-platform-model-metadata' => test_data.to_json
        })
      end

      it 'serializes complete gitlab metadata correctly' do
        test_data = {
          provider: 'gitlab',
          name: 'claude-3-sonnet',
          identifier: 'claude-3-7-sonnet-20250219',
          feature_setting: 'duo_agent_platform'
        }

        allow_next_instance_of(::Gitlab::Llm::AiGateway::ModelMetadata) do |metadata|
          allow(metadata).to receive(:to_params).and_return(test_data)
        end

        expect(execute).to eq({
          'x-gitlab-agent-platform-model-metadata' => test_data.to_json
        })
      end

      it 'serializes self-hosted metadata correctly' do
        test_data = {
          provider: 'self_hosted',
          name: 'mistral-7b',
          endpoint: 'http://localhost:11434/v1',
          api_key: 'secret-key',
          identifier: 'mistral/mistral-7b'
        }

        allow_next_instance_of(::Gitlab::Llm::AiGateway::ModelMetadata) do |metadata|
          allow(metadata).to receive(:to_params).and_return(test_data)
        end

        expect(execute).to eq({
          'x-gitlab-agent-platform-model-metadata' => test_data.to_json
        })
      end
    end

    context 'when feature_setting is nil' do
      let(:service) { described_class.new(feature_setting: nil) }

      it 'passes nil to ModelMetadata and returns {} when metadata is blank' do
        allow_next_instance_of(::Gitlab::Llm::AiGateway::ModelMetadata) do |metadata|
          allow(metadata).to receive(:to_params).and_return(nil)
        end

        expect(::Gitlab::Llm::AiGateway::ModelMetadata).to receive(:new)
          .with(feature_setting: nil)
          .and_call_original

        result = execute
        expect(result).to eq({})
      end
    end

    context 'with a model selection setting' do
      let(:user) { build_stubbed(:user) }
      let(:group) { build_stubbed(:group) }
      let(:service) { described_class.new(feature_setting: feature_setting, user: user) }
      let(:feature_setting) do
        build(:ai_namespace_feature_setting,
          namespace: group, feature: :review_merge_request_dap, offered_model_ref: offered_model_ref)
      end

      let(:model_definitions_response) do
        ServiceResponse.success(payload: {
          'models' => [],
          'unit_primitives' => [
            {
              'feature_setting' => 'review_merge_request_dap',
              'default_models' => ['claude_sonnet_5_5_vertex'],
              'selectable_models' => %w[claude_sonnet_4_6 claude_sonnet_5_5_vertex],
              'beta_models' => ['claude_beta_model'],
              'dev' => { 'selectable_models' => ['claude_dev_model'] }
            }
          ]
        })
      end

      let(:offered_model_ref) { 'claude_sonnet_4_5_20250929' }

      before do
        allow(::Ai::ModelSelection::ModelDefinitions).to receive(:fetch).with(user)
          .and_return(::Ai::ModelSelection::ModelDefinitions.new(model_definitions_response))
      end

      def sent_identifier
        ::Gitlab::Json::SafeParser.parse(execute[described_class::HEADER_KEY])['identifier']
      end

      context 'when AI Gateway lists the pinned model for the feature' do
        where(:offered_model_ref) do
          %w[claude_sonnet_5_5_vertex claude_sonnet_4_6 claude_beta_model claude_dev_model]
        end

        with_them do
          it 'sends the pinned model' do
            expect(sent_identifier).to eq(offered_model_ref)
          end

          it 'does not log the setting' do
            expect(Gitlab::AppLogger).not_to receive(:info)

            execute
          end
        end
      end

      context 'when AI Gateway no longer lists the pinned model for the feature' do
        it 'sends no identifier, so AI Gateway serves the feature default', :aggregate_failures do
          header = ::Gitlab::Json::SafeParser.parse(execute[described_class::HEADER_KEY])

          expect(header).to eq(
            'provider' => 'gitlab',
            'feature_setting' => 'review_merge_request_dap',
            'identifier' => nil
          )
        end

        it 'logs the setting with its pinned model, so it can be cleaned up' do
          expect(Gitlab::AppLogger).to receive(:info).with(
            message: 'Sending no model identifier for a pinned model that AI Gateway does not list',
            event: 'agent_platform_unlisted_pinned_model',
            feature: 'review_merge_request_dap',
            pinned_model_ref: 'claude_sonnet_4_5_20250929',
            Labkit::Fields::GL_NAMESPACE_ID => group.id,
            ai_component: 'model_selection'
          )

          execute
        end
      end

      context 'when the model definitions are not available' do
        let(:model_definitions_response) { ServiceResponse.error(message: 'Failed to fetch model definitions') }

        it 'sends the pinned model' do
          expect(sent_identifier).to eq('claude_sonnet_4_5_20250929')
        end
      end

      context 'when the model definitions do not have the feature' do
        let(:model_definitions_response) do
          ServiceResponse.success(payload: { 'models' => [], 'unit_primitives' => [] })
        end

        it 'sends the pinned model' do
          expect(sent_identifier).to eq('claude_sonnet_4_5_20250929')
        end
      end

      context 'when the setting uses the GitLab default model' do
        let(:offered_model_ref) { nil }

        it 'sends no identifier without fetching the model definitions', :aggregate_failures do
          expect(sent_identifier).to be_nil
          expect(::Ai::ModelSelection::ModelDefinitions).not_to have_received(:fetch)
        end
      end
    end

    context 'with error handling' do
      context 'when ModelMetadata raises an exception' do
        before do
          allow_next_instance_of(::Gitlab::Llm::AiGateway::ModelMetadata) do |metadata|
            allow(metadata).to receive(:to_params).and_raise(StandardError, 'Model metadata error')
          end
        end

        it 'lets the exception bubble up' do
          expect { execute }.to raise_error(StandardError, 'Model metadata error')
        end
      end

      context 'when ModelMetadata initialization raises an exception' do
        before do
          allow(::Gitlab::Llm::AiGateway::ModelMetadata).to receive(:new)
            .and_raise(ArgumentError, 'Invalid feature setting')
        end

        it 'lets the exception bubble up' do
          expect { execute }.to raise_error(ArgumentError, 'Invalid feature setting')
        end
      end

      context 'when JSON serialization fails' do
        let(:invalid_data) { instance_double(Object, present?: true) }

        before do
          allow(invalid_data).to receive(:to_json).and_raise(JSON::GeneratorError, 'Invalid JSON')

          allow_next_instance_of(::Gitlab::Llm::AiGateway::ModelMetadata) do |metadata|
            allow(metadata).to receive(:to_params).and_return(invalid_data)
          end
        end

        it 'lets the JSON error bubble up' do
          expect { execute }.to raise_error(JSON::GeneratorError, 'Invalid JSON')
        end
      end
    end
  end

  describe 'return value consistency' do
    it 'returns a hash with or without metadata' do
      # Test with valid data
      allow_next_instance_of(::Gitlab::Llm::AiGateway::ModelMetadata) do |metadata|
        allow(metadata).to receive(:to_params).and_return({ provider: :gitlab })
      end

      result = service.execute
      expect(result).to be_a(Hash)

      # Test with empty data
      allow_next_instance_of(::Gitlab::Llm::AiGateway::ModelMetadata) do |metadata|
        allow(metadata).to receive(:to_params).and_return(nil)
      end

      result = service.execute
      expect(result).to eq({})
    end

    it 'returns expected header key when data is present' do
      allow_next_instance_of(::Gitlab::Llm::AiGateway::ModelMetadata) do |metadata|
        allow(metadata).to receive(:to_params).and_return({ provider: :gitlab })
      end

      result = service.execute
      expect(result.keys).to eq(['x-gitlab-agent-platform-model-metadata'])
      expect(result['x-gitlab-agent-platform-model-metadata']).to be_a(String)
      parsed_result = ::Gitlab::Json::SafeParser.parse(result['x-gitlab-agent-platform-model-metadata'])
      expect(parsed_result).to eq({ 'provider' => 'gitlab' })
    end
  end

  describe 'integration behavior' do
    it 'flows through the complete happy path' do
      expected_metadata = {
        provider: 'gitlab',
        identifier: 'claude-3-7-sonnet-20250219',
        feature_setting: 'duo_agent_platform'
      }

      expect(::Gitlab::Llm::AiGateway::ModelMetadata).to receive(:new)
        .with(feature_setting: feature_setting)
        .and_return(instance_double(
          ::Gitlab::Llm::AiGateway::ModelMetadata,
          to_params: expected_metadata
        ))

      result = service.execute

      expect(result).to eq({
        'x-gitlab-agent-platform-model-metadata' => expected_metadata.to_json
      })

      parsed_result = ::Gitlab::Json::SafeParser.parse(result['x-gitlab-agent-platform-model-metadata'])
      expect(parsed_result).to eq(expected_metadata.deep_stringify_keys)
    end
  end
end
