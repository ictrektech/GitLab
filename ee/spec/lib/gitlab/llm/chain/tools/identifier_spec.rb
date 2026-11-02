# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Llm::Chain::Tools::Identifier, feature_category: :chat_engine do
  let(:context) do
    instance_double(
      Gitlab::Llm::Chain::GitlabContext,
      request_id: '1234',
      container: nil,
      resource: nil,
      current_user: build_stubbed(:user)
    )
  end

  let(:dummy_class) do
    Class.new(described_class) do
      def resource_name
        'project'
      end

      def passed_content(_json)
        "Extracted content"
      end
    end
  end

  subject(:tool) { dummy_class.new(context: context, options: { suggestions: "" }) }

  describe '#perform' do
    context 'when the LLM response contains malformed JSON' do
      let(:invalid_json) { %(```json\n{"ResourceIdentifierType": "url", "ResourceIdentifier": "http://example.com" \n```) }

      it 'rescues JSON::ParserError, adds suggestion, and retries', :aggregate_failures do
        expect(tool).to receive(:request).exactly(described_class::MAX_RETRIES).times.and_return(invalid_json)

        tool.perform

        expect(tool.options[:suggestions]).to include("Observation: JSON has an invalid format. Please retry")
      end
    end

    context 'when the LLM response contains well-formed JSON' do
      let(:valid_json) { %(```json\n{"ResourceIdentifierType": "url", "ResourceIdentifier": "http://example.com"}\n```) }
      let(:resource) { build_stubbed(:project) }

      before do
        allow(tool).to receive(:identify_resource).with('url', 'http://example.com').and_return(resource)
        allow(Gitlab::Llm::Chain::Utils::ChatAuthorizer).to receive(:resource)
          .with(resource: resource, user: context.current_user, context: context)
          .and_return(instance_double(Gitlab::Llm::Utils::Authorizer::Response, allowed?: true))
      end

      it 'returns a successful answer' do
        expect(tool).to receive(:request).once.and_return(valid_json)
        expect(context).to receive(:resource=).with(resource)
        answer = tool.perform

        expect(answer).to be_a(Gitlab::Llm::Chain::Answer)
        expect(answer.status).to eq(:ok)
        expect(answer.content).to eq("Extracted content")
      end
    end
  end

  # A reader tool driven through a real Requests::AiGateway, not a stubbed
  # #request, so its fenced JSON arrives in frames split across fragments.
  describe '#perform against a streaming AI Gateway' do
    let_it_be(:current_user) { create(:user) }
    let_it_be(:identified_project) { create(:project) }

    let(:ai_client) { instance_double(Gitlab::Llm::AiGateway::Client) }
    let(:logger) { instance_double(Gitlab::Llm::Logger) }

    let(:ai_request) do
      Gitlab::Llm::Chain::Requests::AiGateway.new(current_user, unit_primitive_name: :duo_classic_chat)
    end

    let(:streaming_context) do
      instance_double(
        Gitlab::Llm::Chain::GitlabContext,
        request_id: '1234',
        container: nil,
        resource: nil,
        current_user: current_user,
        ai_request: ai_request
      )
    end

    let(:streaming_tool) do
      Class.new(described_class) do
        def resource_name
          'project'
        end

        def passed_content(_json)
          'Extracted content'
        end

        def prompt
          { prompt: 'identify the resource', options: {} }
        end

        private

        def unit_primitive
          :issue_reader
        end
      end.new(context: streaming_context, options: { suggestions: '' })
    end

    let(:llm_answer) do
      <<~ANSWER
        ```json
        {"ResourceIdentifierType": "url", "ResourceIdentifier": "http://example.com"}
        ```
      ANSWER
    end

    let(:frame) { %({"content":#{Gitlab::Json.dump(llm_answer)}}\n) }

    before do
      # Driving a real Requests::AiGateway reaches the real logger, which the
      # sibling requests/ai_gateway_spec stubs for the same reason: these
      # examples assert the answer, not what was logged.
      allow(Gitlab::Llm::Logger).to receive(:build).and_return(logger)
      allow(logger).to receive(:conditional_info)
      allow(Gitlab::Llm::AiGateway::Client).to receive(:new).and_return(ai_client)
      allow(streaming_tool).to receive(:identify_resource).with('url', 'http://example.com')
        .and_return(identified_project)
      allow(Gitlab::Llm::Chain::Utils::ChatAuthorizer).to receive(:resource)
        .with(resource: identified_project, user: current_user, context: streaming_context)
        .and_return(instance_double(Gitlab::Llm::Utils::Authorizer::Response, allowed?: true))
      allow(streaming_context).to receive(:resource=)
    end

    it 'reads the answer out of the frames, without a parse error or a retry', :aggregate_failures do
      # One frame, cut mid content the way BufferedIo cuts it.
      expect(ai_client).to receive(:stream).once
        .and_yield(frame[0, 24]).and_yield(frame[24..]).and_return(frame)

      answer = streaming_tool.perform

      expect(answer.status).to eq(:ok)
      expect(answer.content).to eq('Extracted content')
      expect(streaming_tool.options[:suggestions]).to eq('')
    end

    context 'when ai_prompts_v2 is disabled' do
      before do
        stub_feature_flags(ai_prompts_v2: false)
      end

      it 'passes the v1 answer through untouched', :aggregate_failures do
        expect(ai_client).to receive(:stream).once.and_yield(llm_answer).and_return(llm_answer)

        answer = streaming_tool.perform

        expect(answer.status).to eq(:ok)
        expect(answer.content).to eq('Extracted content')
      end
    end
  end
end
