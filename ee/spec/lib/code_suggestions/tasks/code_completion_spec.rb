# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CodeSuggestions::Tasks::CodeCompletion, feature_category: :code_suggestions do
  let(:endpoint_path) { 'v4/code/suggestions' }
  let(:expected_unit_primitive_name) { :complete_code }
  let(:expected_feature_name) { :code_suggestions }

  let(:current_file) do
    {
      'file_name' => 'test.py',
      'content_above_cursor' => 'some content_above_cursor',
      'content_below_cursor' => 'some content_below_cursor'
    }.with_indifferent_access
  end

  let(:params) { { current_file: current_file } }

  let(:unsafe_params) do
    {
      'current_file' => current_file,
      'telemetry' => [{ 'model_engine' => 'telemetry-model-engine' }]
    }.with_indifferent_access
  end

  let_it_be(:current_user) { create(:user) }

  let(:task) do
    described_class.new(
      params: params,
      unsafe_passthrough_params: unsafe_params,
      current_user: current_user
    )
  end

  let(:code_editor_completion_component) do
    {
      type: 'code_editor_completion',
      payload: {
        file_name: 'test.py',
        content_above_cursor: 'some content_above_cursor',
        content_below_cursor: 'some content_below_cursor',
        language_identifier: 'Python',
        stream: false
      }
    }
  end

  let(:body_without_model_metadata) do
    { prompt_components: [code_editor_completion_component] }.with_indifferent_access
  end

  def body_with_model_metadata(model_metadata)
    { prompt_components: [code_editor_completion_component], model_metadata: model_metadata }.with_indifferent_access
  end

  describe 'on GitLab self-managed with the GitLab-default model' do
    before do
      allow(Gitlab).to receive(:org_or_com?).and_return(false)
      stub_saas_features(gitlab_com_subscriptions: false)
    end

    it_behaves_like 'code suggestion task' do
      let(:expected_body) { body_without_model_metadata }
    end
  end

  describe 'on GitLab self-managed with a model pinned to a remapped deprecated model' do
    let_it_be(:instance_feature_setting) do
      create(:instance_model_selection_feature_setting,
        feature: :code_completions,
        offered_model_ref: 'codestral_2501_vertex')
    end

    before do
      allow(Gitlab).to receive(:org_or_com?).and_return(false)
      stub_saas_features(gitlab_com_subscriptions: false)
    end

    it_behaves_like 'code suggestion task' do
      let(:expected_body) do
        body_with_model_metadata(
          provider: 'gitlab',
          feature_setting: 'code_completions',
          identifier: 'codestral_2508_vertex'
        )
      end
    end
  end

  describe 'model switching', :saas do
    let_it_be(:group) { create(:group) }
    let_it_be(:project) { create(:project, group: group) }

    let(:params) { { current_file: current_file, project: project } }

    before_all do
      group.add_developer(current_user)
    end

    before do
      stub_saas_features(gitlab_com_subscriptions: true)
    end

    context 'when the namespace feature setting is set to GitLab Default' do
      let_it_be(:namespace_feature_setting) do
        create(:ai_namespace_feature_setting, feature: :code_completions, offered_model_ref: '', namespace: group)
      end

      it_behaves_like 'code suggestion task' do
        let(:expected_body) { body_without_model_metadata }
      end
    end

    context 'when the namespace feature setting pins a model' do
      let_it_be(:namespace_feature_setting) do
        create(:ai_namespace_feature_setting,
          feature: :code_completions,
          offered_model_ref: 'claude_sonnet_3_7_20250219',
          namespace: group
        )
      end

      it_behaves_like 'code suggestion task' do
        let(:expected_body) do
          body_with_model_metadata(
            provider: 'gitlab',
            feature_setting: 'code_completions',
            identifier: 'claude_sonnet_3_7_20250219'
          )
        end
      end
    end
  end

  describe 'self-hosted model' do
    let_it_be(:ai_self_hosted_model) do
      create(:ai_self_hosted_model, model: :codellama, name: 'whatever')
    end

    context 'on setting the provider as `self_hosted`' do
      let_it_be(:ai_feature_setting) do
        create(
          :ai_feature_setting,
          feature: :code_completions,
          self_hosted_model: ai_self_hosted_model,
          provider: :self_hosted
        )
      end

      it_behaves_like 'code suggestion task' do
        let(:expected_body) do
          body_with_model_metadata(
            provider: 'openai',
            name: 'codellama',
            endpoint: 'http://localhost:11434/v1',
            api_key: 'token',
            identifier: 'provider/some-model'
          )
        end
      end
    end

    context 'on setting the provider as `disabled`' do
      let_it_be(:ai_feature_setting) do
        create(
          :ai_feature_setting,
          feature: :code_completions,
          self_hosted_model: ai_self_hosted_model,
          provider: :disabled
        )
      end

      it 'is a disabled task' do
        expect(task.feature_disabled?).to be(true)
      end
    end

    context 'when code_completions is vendored' do
      let_it_be(:ai_feature_setting) do
        create(:ai_feature_setting, :code_completions, provider: :vendored)
      end

      context 'and the instance level is set to GitLab Default' do
        it_behaves_like 'code suggestion task' do
          let(:expected_body) { body_without_model_metadata }
        end
      end

      context 'and a vendored model is pinned at the instance level' do
        before do
          create(:instance_model_selection_feature_setting,
            feature: :code_completions,
            offered_model_ref: 'claude_sonnet_3_5'
          )
        end

        it_behaves_like 'code suggestion task' do
          let(:expected_body) do
            body_with_model_metadata(
              provider: 'gitlab',
              feature_setting: 'code_completions',
              identifier: 'claude_sonnet_3_5'
            )
          end
        end
      end
    end
  end

  describe 'when amazon q is connected' do
    let_it_be(:add_on_purchase) { create(:gitlab_subscription_add_on_purchase, :duo_amazon_q) }

    let(:expected_unit_primitive_name) { :amazon_q_integration }
    let(:expected_feature_name) { :amazon_q_integration }
    let(:expected_body) do
      body_with_model_metadata(provider: 'amazon_q', name: 'amazon_q', role_arn: 'role::arn')
    end

    before do
      stub_licensed_features(amazon_q: true)
      stub_current_organization(current_user.organization)
      Ai::Setting.for_organization(current_user.organization).update!(
        amazon_q_ready: true,
        amazon_q_role_arn: 'role::arn'
      )
    end

    it_behaves_like 'code suggestion task'

    context 'and a self-hosted code_completions feature setting exists' do
      let_it_be(:ai_feature_setting) { create(:ai_feature_setting, feature: :code_completions) }

      it_behaves_like 'code suggestion task'
    end
  end
end
