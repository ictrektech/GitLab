# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Mutations::Ai::FlowTriggers::Update, feature_category: :dap_triggers do
  include GraphqlHelpers

  subject(:mutation) { described_class }

  it { is_expected.to have_graphql_name('AiFlowTriggerUpdate') }

  it { expect(described_class).to require_graphql_authorizations(:manage_ai_flow_triggers) }

  it { is_expected.to have_graphql_fields(:ai_flow_trigger, :errors, :client_mutation_id) }

  it 'has expected arguments' do
    is_expected.to have_graphql_arguments(
      :id,
      :user_id,
      :description,
      :event_types,
      :config_path,
      :ai_catalog_item_consumer_id,
      :filter,
      :goals,
      :status_on_finish,
      :ready_merge_requests_on_finish,
      :active,
      :client_mutation_id
    )
  end

  it 'classifies every argument as ungated or gated' do
    arguments = described_class.arguments.keys.map { |name| name.underscore.to_sym }

    expect(arguments - %i[id client_mutation_id] - ::Ai::FlowTriggers::UpdateService::UNGATED_UPDATE_PARAMS)
      .to contain_exactly(:ai_catalog_item_consumer_id, :config_path)
  end
end
