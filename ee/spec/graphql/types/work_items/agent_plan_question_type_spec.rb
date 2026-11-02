# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Types::WorkItems::AgentPlanQuestionType, feature_category: :duo_agent_platform do
  let(:fields) { %i[note_id discussion_id answered] }

  specify { expect(described_class.graphql_name).to eq('WorkItemAgentPlanQuestion') }

  specify { expect(described_class).to have_graphql_fields(fields) }
end
