# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../spec/support/shared_examples/events/cloud_event_with_schema_shared_examples'

# 19.5 ships the class only. Nothing publishes or subscribes to it until
# https://gitlab.com/gitlab-org/gitlab/-/merge_requests/256963, so that every node
# can read it before any node queues one.
RSpec.describe Ai::DuoWorkflows::WorkflowStoppedEvent, feature_category: :duo_agent_platform do
  it_behaves_like 'a cloud event with schema',
    valid_data: { workflow_id: 1, workflow_definition: 'chat', adapter: 'slack' },
    missing_required: %i[workflow_id],
    invalid_types: { workflow_id: 'not_an_integer', workflow_definition: 1, adapter: 1 }

  it_behaves_like 'a terminal Duo session cloud event' do
    let(:expected_type) { 'com.gitlab.duo_agent_platform.workflow_stopped' }
  end
end
