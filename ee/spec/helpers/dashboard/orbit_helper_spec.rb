# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Dashboard::OrbitHelper, feature_category: :knowledge_graph do
  describe '#orbit_app_data' do
    before do
      # current_user goes through Devise/Warden which is not wired up for
      # helper specs; stub the helper-level methods that depend on it.
      allow(helper).to receive_messages(current_user: nil, duo_accessible?: false,
        orbit_settings_enabled?: false, admin_orbit_configure_available?: false)
    end

    it 'includes router_base pointing at the dashboard orbit path' do
      expect(helper.orbit_app_data[:router_base]).to eq(dashboard_orbit_path)
    end

    it 'includes duo_accessible as a string' do
      expect(helper.orbit_app_data[:duo_accessible]).to eq('false')
    end

    describe 'can_ask_duo_for_queries' do
      using RSpec::Parameterized::TableSyntax

      where(:duo, :value) do
        true  | 'true'
        false | 'false'
      end

      with_them do
        it 'is true only when the user can reach GitLab Duo' do
          allow(helper).to receive(:duo_accessible?).and_return(duo)

          expect(helper.orbit_app_data[:can_ask_duo_for_queries]).to eq(value)
        end
      end
    end

    it 'includes orbit_settings_enabled as a string' do
      expect(helper.orbit_app_data[:orbit_settings_enabled]).to eq('false')
    end

    context 'when deriving orbit_settings_enabled from the facade' do
      let_it_be(:user) { build_stubbed(:user) }

      before do
        allow(helper).to receive(:current_user).and_return(user)
        allow(helper).to receive(:orbit_settings_enabled?).and_call_original
      end

      it 'reflects Ai::Orbit::Settings.orbit_in_duo_on?' do
        allow(::Ai::Orbit::Settings).to receive(:orbit_in_duo_on?).with(user).and_return(true)

        expect(helper.orbit_app_data[:orbit_settings_enabled]).to eq('true')
      end
    end

    context 'when admin orbit configure is available' do
      before do
        allow(helper).to receive(:admin_orbit_configure_available?).and_return(true)
      end

      it 'includes the admin path and lists all groups' do
        expect(helper.orbit_app_data).to include(admin_configuration_path: admin_orbit_path, list_all_groups: 'true')
      end
    end

    context 'when admin orbit configure is not available' do
      it 'omits the admin path and lists only the groups of the user' do
        expect(helper.orbit_app_data).not_to have_key(:admin_configuration_path)
        expect(helper.orbit_app_data[:list_all_groups]).to eq('false')
      end
    end

    describe 'queries_available' do
      using RSpec::Parameterized::TableSyntax

      let_it_be(:user) { build_stubbed(:user, namespace: build_stubbed(:user_namespace)) }

      where(:saas, :accessible, :value) do
        true  | false | 'true'
        false | true  | 'true'
        false | false | 'false'
      end

      with_them do
        it 'reports whether the instance runs Orbit queries for the user' do
          stub_saas_features(gitlab_com_subscriptions: saas)
          allow(helper).to receive(:current_user).and_return(user)
          allow(Analytics::KnowledgeGraph).to receive(:accessible_for?).with(user).and_return(accessible)

          expect(helper.orbit_app_data[:queries_available]).to eq(value)
        end
      end
    end

    describe 'orbit_platform', :request_store do
      let_it_be(:user) { build_stubbed(:user, namespace: build_stubbed(:user_namespace)) }

      let(:current_license) { ::License.current || build(:license) }
      let(:client) { ::Gitlab::SubscriptionPortal::Client }

      def platform
        ::Gitlab::Json::SafeParser.parse(helper.orbit_app_data[:orbit_platform])
      end

      def cdot_trial(state, **attrs)
        ::Gitlab::SubscriptionPortal::ProductTrialResponse.new(state: state, **attrs)
      end

      before do
        allow(helper).to receive(:current_user).and_return(user)
        stub_config(knowledge_graph: { 'enabled' => true })
      end

      context 'on GitLab.com' do
        before do
          stub_saas_features(gitlab_com_subscriptions: true)
        end

        it 'sends no instance access and asks CustomersDot nothing' do
          expect(client).not_to receive(:product_trial)

          expect(platform).to eq('saas' => true)
        end
      end

      context 'on an instance under the promo gate with the trial flow' do
        before do
          stub_saas_features(gitlab_com_subscriptions: false)
          stub_licensed_features(orbit: true)
          stub_feature_flags(orbit_promo_access_gate: true, orbit_trial: true)
          allow(::License).to receive(:current).and_return(current_license)
          allow(current_license).to receive(:online_cloud_license?).and_return(true)
        end

        context 'when the instance runs no queries and the trial can start' do
          before do
            allow(client).to receive(:product_trial).and_return(cdot_trial(:trial_eligible))
          end

          it 'sends the instance state, with one CustomersDot read for the page' do
            expect(helper.orbit_app_data).to include(queries_available: 'false')
            expect(platform).to include('saas' => false)
            expect(platform['instance']).to eq('state' => 'TRIAL_ELIGIBLE')
            expect(client).to have_received(:product_trial).once
          end
        end

        context 'when the trial is active' do
          before do
            allow(client).to receive(:product_trial)
              .and_return(cdot_trial(:trial, trial_expires_at: 10.days.from_now, credits_remaining: 50.0))
          end

          it 'runs queries, sends no instance state, and reads CustomersDot once' do
            expect(helper.orbit_app_data).to include(queries_available: 'true')
            expect(platform).not_to have_key('instance')
            expect(client).to have_received(:product_trial).once
          end
        end

        context 'when CustomersDot does not answer' do
          before do
            allow(client).to receive(:product_trial)
              .and_raise(::Gitlab::SubscriptionPortal::ProductTrialResponse::UnavailableError, 'HTTP 503')
            allow(::Gitlab::ErrorTracking).to receive(:track_exception)
          end

          it 'sends the outage state, with one CustomersDot call for the page' do
            expect(platform['instance']).to eq('state' => 'TRIAL_STATUS_UNAVAILABLE')
            expect(client).to have_received(:product_trial).once
          end
        end
      end
    end

    context 'on SaaS with no current user' do
      before do
        stub_saas_features(gitlab_com_subscriptions: true)
      end

      it 'offers no trial and does not report the default group as missing' do
        expect(helper.orbit_app_data).to include(trial_available: 'false', default_group_missing: 'false')
      end
    end

    context 'with a user who can set a governing group' do
      let_it_be(:user) { build_stubbed(:user) }
      let_it_be(:default_group) { build_stubbed(:group, path: 'acme') }

      before do
        allow(helper).to receive(:current_user).and_return(user)
        allow(helper).to receive(:can?).with(user, :update_governing_knowledge_graph_namespace)
          .and_return(true)
        allow(user.user_preference).to receive(:knowledge_graph_governing_namespace_with_fallback)
          .and_return(default_group)
      end

      it 'includes the preferences path anchored to the default group setting' do
        expect(helper.orbit_app_data[:preferences_path]).to eq(profile_preferences_path(anchor: 'orbit-default-group'))
      end

      context 'when the user can set a governing group but none resolves' do
        before do
          allow(user.user_preference).to receive(:knowledge_graph_governing_namespace_with_fallback)
            .and_return(nil)
        end

        it 'reports the default group as missing' do
          expect(helper.orbit_app_data[:default_group_missing]).to eq('true')
        end
      end

      context 'when the user has a governing group' do
        it 'does not report the default group as missing' do
          expect(helper.orbit_app_data[:default_group_missing]).to eq('false')
        end
      end

      context 'when the user cannot set a governing group (self-managed or no candidates)' do
        before do
          allow(helper).to receive(:can?).with(user, :update_governing_knowledge_graph_namespace)
            .and_return(false)
          allow(user.user_preference).to receive(:knowledge_graph_governing_namespace_with_fallback)
            .and_return(nil)
        end

        it 'does not report the default group as missing' do
          expect(helper.orbit_app_data[:default_group_missing]).to eq('false')
        end
      end

      context 'when SaaS subscriptions are available' do
        let(:personal_namespace) { build_stubbed(:user_namespace) }

        before do
          stub_saas_features(gitlab_com_subscriptions: true)
          allow(user).to receive(:namespace).and_return(personal_namespace)
        end

        it 'sets trial_available to true and marks the platform as GitLab.com' do
          expect(helper.orbit_app_data).to include(trial_available: 'true')
          expect(::Gitlab::Json::SafeParser.parse(helper.orbit_app_data[:orbit_platform]))
            .to include('saas' => true)
        end

        it 'falls back to the personal namespace for leads that name no group' do
          expect(Gitlab::Json::SafeParser.parse(helper.orbit_app_data[:hand_raise_lead_user]))
            .to include('namespace_id' => personal_namespace.id, 'user_name' => user.username)
          expect(helper.orbit_app_data[:hand_raise_lead_submit_path])
            .to eq(gitlab_subscriptions_hand_raise_leads_path)
        end
      end

      context 'when SaaS subscriptions are not available' do
        it 'sets trial_available to false, marks the platform off GitLab.com, and sends no hand-raise lead data' do
          expect(helper.orbit_app_data).to include(trial_available: 'false')
          expect(::Gitlab::Json::SafeParser.parse(helper.orbit_app_data[:orbit_platform]))
            .to include('saas' => false)
          expect(helper.orbit_app_data).not_to have_key(:hand_raise_lead_user)
        end
      end
    end
  end
end
