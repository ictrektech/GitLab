# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../spec/support/shared_examples/events/cloud_event_with_schema_shared_examples'

RSpec.describe Ai::DuoWorkflows::WorkflowFinishedCloudEvent, feature_category: :duo_agent_platform do
  it_behaves_like 'a cloud event with schema',
    valid_data: { workflow_id: 1, workflow_definition: 'chat', adapter: 'slack' },
    missing_required: %i[workflow_id],
    invalid_types: { workflow_id: 'not_an_integer', workflow_definition: 1, adapter: 1 }

  it_behaves_like 'a terminal Duo session cloud event' do
    let(:expected_type) { 'com.gitlab.duo_agent_platform.workflow_finished' }
  end
end
