# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['DuoWorkflowAgentPresence'], feature_category: :duo_agent_platform do
  it 'has the expected fields' do
    expect(described_class).to have_graphql_fields(
      :session_id, :agent_name, :agent_catalog_web_path, :source_type, :source_link, :trigger_source,
      :flow_trigger, :user, :user_permissions
    )
  end

  it 'is presented by the agent presence presenter' do
    expect(described_class.presenter_class).to eq(::Ai::DuoWorkflows::AgentPresencePresenter)
  end

  describe 'DuoWorkflowAgentPresencePermissions' do
    it 'exposes only the read permission' do
      expect(GitlabSchema.types['DuoWorkflowAgentPresencePermissions']).to have_graphql_fields(:read_duo_workflow)
    end
  end
end
