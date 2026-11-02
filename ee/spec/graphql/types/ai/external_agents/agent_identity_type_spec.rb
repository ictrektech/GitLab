# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['AiAgentIdentity'], feature_category: :software_composition_analysis do
  it 'has the expected fields' do
    expect(described_class).to have_graphql_fields(
      :id, :agent_type, :user, :project, :created_at, :last_synced_at, :revoked_at, :status, :session_count
    )
  end
end
