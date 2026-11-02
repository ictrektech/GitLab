# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Llm::Chain::Tools::SlashCommandTool, feature_category: :chat_engine do
  let_it_be(:user) { create(:user) }

  let(:ai_request_double) { instance_double(Gitlab::Llm::Chain::Requests::AiGateway) }
  let_it_be_with_reload(:group) { create(:group) }
  let(:resource) { group }
  let(:context) do
    Gitlab::Llm::Chain::GitlabContext.new(
      current_user: user, container: nil, resource: resource, ai_request: ai_request_double
    )
  end

  subject(:tool) do
    Class.new(described_class) do
      def authorize
        true
      end
    end.new(context: context, options: {})
  end

  it 'raises not implemented error without ai_request implemented' do
    expect { tool.execute }.to raise_error(NotImplementedError)
  end

  it 'raises not implemented error without allow_blank_message implemented' do
    expect { tool.send(:allow_blank_message?) }.to raise_error(NotImplementedError)
  end

  describe 'usage event tracking' do
    subject(:tool) do
      Class.new(described_class) do
        def authorize
          true
        end

        private

        def allow_blank_message?
          true
        end
      end.new(context: context, options: {})
    end

    it 'does not track an event when usage_event_name is not declared' do
      allow(tool).to receive(:request).and_return('response')

      expect { tool.execute }
        .not_to trigger_internal_events('fix_code', 'refactor_code', 'write_tests', 'explain_code')
    end
  end

  # A slash command driven through a real Requests::AiGateway rather than a
  # stubbed #request. The tool assigns what #request returns straight into
  # Answer#content, so on /v2/prompts the user read the raw NDJSON at status :ok.
  describe '#execute against a streaming AI Gateway' do
    let(:ai_client) { instance_double(Gitlab::Llm::AiGateway::Client) }
    let(:logger) { instance_double(Gitlab::Llm::Logger) }

    let(:ai_request) do
      Gitlab::Llm::Chain::Requests::AiGateway.new(user, unit_primitive_name: :duo_classic_chat)
    end

    let(:streaming_context) do
      Gitlab::Llm::Chain::GitlabContext.new(
        current_user: user, container: nil, resource: resource, ai_request: ai_request
      )
    end

    let(:frames) do
      <<~FRAMES
        {"content":"The change "}
        {"content":"renames a method."}
      FRAMES
    end

    subject(:tool) do
      Class.new(described_class) do
        def authorize
          true
        end

        def prompt
          { prompt: 'explain this', options: {} }
        end

        private

        def allow_blank_message?
          true
        end

        def unit_primitive
          :explain_code
        end

        # SlashCommandTool leaves this NotImplementedError so every child names
        # its own service; the real executors answer with the shared request
        # object, as ExplainCode::Executor does.
        def ai_request
          context.ai_request
        end
      end.new(context: streaming_context, options: {})
    end

    before do
      # Driving a real Requests::AiGateway reaches the real logger, which the
      # sibling requests/ai_gateway_spec stubs for the same reason: these
      # examples assert the answer, not what was logged.
      allow(Gitlab::Llm::Logger).to receive(:build).and_return(logger)
      allow(logger).to receive(:conditional_info)
      allow(Gitlab::Llm::AiGateway::Client).to receive(:new).and_return(ai_client)
    end

    it 'answers with the text the frames carried, not the frames', :aggregate_failures do
      expect(ai_client).to receive(:stream).once.and_yield(frames).and_return(frames)

      answer = tool.execute

      expect(answer.status).to eq(:ok)
      expect(answer.content).to eq('The change renames a method.')
    end

    context 'when ai_prompts_v2 is disabled' do
      let(:v1_answer) { 'The change renames a method.' }

      before do
        stub_feature_flags(ai_prompts_v2: false)
      end

      it 'answers with the v1 body unchanged' do
        expect(ai_client).to receive(:stream).once.and_yield(v1_answer).and_return(v1_answer)

        expect(tool.execute.content).to eq(v1_answer)
      end
    end
  end
end
