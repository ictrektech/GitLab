# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'projectSecretsManager.writeDenialReason', feature_category: :secrets_management do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:root_group) { create(:group) }
  let_it_be(:project) { create(:project, group: create(:group, parent: root_group)) }
  let_it_be(:project_reporter) { create(:user, reporter_of: project) }
  let_it_be(:project_guest) { create(:user, guest_of: project) }
  let_it_be(:project_secrets_manager) { create(:project_secrets_manager, project: project) }

  let(:query) do
    graphql_query_for(:project_secrets_manager, { project_path: project.full_path }, 'writeDenialReason')
  end

  subject(:write_denial_reason) do
    post_graphql(query, current_user: project_reporter)

    graphql_data_at(:project_secrets_manager, :write_denial_reason)
  end

  before do
    stub_licensed_features(native_secrets_management: true)
    enroll_instance_in_secrets_manager
  end

  where(:state, :blocked_reason, :expected) do
    :paid           | nil                 | nil
    :trial          | nil                 | nil
    :ineligible     | nil                 | 'INELIGIBLE'
    :blocked        | :credits_exhausted  | 'CREDITS_EXHAUSTED'
    :blocked        | :on_demand_disabled | 'ON_DEMAND_DISABLED'
  end

  with_them do
    it 'returns the reason from the entitlement' do
      stub_secrets_manager_entitlement(state: state, blocked_reason: blocked_reason)

      expect(write_denial_reason).to eq(expected)
    end
  end

  it 'returns the reason from the top-level group entitlement for a project-only member' do
    allow(::SecretsManagement::Entitlement).to receive(:for).with(root_group, user: project_reporter)
      .and_return(::SecretsManagement::Entitlement.new(state: :blocked, blocked_reason: :trial_expired))

    expect(write_denial_reason).to eq('TRIAL_EXPIRED')
  end

  # TRIAL_REQUIRED is never returned here: the project secrets manager is hidden while the
  # top-level group is trial-eligible.
  it 'returns no secrets manager while the top-level group is trial-eligible' do
    stub_secrets_manager_entitlement(state: :trial_eligible)

    post_graphql(query, current_user: project_reporter)

    expect(graphql_data_at(:project_secrets_manager)).to be_nil
  end

  it 'returns no secrets manager for a Guest' do
    stub_secrets_manager_entitlement(state: :blocked, blocked_reason: :credits_exhausted)

    post_graphql(query, current_user: project_guest)

    expect(graphql_data_at(:project_secrets_manager)).to be_nil
  end
end
