# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::DuoWorkflows::DuoAgentPlatformModelMetadataService, feature_category: :duo_agent_platform do
  let_it_be(:group, reload: true) { create(:group) }
  let_it_be(:user) { create(:user) }
  let_it_be(:user_selected_model_identifier) { nil }
  let(:feature_name) { ::Ai::ModelSelection::FeaturesConfigurable.agentic_chat_feature_name }

  subject(:service) do
    described_class.new(
      root_namespace: root_namespace,
      current_user: user,
      user_selected_model_identifier: user_selected_model_identifier,
      feature_name: feature_name
    )
  end

  shared_examples 'returns empty headers' do
    it 'returns empty hash' do
      result = service.execute
      expect(result).to eq({})
    end
  end

  shared_examples 'uses the gitlab default model' do
    it 'uses the gitlab default model' do
      result = service.execute
      expect(result).to include(
        'x-gitlab-agent-platform-model-metadata' => {
          'provider' => 'gitlab',
          'feature_setting' => 'duo_agent_platform_agentic_chat',
          'identifier' => nil
        }.to_json
      )
    end
  end

  # Model definitions in which AI Gateway lists the given models for agentic chat.
  def agentic_chat_model_definitions_response(*model_refs)
    ServiceResponse.success(payload: {
      'models' => [],
      'unit_primitives' => [
        {
          'feature_setting' => 'duo_agent_platform_agentic_chat',
          'default_models' => ['claude_sonnet_4_20250514'],
          'selectable_models' => model_refs
        }
      ]
    })
  end

  describe '#execute' do
    context 'for self-hosted Duo instances' do
      let(:root_namespace) { nil }

      context 'for self hosted duo agent platform' do
        context 'with self-hosted feature setting' do
          let_it_be(:feature_setting) do
            create(:ai_feature_setting,
              feature: :duo_agent_platform_agentic_chat,
              provider: :self_hosted,
              self_hosted_model: create(:ai_self_hosted_model, model: :claude_3))
          end

          it 'returns model metadata headers from existing ModelMetadata class' do
            result = service.execute

            expect(result).to have_key('x-gitlab-agent-platform-model-metadata')

            metadata_json = result['x-gitlab-agent-platform-model-metadata']
            metadata = ::Gitlab::Json::SafeParser.parse(metadata_json)
            expect(metadata).to include(
              'provider' => 'openai',
              'name' => feature_setting.self_hosted_model.model
            )
          end
        end

        context 'when feature setting is not ready (disabled provider)' do
          before do
            create(:ai_feature_setting,
              feature: :duo_agent_platform_agentic_chat,
              provider: :disabled,
              self_hosted_model: nil)
          end

          it_behaves_like 'returns empty headers'
        end
      end
    end

    context 'for cloud-connected self-managed instances' do
      let(:root_namespace) { nil }

      context 'with instance model selection setting (priority 1)' do
        context 'with a model pinned for instance-level model selection' do
          include_context 'with mocked ::Ai::ModelSelection::FetchModelDefinitionsService'

          let_it_be(:pinned_model_identifier) { 'claude-3-7-sonnet-20250219' }
          let_it_be(:instance_setting) do
            create(:instance_model_selection_feature_setting,
              feature: :duo_agent_platform_agentic_chat,
              offered_model_ref: pinned_model_identifier)
          end

          let(:model_definitions_service_response) do
            agentic_chat_model_definitions_response(pinned_model_identifier)
          end

          shared_examples 'uses the pinned instance model' do
            it 'uses the pinned model' do
              result = service.execute

              expect(result).to eq(
                'x-gitlab-agent-platform-model-metadata' => {
                  'provider' => 'gitlab',
                  'feature_setting' => 'duo_agent_platform_agentic_chat',
                  'identifier' => pinned_model_identifier
                }.to_json
              )
            end
          end

          it_behaves_like 'uses the pinned instance model'

          context 'when a valid user_selected_model_identifier is provided' do
            let(:user_selected_model_identifier) { 'claude_sonnet_4_20250514' }

            it_behaves_like 'uses the pinned instance model'
          end

          context 'when an invalid user_selected_model_identifier is provided' do
            let(:user_selected_model_identifier) { 'invalid-model-for-duo-agent-platform' }

            it_behaves_like 'uses the pinned instance model'
          end

          context 'when an empty user_selected_model_identifier is provided' do
            let(:user_selected_model_identifier) { '' }

            it_behaves_like 'uses the pinned instance model'
          end
        end

        context 'with no model pinned for instance-level model selection' do
          let_it_be(:instance_setting) do
            create(:instance_model_selection_feature_setting,
              feature: :duo_agent_platform_agentic_chat,
              offered_model_ref: nil)
          end

          it_behaves_like 'uses the gitlab default model'

          context 'for user model selection' do
            include_context 'with model selections fetch definition service side-effect context'

            before do
              stub_request(:get, fetch_service_endpoint_url)
                .to_return(
                  status: 200,
                  body: model_definitions_response,
                  headers: { 'Content-Type' => 'application/json' }
                )
            end

            context 'when a valid user_selected_model_identifier is provided' do
              let(:user_selected_model_identifier) { 'claude_sonnet_4_20250514' }

              it 'uses the user-selected model' do
                result = service.execute

                expect(result).to include(
                  'x-gitlab-agent-platform-model-metadata' => {
                    'provider' => 'gitlab',
                    'feature_setting' => 'duo_agent_platform_agentic_chat',
                    'identifier' => user_selected_model_identifier
                  }.to_json
                )
              end

              context 'when the response from AI Gateway is not successful' do
                before do
                  stub_request(:get, fetch_service_endpoint_url)
                    .to_return(status: 400)
                end

                it_behaves_like 'uses the gitlab default model'
              end

              context 'when FetchModelDefinitionsService returns nil' do
                before do
                  allow_next_instance_of(::Ai::ModelSelection::FetchModelDefinitionsService) do |fetch_service|
                    allow(fetch_service).to receive(:execute).and_return(nil)
                  end
                end

                it_behaves_like 'uses the gitlab default model'
              end

              context 'when setting is nil' do
                before do
                  allow(::Ai::ModelSelection::InstanceModelSelectionFeatureSetting)
                    .to receive(:find_or_initialize_by_feature)
                    .and_return(nil)
                end

                it_behaves_like 'returns empty headers'
              end
            end

            context 'when an invalid user_selected_model_identifier is provided' do
              let(:user_selected_model_identifier) { 'invalid-model-for-duo-agent-platform' }

              it_behaves_like 'uses the gitlab default model'
            end

            context 'when an empty user_selected_model_identifier is provided' do
              let(:user_selected_model_identifier) { '' }

              it_behaves_like 'uses the gitlab default model'
            end
          end
        end
      end

      context 'when instance setting has no model ref' do
        let_it_be(:instance_setting) do
          create(:instance_model_selection_feature_setting,
            feature: :duo_agent_platform_agentic_chat,
            offered_model_ref: nil
          )
        end

        it 'returns model metadata headers for cloud-connected wit gitlab default model' do
          result = service.execute

          expect(result).to eq(
            'x-gitlab-agent-platform-model-metadata' => {
              'provider' => 'gitlab',
              'feature_setting' => 'duo_agent_platform_agentic_chat',
              'identifier' => nil
            }.to_json
          )
        end
      end

      context 'when no instance setting exists' do
        before do
          allow(::Ai::ModelSelection::InstanceModelSelectionFeatureSetting)
            .to receive(:find_or_initialize_by_feature)
            .and_return(nil)
        end

        it_behaves_like 'returns empty headers'
      end
    end

    context 'for GitLab.com instances', :saas_gitlab_com_subscriptions do
      let(:root_namespace) { group }

      context 'for namesapce model selection' do
        context 'with a model pinned for namespace-level model selection' do
          include_context 'with mocked ::Ai::ModelSelection::FetchModelDefinitionsService'

          let_it_be(:pinned_model_identifier) { 'claude_sonnet_3_7_20250219' }
          let_it_be(:namespace_setting) do
            create(:ai_namespace_feature_setting,
              namespace: group,
              feature: :duo_agent_platform_agentic_chat,
              offered_model_ref: pinned_model_identifier)
          end

          let(:model_definitions_service_response) do
            agentic_chat_model_definitions_response(pinned_model_identifier)
          end

          shared_examples 'uses the pinned model' do
            it 'uses the pinned model' do
              result = service.execute

              expect(result).to include(
                'x-gitlab-agent-platform-model-metadata' => {
                  'provider' => 'gitlab',
                  'feature_setting' => 'duo_agent_platform_agentic_chat',
                  'identifier' => pinned_model_identifier
                }.to_json
              )
            end
          end

          it_behaves_like 'uses the pinned model'

          context 'when a valid user_selected_model_identifier is provided' do
            let(:user_selected_model_identifier) { 'claude_sonnet_4_20250514' }

            it_behaves_like 'uses the pinned model'
          end

          context 'when an invalid user_selected_model_identifier is provided' do
            let(:user_selected_model_identifier) { 'invalid-model-for-duo-agent-platform' }

            it_behaves_like 'uses the pinned model'
          end

          context 'when an empty user_selected_model_identifier is provided' do
            let(:user_selected_model_identifier) { '' }

            it_behaves_like 'uses the pinned model'
          end

          context 'when AI Gateway no longer lists the pinned model' do
            let(:model_definitions_service_response) do
              agentic_chat_model_definitions_response('claude_sonnet_4_20250514')
            end

            it_behaves_like 'uses the gitlab default model'
          end
        end

        context 'with no model is pinned for namespace-level model selection' do
          it_behaves_like 'uses the gitlab default model'

          context 'for user model selection' do
            include_context 'with model selections fetch definition service side-effect context'

            before do
              stub_request(:get, fetch_service_endpoint_url)
                .to_return(
                  status: 200,
                  body: model_definitions_response,
                  headers: { 'Content-Type' => 'application/json' }
                )

              # Stub FeatureSetting.decorate to handle new parameters
              allow(::Gitlab::Graphql::Representation::ModelSelection::FeatureSetting)
                .to receive(:decorate)
                      .and_wrap_original do |_method, settings, **_kwargs|
                # Return decorated settings with selectable_models
                settings.map do |setting|
                  instance_double(
                    Gitlab::Graphql::Representation::ModelSelection::FeatureSetting,
                    feature_setting: setting,
                    selectable_models: [
                      { ref: 'claude_sonnet_3_7_20250219' },
                      { ref: 'claude_sonnet_4_20250514' },
                      { ref: 'claude_sonnet_4_20250514_vertex' }
                    ]
                  )
                end
              end
            end

            context 'when a valid user_selected_model_identifier is provided' do
              let(:user_selected_model_identifier) { 'claude_sonnet_4_20250514' }

              it 'uses the user-selected model' do
                result = service.execute

                expect(result).to include(
                  'x-gitlab-agent-platform-model-metadata' => {
                    'provider' => 'gitlab',
                    'feature_setting' => 'duo_agent_platform_agentic_chat',
                    'identifier' => user_selected_model_identifier
                  }.to_json
                )
              end

              context 'when the response from AI Gateway is not successful' do
                before do
                  stub_request(:get, fetch_service_endpoint_url)
                  .to_return(status: 400)
                end

                it_behaves_like 'uses the gitlab default model'
              end

              context 'when FetchModelDefinitionsService returns nil' do
                before do
                  allow_next_instance_of(::Ai::ModelSelection::FetchModelDefinitionsService) do |fetch_service|
                    allow(fetch_service).to receive(:execute).and_return(nil)
                  end
                end

                it_behaves_like 'uses the gitlab default model'
              end

              context 'when setting is nil' do
                before do
                  allow(::Ai::ModelSelection::NamespaceFeatureSetting)
                    .to receive(:find_or_initialize_by_feature)
                    .and_return(nil)
                end

                it_behaves_like 'returns empty headers'
              end
            end

            context 'when an invalid user_selected_model_identifier is provided' do
              let(:user_selected_model_identifier) { 'invalid-model-for-duo-agent-platform' }

              it_behaves_like 'uses the gitlab default model'
            end

            context 'when an empty user_selected_model_identifier is provided' do
              let(:user_selected_model_identifier) { '' }

              it_behaves_like 'uses the gitlab default model'
            end
          end
        end

        context 'without root_namespace provided' do
          let(:root_namespace) { nil }

          it_behaves_like 'returns empty headers'
        end

        context 'when no namespace setting exists' do
          before do
            allow(::Ai::ModelSelection::NamespaceFeatureSetting)
              .to receive(:find_or_initialize_by_feature)
              .and_return(nil)
          end

          it_behaves_like 'returns empty headers'
        end
      end

      context 'for self managed instances' do
        before do
          stub_saas_features(gitlab_com_subscriptions: false)
        end

        it_behaves_like 'uses the gitlab default model'
      end
    end
  end

  describe 'feature_name parameter' do
    let(:root_namespace) { group }

    context 'when feature_name is provided' do
      let(:feature_name) { :duo_agent_platform }

      it 'uses the provided feature_name when finding feature settings', :saas do
        expect(::Ai::ModelSelection::NamespaceFeatureSetting)
          .to receive(:find_or_initialize_by_feature)
          .with(group, :duo_agent_platform)
          .and_call_original

        service.execute
      end

      it 'uses the provided feature_name when finding instance feature settings' do
        expect(::Ai::ModelSelection::InstanceModelSelectionFeatureSetting)
          .to receive(:find_or_initialize_by_feature)
          .with(:duo_agent_platform)
          .and_call_original

        service.execute
      end

      it 'uses the provided feature_name when finding self-hosted feature settings' do
        expect(::Ai::FeatureSetting)
          .to receive(:find_by_feature)
          .with(:duo_agent_platform)
          .and_call_original

        service.execute
      end
    end

    context 'when feature_name is nil' do
      let(:feature_name) { nil }

      it 'sets feature_name to nil' do
        expect(service.send(:feature_name)).to be_nil
      end
    end

    context 'when feature_name is different from agentic_chat_feature_name' do
      let(:feature_name) { :duo_chat }
      let(:user_selected_model_identifier) { 'claude_sonnet_3_7_20250219' }

      include_context 'with model selections fetch definition service side-effect context'

      before do
        stub_request(:get, fetch_service_endpoint_url)
          .to_return(
            status: 200,
            body: model_definitions_response,
            headers: { 'Content-Type' => 'application/json' }
          )

        create(:ai_namespace_feature_setting,
          namespace: group,
          feature: :duo_chat,
          offered_model_ref: nil)
      end

      it 'does not consider user selected model even when valid' do
        result = service.execute

        expect(result).to include(
          'x-gitlab-agent-platform-model-metadata' => {
            'provider' => 'gitlab',
            'feature_setting' => 'duo_chat',
            'identifier' => nil
          }.to_json
        )
      end
    end

    context 'when feature_name is agentic_chat_feature_name' do
      let(:feature_name) { ::Ai::ModelSelection::FeaturesConfigurable.agentic_chat_feature_name }
      let(:user_selected_model_identifier) { 'claude_sonnet_4_20250514' }

      include_context 'with model selections fetch definition service side-effect context'

      before do
        stub_request(:get, fetch_service_endpoint_url)
          .to_return(
            status: 200,
            body: model_definitions_response,
            headers: { 'Content-Type' => 'application/json' }
          )

        create(:ai_namespace_feature_setting,
          namespace: group,
          feature: :duo_agent_platform,
          offered_model_ref: nil)
      end

      it 'considers user selected model when valid' do
        result = service.execute

        expect(result).to include(
          'x-gitlab-agent-platform-model-metadata' => {
            'provider' => 'gitlab',
            'feature_setting' => 'duo_agent_platform_agentic_chat',
            'identifier' => user_selected_model_identifier
          }.to_json
        )
      end
    end
  end

  describe 'credit-gated models', :saas_gitlab_com_subscriptions do
    include_context 'with model selections fetch definition service side-effect context'

    let(:root_namespace) { group }
    let(:gated_model_identifier) { 'claude_fable_5' }

    let(:model_definitions) do
      {
        'models' => [
          { 'name' => 'Claude Sonnet 4.0', 'identifier' => 'claude_sonnet_4_20250514',
            'requires_paid_credits' => false },
          { 'name' => 'Claude Fable 5', 'identifier' => gated_model_identifier,
            'requires_paid_credits' => true }
        ],
        'unit_primitives' => [
          {
            'feature_setting' => 'duo_agent_platform_agentic_chat',
            'default_model' => 'claude_sonnet_4_20250514',
            'selectable_models' => ['claude_sonnet_4_20250514', gated_model_identifier],
            'beta_models' => []
          }
        ]
      }
    end

    let!(:namespace_setting) do
      create(:ai_namespace_feature_setting,
        namespace: group,
        feature: :duo_agent_platform_agentic_chat,
        model_definitions: model_definitions,
        offered_model_ref: gated_model_identifier)
    end

    before do
      stub_request(:get, fetch_service_endpoint_url)
        .to_return(status: 200, body: model_definitions_response,
          headers: { 'Content-Type' => 'application/json' })
    end

    shared_examples 'uses the credit-gated model' do
      it 'sends the credit-gated model to the AI Gateway' do
        expect(service.execute).to include(
          'x-gitlab-agent-platform-model-metadata' => {
            'provider' => 'gitlab',
            'feature_setting' => 'duo_agent_platform_agentic_chat',
            'identifier' => gated_model_identifier
          }.to_json
        )
      end
    end

    context 'when the namespace is on an active trial without purchased credits' do
      before do
        create(:gitlab_subscription, :active_trial, :ultimate_trial, namespace: group)
      end

      it 'sends no model metadata, so that the AI Gateway falls back to its own default' do
        expect(service.execute).to eq({})
      end

      context 'when the namespace has purchased credits' do
        before do
          create(:gitlab_subscription_add_on_purchase, :gitlab_credits, namespace: group)
        end

        it_behaves_like 'uses the credit-gated model'
      end

      context 'when the feature flag is disabled' do
        before do
          stub_feature_flags(restrict_credit_gated_models_on_trials: false)
        end

        it_behaves_like 'uses the credit-gated model'
      end
    end

    context 'when the namespace is not on a trial' do
      it_behaves_like 'uses the credit-gated model'
    end

    describe '#user_selected_model_credit_gated?' do
      let(:user_selected_model_identifier) { gated_model_identifier }

      context 'when the namespace is on an active trial without purchased credits' do
        before do
          create(:gitlab_subscription, :active_trial, :ultimate_trial, namespace: group)
        end

        it { expect(service.user_selected_model_credit_gated?).to be(true) }

        context 'when the user did not pick a model' do
          let(:user_selected_model_identifier) { nil }

          it { expect(service.user_selected_model_credit_gated?).to be(false) }
        end

        context 'when there is no root namespace' do
          let(:root_namespace) { nil }

          it { expect(service.user_selected_model_credit_gated?).to be(false) }
        end

        context 'when the namespace lookup declines the namespace' do
          let(:root_namespace) { create(:group, parent: group) }

          it 'reports no gating rather than raising on the missing setting' do
            expect(service.user_selected_model_credit_gated?).to be(false)
          end
        end
      end

      context 'when the namespace is not on a trial' do
        it { expect(service.user_selected_model_credit_gated?).to be(false) }
      end
    end
  end

  describe '#user_selected_model_credit_gated? on self-managed instances' do
    include_context 'with model selections fetch definition service side-effect context'

    let(:root_namespace) { nil }
    let(:gated_model_identifier) { 'claude_fable_5' }
    let(:user_selected_model_identifier) { gated_model_identifier }
    let(:license) { build(:license) }

    let(:model_definitions) do
      {
        'models' => [
          { 'name' => 'Claude Sonnet 4.0', 'identifier' => 'claude_sonnet_4_20250514',
            'requires_paid_credits' => false },
          { 'name' => 'Claude Fable 5', 'identifier' => gated_model_identifier,
            'requires_paid_credits' => true }
        ],
        'unit_primitives' => [
          {
            'feature_setting' => 'duo_agent_platform_agentic_chat',
            'default_model' => 'claude_sonnet_4_20250514',
            'selectable_models' => ['claude_sonnet_4_20250514', gated_model_identifier],
            'beta_models' => []
          }
        ]
      }
    end

    let!(:instance_setting) do
      create(:instance_model_selection_feature_setting,
        feature: :duo_agent_platform_agentic_chat,
        offered_model_ref: nil)
    end

    before do
      stub_request(:get, fetch_service_endpoint_url)
        .to_return(status: 200, body: model_definitions_response,
          headers: { 'Content-Type' => 'application/json' })

      allow(License).to receive_messages(
        current: license, has_active_gitlab_credits_add_on?: false, billable_license: nil
      )
      allow(license).to receive(:trial?).and_return(true)
    end

    context 'when the instance is on a trial licence without purchased credits' do
      it { expect(service.user_selected_model_credit_gated?).to be(true) }

      context 'when the instance has purchased credits' do
        before do
          allow(License).to receive_messages(
            has_active_gitlab_credits_add_on?: true, billable_license: license
          )
        end

        it { expect(service.user_selected_model_credit_gated?).to be(false) }
      end

      context 'when the instance uses self-hosted Duo' do
        before do
          create(:ai_feature_setting,
            feature: :duo_agent_platform_agentic_chat,
            provider: :self_hosted,
            self_hosted_model: create(:ai_self_hosted_model, model: :claude_3))
        end

        it 'does not consult model selection, because users cannot pick a model there' do
          expect(::Ai::ModelSelection::UserModelSelection).not_to receive(:for)

          expect(service.user_selected_model_credit_gated?).to be(false)
        end
      end
    end

    context 'when the licence is not a trial' do
      before do
        allow(license).to receive(:trial?).and_return(false)
      end

      it { expect(service.user_selected_model_credit_gated?).to be(false) }
    end
  end
end
