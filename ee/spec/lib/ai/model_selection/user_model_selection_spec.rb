# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ai::ModelSelection::UserModelSelection, :saas, feature_category: :duo_agent_platform do
  include_context 'with model selections fetch definition service side-effect context'

  let_it_be(:user) { create(:user) }
  let_it_be(:group, reload: true) { create(:group) }

  let(:feature) { :duo_agent_platform_agentic_chat }
  let(:offered_model_ref) { '' }
  let(:model_allowlist_enabled) { false }
  let(:model_allowlist_gitlab_model_refs) { [] }

  subject(:user_model_selection) do
    described_class.new(user, feature_setting: feature_setting)
  end

  before do
    allow(user).to receive(:governing_namespace).and_return(group)
  end

  describe '.for' do
    subject(:selection) { described_class.for(user, feature_setting: feature_setting) }

    context 'when the feature setting points to a self-hosted model' do
      let(:feature_setting) do
        build(:ai_feature_setting, feature: feature, self_hosted_model: build(:ai_self_hosted_model))
      end

      it 'returns a self-hosted selection' do
        expect(selection).to be_a(Ai::ModelSelection::SelfHostedModelSelection)
      end
    end

    context 'when the feature setting is cloud-connected' do
      let(:feature_setting) do
        build(:ai_namespace_feature_setting, namespace: group, feature: feature)
      end

      it 'returns a cloud selection' do
        expect(selection).to be_an_instance_of(described_class)
      end
    end

    context 'when no feature setting is given' do
      let(:feature_setting) { nil }

      it 'returns a cloud selection' do
        expect(selection).to be_an_instance_of(described_class)
      end
    end
  end

  # The class is scope-agnostic: it behaves identically for namespace-scoped settings
  # (gitlab.com / cloud-connected namespace) and instance-scoped settings (cloud-connected
  # self-managed). Both flow through the metadata service.
  shared_examples 'resolves the user-visible model picture' do
    before do
      stub_request(:get, fetch_service_endpoint_url)
        .to_return(status: 200, body: model_definitions_response, headers: { 'Content-Type' => 'application/json' })
    end

    describe '#default_model' do
      it 'returns the default model for the feature' do
        expect(user_model_selection.default_model[:ref]).to eq('claude_sonnet_4_20250514')
      end

      context 'when the admin allowlist is enabled' do
        let(:model_allowlist_enabled) { true }

        context 'when the admin has chosen a model' do
          let(:offered_model_ref) { 'claude_sonnet_3_7' }

          it 'returns the chosen model as the default' do
            expect(user_model_selection.default_model[:ref]).to eq('claude_sonnet_3_7')
          end
        end

        context 'when the admin has not chosen a model' do
          it 'returns the GitLab default model' do
            expect(user_model_selection.default_model[:ref]).to eq('claude_sonnet_4_20250514')
          end
        end
      end
    end

    describe '#selectable_models' do
      it 'returns the full set of selectable models' do
        expect(user_model_selection.selectable_models.map { |model| model[:ref] })
          .to match_array(%w[claude_sonnet_4_20250514 claude_sonnet_3_7])
      end

      context 'when the admin allowlist is enabled' do
        let(:model_allowlist_enabled) { true }
        let(:model_allowlist_gitlab_model_refs) { %w[claude_sonnet_3_7] }
        let(:offered_model_ref) { 'claude_sonnet_3_7' }

        it 'narrows the selectable models to the allowlist' do
          expect(user_model_selection.selectable_models.map { |model| model[:ref] })
            .to contain_exactly('claude_sonnet_3_7')
        end

        context 'when the admin has chosen a model outside the allowlist' do
          let(:offered_model_ref) { 'claude_sonnet_4_20250514' }

          it 'always includes the chosen model' do
            expect(user_model_selection.selectable_models.map { |model| model[:ref] })
              .to match_array(%w[claude_sonnet_4_20250514 claude_sonnet_3_7])
          end
        end
      end
    end

    describe '#enforced_model_refs' do
      it 'returns nil when the admin allowlist is disabled' do
        expect(user_model_selection.enforced_model_refs).to be_nil
      end

      context 'when the admin allowlist is enabled' do
        let(:model_allowlist_enabled) { true }
        let(:model_allowlist_gitlab_model_refs) { %w[claude_sonnet_3_7] }

        it 'returns the allowlisted refs and the GitLab default model' do
          expect(user_model_selection.enforced_model_refs)
            .to contain_exactly('claude_sonnet_3_7', 'claude_sonnet_4_20250514')
        end

        context 'when model definitions cannot be fetched' do
          before do
            allow(::Ai::ModelSelection::ModelDefinitions).to receive(:fetch).with(user)
              .and_return(::Ai::ModelSelection::ModelDefinitions.new(ServiceResponse.error(message: 'error')))
          end

          it 'returns only the allowlisted refs' do
            expect(user_model_selection.enforced_model_refs).to contain_exactly('claude_sonnet_3_7')
          end

          context 'when no refs are stored' do
            let(:model_allowlist_gitlab_model_refs) { [] }

            it 'returns an empty list, so no model is allowed' do
              expect(user_model_selection.enforced_model_refs).to eq([])
            end
          end
        end
      end
    end

    describe '#pinned_model' do
      context 'when a model is pinned' do
        let(:offered_model_ref) { 'claude_sonnet_4_20250514' }

        it 'returns the pinned model' do
          expect(user_model_selection.pinned_model[:ref]).to eq('claude_sonnet_4_20250514')
        end
      end

      context 'when no model is pinned' do
        it 'returns nil' do
          expect(user_model_selection.pinned_model).to be_nil
        end
      end

      context 'when the admin allowlist is enabled' do
        let(:model_allowlist_enabled) { true }
        let(:offered_model_ref) { 'claude_sonnet_4_20250514' }

        it 'returns nil so the model can still be selected' do
          expect(user_model_selection.pinned_model).to be_nil
        end

        context 'when the admin has not chosen a model' do
          let(:offered_model_ref) { '' }

          it 'returns nil' do
            expect(user_model_selection.pinned_model).to be_nil
          end
        end
      end
    end

    describe '#do_not_consider_user_selected_model?' do
      it 'considers a selectable ref' do
        expect(user_model_selection.do_not_consider_user_selected_model?('claude_sonnet_3_7')).to be(false)
      end

      it 'ignores a non-selectable ref' do
        expect(user_model_selection.do_not_consider_user_selected_model?('openai_chatgpt_4o')).to be(true)
      end

      it 'ignores a blank ref' do
        expect(user_model_selection.do_not_consider_user_selected_model?('')).to be(true)
      end

      context 'when a model is pinned' do
        let(:offered_model_ref) { 'claude_sonnet_4_20250514' }

        it 'ignores an otherwise selectable ref' do
          expect(user_model_selection.do_not_consider_user_selected_model?('claude_sonnet_3_7')).to be(true)
        end
      end

      context 'when the feature is not agentic chat' do
        let(:feature) { :duo_chat }

        it 'ignores a selectable ref' do
          expect(user_model_selection.do_not_consider_user_selected_model?('claude_sonnet_3_7')).to be(true)
        end
      end

      context 'when the admin allowlist is enabled' do
        let(:model_allowlist_enabled) { true }
        let(:model_allowlist_gitlab_model_refs) { %w[claude_sonnet_3_7] }

        context 'when the admin has chosen a model' do
          let(:offered_model_ref) { 'claude_sonnet_4_20250514' }

          it 'considers an allowlisted ref instead of treating the choice as pinned' do
            expect(user_model_selection.do_not_consider_user_selected_model?('claude_sonnet_3_7')).to be(false)
          end
        end

        context 'when the ref is selectable but excluded from the allowlist' do
          let(:offered_model_ref) { 'claude_sonnet_3_7' }

          it 'ignores it' do
            expect(user_model_selection.do_not_consider_user_selected_model?('claude_sonnet_4_20250514')).to be(true)
          end
        end

        context 'when the admin has not chosen a model' do
          let(:offered_model_ref) { '' }

          it 'considers an allowlisted ref' do
            expect(user_model_selection.do_not_consider_user_selected_model?('claude_sonnet_3_7')).to be(false)
          end

          it 'ignores a ref outside the allowlist' do
            expect(user_model_selection.do_not_consider_user_selected_model?('openai_chatgpt_4o')).to be(true)
          end
        end
      end
    end

    context 'when the feature is absent from the definitions' do
      let(:model_definitions) do
        {
          'models' => [{ 'name' => 'Claude Sonnet 3.5', 'identifier' => 'claude_sonnet_3_5' }],
          'unit_primitives' => [
            {
              'feature_setting' => 'duo_chat',
              'default_model' => 'claude_sonnet_3_5',
              'selectable_models' => %w[claude_sonnet_3_5],
              'beta_models' => []
            }
          ]
        }
      end

      it 'returns empty results', :aggregate_failures do
        expect(user_model_selection.default_model).to be_nil
        expect(user_model_selection.selectable_models).to eq([])
        expect(user_model_selection.do_not_consider_user_selected_model?('claude_sonnet_3_7')).to be(true)
      end
    end
  end

  context 'with a namespace feature setting' do
    let(:feature_setting) do
      build(:ai_namespace_feature_setting,
        namespace: group, feature: feature, offered_model_ref: offered_model_ref, model_definitions: model_definitions,
        model_allowlist_enabled: model_allowlist_enabled,
        model_allowlist_gitlab_model_refs: model_allowlist_gitlab_model_refs)
        .tap { |setting| setting.save!(validate: false) }
    end

    it_behaves_like 'resolves the user-visible model picture'

    context 'when the catalog contains a credit-gated model' do
      let(:gated_ref) { 'claude_fable_5' }
      let(:ungated_ref) { 'claude_sonnet_4_20250514' }

      let(:model_definitions) do
        {
          'models' => [
            { 'name' => 'Claude Sonnet 4.0', 'identifier' => ungated_ref, 'requires_paid_credits' => false },
            { 'name' => 'Claude Fable 5', 'identifier' => gated_ref, 'requires_paid_credits' => true }
          ],
          'unit_primitives' => [
            {
              'feature_setting' => 'duo_agent_platform_agentic_chat',
              'default_model' => ungated_ref,
              'selectable_models' => [ungated_ref, gated_ref],
              'beta_models' => []
            }
          ]
        }
      end

      before do
        stub_request(:get, fetch_service_endpoint_url)
          .to_return(status: 200, body: model_definitions_response,
            headers: { 'Content-Type' => 'application/json' })
      end

      describe '#credit_gated?' do
        context 'when the namespace must purchase credits' do
          before do
            create(:gitlab_subscription, :active_trial, :ultimate_trial, namespace: group)
          end

          it 'gates a model the catalog flags' do
            expect(user_model_selection.credit_gated?(gated_ref)).to be(true)
          end

          it 'does not gate a model the catalog leaves unflagged' do
            expect(user_model_selection.credit_gated?(ungated_ref)).to be(false)
          end

          it 'does not gate a ref the catalog does not describe' do
            expect(user_model_selection.credit_gated?('__default__agentic_chat')).to be(false)
          end

          it 'does not gate a blank ref', :aggregate_failures do
            expect(user_model_selection.credit_gated?(nil)).to be(false)
            expect(user_model_selection.credit_gated?('')).to be(false)
          end

          context 'when the catalog is unavailable' do
            before do
              allow_next_instance_of(::Ai::ModelSelection::FetchModelDefinitionsService) do |service|
                allow(service).to receive(:execute).and_return(nil)
              end
            end

            it 'gates the model so the caller falls back to the AI Gateway default' do
              expect(user_model_selection.credit_gated?(ungated_ref)).to be(true)
            end
          end
        end

        context 'when the namespace does not have to purchase credits' do
          it 'does not gate a model the catalog flags' do
            expect(user_model_selection.credit_gated?(gated_ref)).to be(false)
          end
        end
      end

      describe '#user_selected_model_credit_gated?' do
        context 'when the namespace must purchase credits' do
          before do
            create(:gitlab_subscription, :active_trial, :ultimate_trial, namespace: group)
          end

          it 'is true for a gated model the user could otherwise pick' do
            expect(user_model_selection.user_selected_model_credit_gated?(gated_ref)).to be(true)
          end

          it 'is false for an ungated model' do
            expect(user_model_selection.user_selected_model_credit_gated?(ungated_ref)).to be(false)
          end

          it 'is false for a model the feature does not offer' do
            expect(user_model_selection.user_selected_model_credit_gated?('claude_sonnet_3_5')).to be(false)
          end

          context 'when the admin pinned an ungated model' do
            let(:offered_model_ref) { ungated_ref }

            it 'is false, because the pick would be ignored anyway' do
              expect(user_model_selection.user_selected_model_credit_gated?(gated_ref)).to be(false)
            end
          end

          context 'when the feature is not agentic chat' do
            let(:feature) { :duo_agent_platform }

            it 'is false, because user selection does not apply' do
              expect(user_model_selection.user_selected_model_credit_gated?(gated_ref)).to be(false)
            end
          end
        end

        context 'when the namespace does not have to purchase credits' do
          it 'is false' do
            expect(user_model_selection.user_selected_model_credit_gated?(gated_ref)).to be(false)
          end
        end
      end

      describe '#selectable_models' do
        context 'when the namespace must purchase credits' do
          before do
            create(:gitlab_subscription, :active_trial, :ultimate_trial, namespace: group)
          end

          it 'keeps the gated model in the list and marks it', :aggregate_failures do
            expect(user_model_selection.selectable_models.pluck(:ref)).to contain_exactly(ungated_ref, gated_ref)
            expect(user_model_selection.selectable_models.select { |model| model[:requires_paid_credits] })
              .to contain_exactly(a_hash_including(ref: gated_ref))
          end

          it 'flags every model explicitly, never leaving the value unset' do
            expect(user_model_selection.selectable_models.map { |model| model[:requires_paid_credits] })
              .to contain_exactly(true, false)
          end
        end
      end

      describe '#default_model' do
        context 'when the allowlist is disabled and the feature default itself requires credits' do
          let(:model_definitions) do
            {
              'models' => [
                { 'name' => 'Claude Fable 5', 'identifier' => gated_ref, 'requires_paid_credits' => true }
              ],
              'unit_primitives' => [
                {
                  'feature_setting' => 'duo_agent_platform_agentic_chat',
                  'default_model' => gated_ref,
                  'selectable_models' => [gated_ref],
                  'beta_models' => []
                }
              ]
            }
          end

          before do
            create(:gitlab_subscription, :active_trial, :ultimate_trial, namespace: group)
          end

          it 'reports no default, because there is no ungated model to fall back to' do
            expect(user_model_selection.default_model).to be_nil
          end
        end

        context 'when the allowlist is disabled and the feature default does not require credits' do
          before do
            create(:gitlab_subscription, :active_trial, :ultimate_trial, namespace: group)
          end

          it 'flags it false rather than leaving it unset', :aggregate_failures do
            expect(user_model_selection.default_model[:ref]).to eq(ungated_ref)
            expect(user_model_selection.default_model[:requires_paid_credits]).to be(false)
          end
        end

        context 'when the allowlist is enabled and the catalog default is not allowlisted' do
          let(:model_allowlist_enabled) { true }
          let(:model_allowlist_gitlab_model_refs) { [gated_ref, other_ungated_ref] }
          let(:offered_model_ref) { gated_ref }
          let(:other_ungated_ref) { 'claude_haiku_4_5' }
          let(:model_definitions) do
            {
              'models' => [
                { 'name' => 'Claude Sonnet 4.0', 'identifier' => ungated_ref, 'requires_paid_credits' => false },
                { 'name' => 'Claude Haiku 4.5', 'identifier' => other_ungated_ref, 'requires_paid_credits' => false },
                { 'name' => 'Claude Fable 5', 'identifier' => gated_ref, 'requires_paid_credits' => true }
              ],
              'unit_primitives' => [
                {
                  'feature_setting' => 'duo_agent_platform_agentic_chat',
                  'default_model' => ungated_ref,
                  'selectable_models' => [ungated_ref, other_ungated_ref, gated_ref],
                  'beta_models' => []
                }
              ]
            }
          end

          before do
            create(:gitlab_subscription, :active_trial, :ultimate_trial, namespace: group)
          end

          it 'falls back to an allowlisted model rather than the unreachable catalog default' do
            expect(user_model_selection.default_model[:ref]).to eq(other_ungated_ref)
          end

          it 'does not hand back a gated default', :aggregate_failures do
            expect(user_model_selection.default_model[:ref]).not_to eq(gated_ref)
            expect(user_model_selection.default_model[:requires_paid_credits]).to be(false)
          end
        end

        context 'when the admin chose a model the feature does not offer' do
          let(:model_allowlist_enabled) { true }
          let(:model_allowlist_gitlab_model_refs) { [ungated_ref] }
          let(:offered_model_ref) { ungated_ref }
          let(:model_definitions) do
            {
              'models' => [
                { 'name' => 'Claude Sonnet 4.0', 'identifier' => ungated_ref, 'requires_paid_credits' => false },
                { 'name' => 'Claude Fable 5', 'identifier' => gated_ref, 'requires_paid_credits' => true },
                { 'name' => 'Claude Opus 4', 'identifier' => 'claude_opus_4', 'requires_paid_credits' => false }
              ],
              'unit_primitives' => [
                {
                  'feature_setting' => 'duo_agent_platform_agentic_chat',
                  'default_model' => ungated_ref,
                  'selectable_models' => [ungated_ref, gated_ref],
                  'beta_models' => []
                }
              ]
            }
          end

          before do
            create(:gitlab_subscription, :active_trial, :ultimate_trial, namespace: group)
            feature_setting.update_column(:offered_model_ref, 'claude_opus_4')
          end

          it 'reports no default when the offered ref is not a selectable model' do
            expect(user_model_selection.default_model).to be_nil
          end
        end

        context 'when every allowlisted model is gated' do
          let(:model_allowlist_enabled) { true }
          let(:model_allowlist_gitlab_model_refs) { [gated_ref] }
          let(:offered_model_ref) { gated_ref }

          before do
            create(:gitlab_subscription, :active_trial, :ultimate_trial, namespace: group)
          end

          it 'reports no default rather than an unusable one' do
            expect(user_model_selection.default_model).to be_nil
          end
        end

        context 'when the namespace must purchase credits and the allowlist holds the gated model' do
          let(:model_allowlist_enabled) { true }
          let(:model_allowlist_gitlab_model_refs) { [ungated_ref, gated_ref] }
          let(:offered_model_ref) { gated_ref }

          before do
            create(:gitlab_subscription, :active_trial, :ultimate_trial, namespace: group)
          end

          it 'falls back to the default model for the feature' do
            expect(user_model_selection.default_model[:ref]).to eq(ungated_ref)
          end
        end
      end

      describe '#pinned_model' do
        context 'when the namespace must purchase credits and an administrator pinned the gated model' do
          let(:offered_model_ref) { gated_ref }

          before do
            create(:gitlab_subscription, :active_trial, :ultimate_trial, namespace: group)
          end

          it 'does not report it as pinned, because the backend refuses to honour it' do
            expect(user_model_selection.pinned_model).to be_nil
          end
        end
      end

      describe '#do_not_consider_user_selected_model?' do
        context 'when the namespace must purchase credits' do
          before do
            create(:gitlab_subscription, :active_trial, :ultimate_trial, namespace: group)
          end

          it 'refuses the gated model' do
            expect(user_model_selection.do_not_consider_user_selected_model?(gated_ref)).to be(true)
          end

          it 'honours an ungated selection' do
            expect(user_model_selection.do_not_consider_user_selected_model?(ungated_ref)).to be(false)
          end

          context 'when an administrator pinned the gated model' do
            let(:offered_model_ref) { gated_ref }

            it 'honours the user selection instead of the unusable pin' do
              expect(user_model_selection.do_not_consider_user_selected_model?(ungated_ref)).to be(false)
            end
          end
        end
      end
    end
  end

  context 'with an instance feature setting' do
    let(:feature_setting) do
      create(:instance_model_selection_feature_setting,
        feature: feature, offered_model_ref: offered_model_ref, model_definitions: model_definitions,
        model_allowlist_enabled: model_allowlist_enabled,
        model_allowlist_gitlab_model_refs: model_allowlist_gitlab_model_refs)
    end

    it_behaves_like 'resolves the user-visible model picture'
  end

  context 'when no feature setting is given' do
    let(:feature_setting) { nil }

    it 'returns empty results without fetching definitions', :aggregate_failures do
      expect(::Ai::ModelSelection::FetchModelDefinitionsService).not_to receive(:new)

      expect(user_model_selection.default_model).to be_nil
      expect(user_model_selection.selectable_models).to eq([])
      expect(user_model_selection.pinned_model).to be_nil
      expect(user_model_selection.enforced_model_refs).to be_nil
      expect(user_model_selection.do_not_consider_user_selected_model?('claude_sonnet_3_7')).to be(true)
    end
  end

  context 'when the fetch fails' do
    let(:feature_setting) do
      create(:ai_namespace_feature_setting, namespace: group, feature: feature, offered_model_ref: offered_model_ref)
    end

    before do
      stub_request(:get, fetch_service_endpoint_url)
        .to_return(status: 400, body: '{}', headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns empty results', :aggregate_failures do
      expect(user_model_selection.default_model).to be_nil
      expect(user_model_selection.selectable_models).to eq([])
      expect(user_model_selection.do_not_consider_user_selected_model?('claude_sonnet_3_7')).to be(true)
    end
  end

  context 'when the fetch returns nil' do
    let(:feature_setting) do
      create(:ai_namespace_feature_setting, namespace: group, feature: feature, offered_model_ref: offered_model_ref)
    end

    before do
      allow_next_instance_of(::Ai::ModelSelection::FetchModelDefinitionsService) do |service|
        allow(service).to receive(:execute).and_return(nil)
      end
    end

    it 'returns empty results', :aggregate_failures do
      expect(user_model_selection.default_model).to be_nil
      expect(user_model_selection.selectable_models).to eq([])
      expect(user_model_selection.do_not_consider_user_selected_model?('claude_sonnet_3_7')).to be(true)
    end
  end
end
