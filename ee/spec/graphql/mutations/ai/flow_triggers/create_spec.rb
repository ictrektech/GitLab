# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Ai::FlowTriggers::Create, feature_category: :dap_triggers do
  include GraphqlHelpers

  subject(:mutation) { described_class }

  it { is_expected.to have_graphql_name('AiFlowTriggerCreate') }

  it { expect(described_class).to require_graphql_authorizations(:manage_ai_flow_triggers) }

  it { is_expected.to have_graphql_fields(:ai_flow_trigger, :errors, :client_mutation_id) }

  it 'has expected arguments' do
    is_expected.to have_graphql_arguments(
      :project_path,
      :user_id,
      :description,
      :event_types,
      :filter,
      :goals,
      :status_on_finish,
      :ready_merge_requests_on_finish,
      :config_path,
      :ai_catalog_item_consumer_id,
      :active,
      :client_mutation_id
    )
  end
end
