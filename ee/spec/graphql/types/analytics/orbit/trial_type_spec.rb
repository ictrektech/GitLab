# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::Analytics::Orbit::TrialType, feature_category: :knowledge_graph do
  include GraphqlHelpers

  it { expect(described_class.graphql_name).to eq('OrbitTrial') }
  it { expect(described_class).to have_graphql_fields(:state, :expires_on, :credits, :offer) }
  it { expect(described_class).to require_graphql_authorizations(:read_orbit_trial) }

  describe '#credits' do
    let_it_be(:group) { create(:group) }
    let_it_be(:owner) { create(:user, owner_of: group) }
    let_it_be(:admin) { create(:admin) }

    let(:trial) do
      ::Gitlab::SubscriptionPortal::ProductTrialResponse.new(
        state: :trial, trial_expires_at: 10.days.from_now, credits_remaining: 80.0, credits_total: 100.0
      )
    end

    let(:adapter) { described_class::Adapter.new(trial: trial, group: group) }

    subject(:credits) { resolve_field(:credits, adapter, current_user: current_user) }

    before do
      allow(described_class).to receive(:authorized?).and_return(true)
      stub_saas_features(gitlab_com_subscriptions: saas)
    end

    context 'on GitLab.com' do
      let(:saas) { true }
      let(:current_user) { owner }

      it 'shows the group Owner the credits of the group trial' do
        expect(credits).to eq(adapter)
      end
    end

    context 'on an instance' do
      let(:saas) { false }

      context 'for a group Owner' do
        let(:current_user) { owner }

        it 'hides the credits that all groups share' do
          expect(credits).to be_nil
        end
      end

      context 'for an administrator in admin mode', :enable_admin_mode do
        let(:current_user) { admin }

        it 'shows the credits' do
          expect(credits).to eq(adapter)
        end
      end

      context 'for an administrator without admin mode' do
        let(:current_user) { admin }

        it 'hides the credits' do
          expect(credits).to be_nil
        end
      end

      context 'without a user' do
        let(:current_user) { nil }

        it 'hides the credits' do
          expect(credits).to be_nil
        end
      end
    end
  end
end
