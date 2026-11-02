# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Profiles::PreferencesController, feature_category: :user_profile do
  let_it_be(:user) { create(:user) }

  before do
    sign_in(user)
  end

  describe 'PATCH update' do
    context 'when updating orbit subsettings' do
      before do
        allow(::Ai::Orbit::Settings).to receive(:orbit_in_duo_on?).and_return(true)
      end

      it 'persists each submitted subsetting' do
        patch :update, params: { user: {
          orbit_agent_enabled: '1',
          orbit_agentic_chat_enabled: '0',
          orbit_other_foundational_agents_enabled: '1',
          orbit_custom_agents_enabled: '0'
        } }, format: :json

        preference = user.reload.user_preference
        expect(preference.orbit_agent_enabled).to be(true)
        expect(preference.orbit_agentic_chat_enabled).to be(false)
        expect(preference.orbit_other_foundational_agents_enabled).to be(true)
        expect(preference.orbit_custom_agents_enabled).to be(false)
      end

      it 'does not materialize subsettings that already match the effective values' do
        user.user_preference.update!(orbit_settings: {})

        patch :update, params: { user: {
          orbit_agent_enabled: '1',
          orbit_agentic_chat_enabled: '1',
          orbit_other_foundational_agents_enabled: '1',
          orbit_custom_agents_enabled: '1',
          preferred_language: 'en'
        } }, format: :json

        expect(user.reload.user_preference.orbit_settings).to eq({})
      end
    end

    context 'when updating security dashboard feature' do
      subject(:update_request) { patch :update, params: { user: { group_view: group_view } }, format: :json }

      let(:group_view) { 'security_dashboard' }

      context 'when the security dashboard feature is enabled' do
        before do
          stub_licensed_features(security_dashboard: true)
        end

        context 'and valid group view choice is submitted' do
          it "changes the user's preferences" do
            expect { update_request }.to change { user.reload.group_view_security_dashboard? }.from(false).to(true)
          end

          context 'and an invalid group view choice is submitted' do
            let(:group_view) { 'foo' }

            it 'responds with an error message' do
              update_request

              expect(response).to have_gitlab_http_status(:bad_request)
              expect(response.parsed_body['message']).to match(/Failed to save preferences/)
              expect(response.parsed_body['type']).to eq('alert')
            end
          end
        end
      end

      context 'when the security dashboard feature is disabled' do
        context 'when security dashboard feature enabled' do
          specify do
            expect { update_request }.not_to change { user.reload.group_view_security_dashboard? }
          end
        end
      end
    end

    context 'when updating knowledge_graph_governing_namespace_id' do
      let_it_be(:namespace) { create(:group, developers: [user]) }

      subject(:update_request) do
        patch :update, params: { user: { knowledge_graph_governing_namespace_id: namespace.id } }, format: :json
      end

      context 'when SaaS', :saas do
        before do
          stub_saas_features(gitlab_com_subscriptions: true)
          stub_feature_flags(orbit_promo_access_gate: false)
          create(:gitlab_subscription, :premium, namespace: namespace)
          create(:knowledge_graph_enabled_namespace, namespace: namespace)
        end

        it 'updates the preference' do
          expect { update_request }
            .to change { user.reload.user_preference.knowledge_graph_governing_namespace_id }.to(namespace.id)
        end
      end

      context 'when self-managed' do
        it 'does not permit the param and leaves the preference unchanged' do
          expect { update_request }
            .not_to change { user.reload.user_preference.knowledge_graph_governing_namespace_id }
        end
      end
    end
  end
end
