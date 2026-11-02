# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'groupSecretsManager.writeDenialReason', feature_category: :secrets_management do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:root_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: root_group) }
  let_it_be(:root_reporter) { create(:user, reporter_of: root_group) }
  let_it_be(:subgroup_reporter) { create(:user, reporter_of: subgroup) }
  let_it_be(:root_guest) { create(:user, guest_of: root_group) }

  let_it_be(:root_secrets_manager) { create(:group_secrets_manager, group: root_group) }
  let_it_be(:subgroup_secrets_manager) { create(:group_secrets_manager, group: subgroup) }

  let(:target_group) { root_group }
  let(:current_user) { root_reporter }
  let(:query) do
    graphql_query_for(:group_secrets_manager, { group_path: target_group.full_path }, 'writeDenialReason')
  end

  subject(:write_denial_reason) do
    post_graphql(query, current_user: current_user)

    graphql_data_at(:group_secrets_manager, :write_denial_reason)
  end

  before do
    stub_licensed_features(native_secrets_management: true)
    enroll_instance_in_secrets_manager
  end

  where(:state, :blocked_reason, :expected) do
    :paid           | nil                 | nil
    :trial          | nil                 | nil
    :ineligible     | nil                 | 'INELIGIBLE'
    :trial_eligible | nil                 | 'TRIAL_REQUIRED'
    :blocked        | :credits_exhausted  | 'CREDITS_EXHAUSTED'
    :blocked        | :on_demand_disabled | 'ON_DEMAND_DISABLED'
  end

  with_them do
    it 'returns the reason from the entitlement' do
      stub_secrets_manager_entitlement(state: state, blocked_reason: blocked_reason)

      expect(write_denial_reason).to eq(expected)
    end
  end

  context 'when the user is a member of only the subgroup' do
    let(:target_group) { subgroup }
    let(:current_user) { subgroup_reporter }

    it 'returns the reason from the top-level group entitlement' do
      allow(::SecretsManagement::Entitlement).to receive(:for).with(root_group, user: current_user)
        .and_return(::SecretsManagement::Entitlement.new(state: :blocked, blocked_reason: :trial_expired))

      expect(write_denial_reason).to eq('TRIAL_EXPIRED')
    end

    # TRIAL_REQUIRED is only returned on the top-level group: subgroup secrets managers are
    # hidden while it is trial-eligible.
    it 'returns no secrets manager while the top-level group is trial-eligible' do
      stub_secrets_manager_entitlement(state: :trial_eligible)

      post_graphql(query, current_user: current_user)

      expect(graphql_data_at(:group_secrets_manager)).to be_nil
    end
  end

  context 'when the user is a Guest' do
    let(:current_user) { root_guest }

    it 'returns no secrets manager' do
      stub_secrets_manager_entitlement(state: :blocked, blocked_reason: :credits_exhausted)

      post_graphql(query, current_user: current_user)

      expect(graphql_data_at(:group_secrets_manager)).to be_nil
    end
  end
end
