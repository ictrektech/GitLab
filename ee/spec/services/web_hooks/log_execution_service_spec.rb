# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WebHooks::LogExecutionService, feature_category: :webhooks do
  describe '#execute' do
    let_it_be(:group_hook) { create(:group_hook) }

    let(:data) do
      {
        trigger: 'trigger_name',
        url: 'https://example.com',
        request_headers: { 'Header' => 'header value' },
        request_data: { 'Request Data' => 'request data value' },
        response_body: 'Response body',
        response_status: '200',
        execution_duration: 1.2
      }
    end

    subject(:service) { described_class.new(hook: group_hook, log_data: data, response_category: :ok) }

    it 'logs the data with the group of a group hook' do
      expect { service.execute }.to change { WebHookLog.count }.by(1)

      expect(WebHookLog.recent.first).to have_attributes(
        data.merge(project_id: nil, group_id: group_hook.group_id, organization_id: nil)
      )
    end
  end
end
