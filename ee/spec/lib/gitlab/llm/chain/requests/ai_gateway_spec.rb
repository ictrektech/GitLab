# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Llm::Chain::Requests::AiGateway, feature_category: :chat_engine do
  let_it_be(:user) { create(:user) }
  let(:tracking_context) { { action: 'chat', request_id: 'uuid' } }

  subject(:instance) do
    described_class.new(user, unit_primitive_name: :duo_classic_chat, tracking_context: tracking_context)
  end

  describe 'initializer' do
    it 'initializes the AI Gateway client' do
      expect(instance.ai_client.class).to eq(::Gitlab::Llm::AiGateway::Client)
    end

    context 'when alternative service name is passed' do
      it 'creates ai gateway client with different service name' do
        expect(::Gitlab::Llm::AiGateway::Client).to receive(:new).with(
          user,
          unit_primitive_name: :alternative,
          tracking_context: tracking_context,
          governing_namespace_id: nil
        )

        described_class.new(user, unit_primitive_name: :alternative, tracking_context: tracking_context)
      end
    end

    context 'when duo chat is self-hosted' do
      let_it_be(:feature_setting) { create(:ai_feature_setting, feature: :duo_chat, provider: :self_hosted) }

      it 'creates ai gateway client with duo_classic_chat service name' do
        expect(::Gitlab::Llm::AiGateway::Client).to receive(:new).with(
          user,
          unit_primitive_name: :duo_classic_chat,
          tracking_context: tracking_context,
          governing_namespace_id: nil
        )

        described_class.new(user, unit_primitive_name: :duo_classic_chat, tracking_context: tracking_context)
      end
    end
  end

  describe '#request' do
    let(:logger) { instance_double(Gitlab::Llm::Logger) }
    let(:ai_client) { double }
    let(:endpoint) { "/v2/prompts/chat/#{unit_primitive}" }
    let(:url) { "#{::Gitlab::AiGateway.url}#{endpoint}" }
    let(:model) { nil }
    let(:prompt_version) { "2.0.0" }
    let(:user_prompt) { "some user request" }
    let(:options) { { model: model } }
    let(:prompt) { { prompt: user_prompt, options: options } }
    let(:unit_primitive) { :test }

    let(:body) do
      {
        stream: true,
        inputs: nil,
        model_metadata: {
          feature_setting: "duo_chat",
          identifier: nil,
          provider: "gitlab"
        },
        prompt_version: "^1.0.0"
      }
    end

    let(:response) { 'Hello World' }

    # `response` as the gateway streams it: a PromptResponse frame on v2, so the
    # parser runs. The flag-disabled context overrides it with v1's bare text.
    let(:streamed_body) { %({"content":#{Gitlab::Json.dump(response)}}\n) }

    # The /v2/prompts endpoint streams newline-delimited PromptResponse objects.
    let(:frames) do
      <<~FRAMES
        {"content":"Hi "}
        {"content":"John!"}
      FRAMES
    end

    let(:usage_frames) do
      <<~FRAMES
        {"content":"Hi "}
        {"content":"John!","usage":{"claude-sonnet-4-5":{"input_tokens":10,"output_tokens":20}}}
      FRAMES
    end

    subject(:request) { instance.request(prompt, unit_primitive: unit_primitive) }

    before do
      allow(Gitlab::Llm::Logger).to receive(:build).and_return(logger)
      allow(logger).to receive(:conditional_info)
      allow(::Gitlab::Llm::AiGateway::Client).to receive(:new).and_return(ai_client)
    end

    shared_examples 'performing request to the AI Gateway' do
      it 'returns the response from AI Gateway' do
        expect(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything)
          .and_yield(streamed_body).and_return(streamed_body)

        expect(request).to eq(response)
      end
    end

    it 'logs the request and response' do
      expect(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything)
        .and_yield(streamed_body).and_return(streamed_body)
      expect(logger).to receive(:conditional_info).with(
        user,
        a_hash_including(
          message: "Made request to AI Client",
          klass: described_class.to_s,
          prompt: user_prompt,
          response_from_llm: response
        ))

      request
    end

    it 'logs the token usage the streamed frames report, one entry for each model' do
      expect(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything)
        .and_yield(usage_frames).and_return(usage_frames)

      request

      expect(logger).to have_received(:conditional_info).with(
        user,
        a_hash_including(
          message: "Made request to AI Client",
          response_from_llm: 'Hi John!',
          token_usage: [{ model_name: 'claude-sonnet-4-5', input_tokens: 10, output_tokens: 20 }]
        ))
    end

    it 'logs no token usage when no streamed frame reports it' do
      expect(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything)
        .and_yield(frames).and_return(frames)

      request

      expect(logger).not_to have_received(:conditional_info).with(user, a_hash_including(:token_usage))
    end

    it 'calls the AI Gateway streaming endpoint and yields the content of each frame' do
      expect(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything).and_yield(frames)
        .and_return(frames)

      expect { |b| instance.request(prompt, unit_primitive: unit_primitive, &b) }
        .to yield_successive_args('Hi ', 'John!')
    end

    it 'returns the answer text rather than the frames that carried it' do
      expect(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything).and_yield(frames)
        .and_return(frames)

      expect(request).to eq('Hi John!')
    end

    it 'returns empty text rather than the frames when no frame carries content' do
      frames_without_content = %(not json at all\n{"usage":{"model":{"input_tokens":10,"output_tokens":20}}}\n)
      allow(logger).to receive(:warn)
      expect(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything)
        .and_yield(frames_without_content).and_return(frames_without_content)

      expect(request).to eq('')
    end

    it 'reassembles a frame the gateway split across two fragments' do
      expect(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything)
        .and_yield('{"content":"Hi ').and_yield(%("}\n)).and_return(frames)

      expect { |b| instance.request(prompt, unit_primitive: unit_primitive, &b) }.to yield_with_args('Hi ')
    end

    it 'yields a final frame that arrived without its delimiter' do
      expect(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything)
        .and_yield(frames.chomp).and_return(frames.chomp)

      expect { |b| instance.request(prompt, unit_primitive: unit_primitive, &b) }
        .to yield_successive_args('Hi ', 'John!')
    end

    it 'propagates a forbidden response rather than answering with a partial frame' do
      expect(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything)
        .and_yield('{"content":"Hi ').and_raise(::Gitlab::AiGateway::ForbiddenError)

      expect { request }.to raise_error(::Gitlab::AiGateway::ForbiddenError)
    end

    it 'propagates an unreachable gateway' do
      expect(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything)
        .and_raise(::Gitlab::Llm::AiGateway::Client::ConnectionError)

      expect { request }.to raise_error(::Gitlab::Llm::AiGateway::Client::ConnectionError)
    end

    it_behaves_like 'performing request to the AI Gateway'

    it_behaves_like 'tracks events for AI requests', 4, 2, klass: 'Gitlab::Llm::Anthropic::Client' do
      before do
        allow(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything)
          .and_yield(streamed_body).and_return(streamed_body)
      end
    end

    context 'when other model is passed' do
      let(:model) { ::Gitlab::Llm::Concerns::AvailableModels::VERTEX_MODEL_CHAT }

      it_behaves_like 'performing request to the AI Gateway'
      it_behaves_like 'tracks events for AI requests', 4, 2, klass: 'Gitlab::Llm::VertexAi::Client' do
        before do
          allow(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything)
            .and_yield(streamed_body).and_return(streamed_body)
        end
      end
    end

    context 'when invalid model is passed' do
      let(:model) { 'test' }

      it 'returns nothing' do
        expect(ai_client).not_to receive(:stream)

        expect(request).to be_nil
      end
    end

    context 'when unit_primitive is nil' do
      let(:unit_primitive) { nil }

      it 'raises ArgumentError' do
        expect { request }.to raise_error(ArgumentError, "unit_primitive cannot be nil")
      end
    end

    context 'when ai_prompts_v2 feature flag is disabled' do
      let(:endpoint) { "#{described_class::BASE_PROMPTS_CHAT_ENDPOINT}/#{unit_primitive}" }
      let(:streamed_body) { response }

      before do
        stub_feature_flags(ai_prompts_v2: false)
      end

      it_behaves_like 'performing request to the AI Gateway'

      it 'calls the AI Gateway streaming endpoint and yields response without stripping it' do
        expect(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything).and_yield(response)
          .and_return(response)

        expect { |b| instance.request(prompt, unit_primitive: unit_primitive, &b) }.to yield_with_args(response)
      end

      it 'leaves a v1 answer that happens to look like a frame alone' do
        expect(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything).and_yield(frames)
          .and_return(frames)

        yielded = []
        answer = instance.request(prompt, unit_primitive: unit_primitive) { |content| yielded << content }

        expect(yielded).to eq([frames])
        expect(answer).to eq(frames)
      end

      it 'builds no parser, and answers with the client body' do
        expect(Gitlab::Llm::Chain::Requests::PromptResponseParser).not_to receive(:new)
        expect(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything).and_yield(response)
          .and_return(response)

        expect(request).to eq(response)
      end

      it 'logs no token usage for a v1 answer that happens to look like a frame reporting it' do
        expect(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything)
          .and_yield(usage_frames).and_return(usage_frames)

        request

        expect(logger).to have_received(:conditional_info)
          .with(user, a_hash_including(message: "Made request to AI Client", response_from_llm: usage_frames))
        expect(logger).not_to have_received(:conditional_info).with(user, a_hash_including(:token_usage))
      end
    end

    context 'when ai_prompts_v2 is enabled for this user only' do
      before do
        stub_feature_flags(ai_prompts_v2: user)
      end

      it_behaves_like 'performing request to the AI Gateway'
    end

    context 'when user amazon q is connected' do
      let_it_be(:add_on_purchase) { create(:gitlab_subscription_add_on_purchase, :duo_amazon_q) }

      let(:unit_primitive) { :explain_code }
      let(:endpoint) { "#{described_class::BASE_PROMPTS_CHAT_V2_ENDPOINT}/#{unit_primitive}" }
      let(:inputs) { { field: :test_field } }

      let(:options) do
        {
          inputs: inputs,
          prompt_version: '2.0.0'
        }
      end

      let(:body) do
        {
          stream: true,
          inputs: inputs,
          model_metadata: {
            provider: :amazon_q,
            name: :amazon_q,
            role_arn: 'role-arn'
          },
          prompt_version: "^1.0.0"
        }
      end

      before do
        stub_licensed_features(amazon_q: true)
        stub_current_organization(user.organization)
        Ai::Setting.for_organization(user.organization).update!(amazon_q_ready: true, amazon_q_role_arn: 'role-arn')
      end

      it_behaves_like 'performing request to the AI Gateway'
    end

    context 'when request is sent to chat tools implemented via agents' do
      let(:options) do
        {
          inputs: inputs,
          prompt_version: prompt_version
        }
      end

      let(:body) do
        {
          stream: true,
          inputs: inputs,
          model_metadata: model_metadata,
          prompt_version: "^1.0.0"
        }
      end

      let(:prompt) { { prompt: user_prompt, options: options } }
      let(:inputs) { { field: :test_field } }

      let(:unit_primitive) { :test }
      let(:endpoint) { "#{described_class::BASE_PROMPTS_CHAT_V2_ENDPOINT}/#{unit_primitive}" }
      let(:model_metadata) do
        { api_key: "token", endpoint: "http://localhost:11434/v1", name: "mistral", provider: :openai, identifier: 'provider/some-model' }
      end

      before_all do
        create(:cloud_connector_keys)
      end

      context 'with a unit primitive corresponding a feature setting' do
        let_it_be(:model_api_key) { 'explain_code_token_model' }
        let_it_be(:model_identifier) { 'provider/some-cool-model' }
        let_it_be(:model_endpoint) { 'http://example.explain_code.dev' }
        let_it_be(:self_hosted_model) do
          create(:ai_self_hosted_model, name: 'explain_code', endpoint: model_endpoint, api_token: model_api_key,
            identifier: model_identifier)
        end

        let_it_be(:self_hosted_sub_feature_setting) do
          create(
            :ai_feature_setting,
            feature: :duo_chat_explain_code,
            provider: :self_hosted,
            self_hosted_model: self_hosted_model
          )
        end

        let(:sub_feature_setting) { self_hosted_sub_feature_setting }

        let(:unit_primitive) { :explain_code }

        let(:endpoint) { "#{described_class::BASE_PROMPTS_CHAT_V2_ENDPOINT}/#{unit_primitive}" }

        let(:model_metadata) do
          { api_key: model_api_key, endpoint: model_endpoint, name: "mistral", provider: :openai,
            identifier: model_identifier }
        end

        it 'fetches the right prompt version' do
          expect(Gitlab::Llm::PromptVersions).to receive(:version_for_prompt).with('chat/explain_code', 'mistral')
                                                                             .and_call_original

          expect(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything)
            .and_yield(streamed_body).and_return(streamed_body)
          expect(request).to eq(response)
        end

        # Without the feature setting, the token is minted from a lookup on the unit primitive,
        # which misses the self-hosted setting and makes the gateway reject the request.
        it 'passes the resolved feature setting so the token is minted for it' do
          expect(ai_client).to receive(:stream)
            .with(hash_including(feature_setting: self_hosted_sub_feature_setting))
            .and_yield(streamed_body).and_return(streamed_body)

          expect(request).to eq(response)
        end

        context 'if feature setting is set to vendored' do
          let(:unit_primitive) { :fix_code }

          let!(:sub_feature_setting) do
            create(
              :ai_feature_setting,
              feature: :duo_chat_fix_code,
              provider: :vendored,
              self_hosted_model: self_hosted_model
            )
          end

          let(:body) do
            {
              stream: true,
              inputs: inputs,
              prompt_version: "2.0.0",
              model_metadata: {
                feature_setting: 'duo_chat_fix_code',
                identifier: nil,
                provider: 'gitlab'
              }
            }
          end

          it 'uses the passed prompt version' do
            expect(ai_client).to receive(:stream).with(url: url, body: body, feature_setting: anything)
              .and_yield(streamed_body).and_return(streamed_body)
            expect(request).to eq(response)
          end
        end
      end

      context 'with a unit primitive that has no feature setting of its own' do
        let_it_be(:general_chat_setting) do
          create(:ai_feature_setting, feature: :duo_chat, provider: :self_hosted)
        end

        let(:unit_primitive) { :merge_request_reader }

        # Reader tools have no sub-feature setting of their own, so this resolves through the
        # General Chat fallback -- the path that skipped self-signing and returned 401 for
        # air-gapped self-hosted instances.
        it 'falls back to the General Chat setting so the token is minted for it' do
          expect(ai_client).to receive(:stream)
            .with(hash_including(feature_setting: general_chat_setting))
            .and_yield(streamed_body).and_return(streamed_body)

          expect(request).to eq(response)
        end

        context 'when ai_prompts_v2 feature flag is disabled' do
          before do
            stub_feature_flags(ai_prompts_v2: false)
          end

          it 'falls back to the General Chat setting so the token is minted for it' do
            expect(ai_client).to receive(:stream)
              .with(hash_including(feature_setting: general_chat_setting))
              .and_return(response)

            expect(request).to eq(response)
          end
        end
      end
    end

    context 'when instance is SAAS and a root_namespace is passed', :saas do
      let_it_be(:root_namespace) { create(:group) }
      let(:tracking_context) { { action: 'chat', request_id: 'uuid' } }
      let(:user_prompt) { "Some prompt" }
      let(:response) { 'response from llm' }
      let(:logger) { instance_double(Gitlab::Llm::Logger) }
      let(:ai_client) { double }

      before_all do
        root_namespace.add_developer(user)
      end

      before do
        allow(Gitlab::Llm::Logger).to receive(:build).and_return(logger)
        allow(logger).to receive(:conditional_info)
        allow(::Gitlab::Llm::AiGateway::Client).to receive(:new).and_return(ai_client)
      end

      context 'with namespace model selection', :saas_gitlab_com_subscriptions do
        context 'when using agent prompt with namespace model switching' do
          let(:unit_primitive) { :explain_code }
          let(:model_ref) { 'claude-3-7-sonnet-20250219' }
          let(:prompt) do
            {
              options: {
                inputs: { a: 1 }
              }
            }
          end

          before do
            create(:ai_namespace_feature_setting, namespace: root_namespace,
              feature: :"duo_chat_#{unit_primitive}", offered_model_ref: model_ref)
          end

          it 'sends model_metadata with identifier and feature_setting' do
            url = "#{::Gitlab::AiGateway.url}#{described_class::BASE_PROMPTS_CHAT_V2_ENDPOINT}/#{unit_primitive}"

            expect(ai_client).to receive(:stream).with(
              hash_including(
                url: url,
                body: hash_including(
                  inputs: { a: 1 },
                  model_metadata: {
                    provider: 'gitlab',
                    feature_setting: 'duo_chat_explain_code',
                    identifier: model_ref
                  },
                  prompt_version: a_kind_of(String)
                )
              )
            ).and_yield(streamed_body).and_return(streamed_body)

            gateway = described_class.new(
              user,
              unit_primitive_name: :duo_classic_chat,
              root_namespace: root_namespace,
              tracking_context: tracking_context)
            expect(gateway.request(prompt, unit_primitive: unit_primitive)).to eq(response)
          end
        end
      end
    end
  end
end
