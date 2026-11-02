# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::SystemHooks, :with_current_organization, :sidekiq_inline, feature_category: :webhooks do
  let_it_be(:admin) { create(:admin) }
  let_it_be_with_refind(:hook) do
    create(:system_hook, url: 'http://example.com', organization: current_organization,
      url_variables: { 'abc' => 'secret' })
  end

  shared_examples 'audits the system hook update' do |changed_attributes|
    it 'creates an instance-scoped webhook_updated event attributed to the organization', :aggregate_failures do
      expect { request }
        .to change { AuditEvents::InstanceAuditEvent.count }.by(1)
        .and not_change { AuditEvents::UserAuditEvent.count }

      expect(AuditEvents::InstanceAuditEvent.last).to have_attributes(
        author_id: admin.id,
        target_type: 'SystemHook',
        target_details: "Hook #{hook.id}",
        details: include(
          event_name: 'webhook_updated',
          organization_id: current_organization.id,
          changed_attributes: changed_attributes
        )
      )
      expect(AuditEvents::InstanceAuditEvent.last.details.to_json).not_to include('changed-value')
    end
  end

  describe 'PUT /hooks/:hook_id' do
    subject(:request) do
      put api("/hooks/#{hook.id}", admin, admin_mode: true), params: { url: 'http://example.org' }
    end

    # Changing the URL also clears the now-stale url_variables via the model's
    # before_validation callback, so both attributes are reported as changed.
    it_behaves_like 'audits the system hook update', %w[url url_variables]
  end

  describe 'PUT /hooks/:hook_id/url_variables/:key' do
    subject(:request) do
      put api("/hooks/#{hook.id}/url_variables/abc", admin, admin_mode: true), params: { value: 'changed-value' }
    end

    it_behaves_like 'audits the system hook update', ['url_variables']
  end

  describe 'DELETE /hooks/:hook_id/url_variables/:key' do
    subject(:request) do
      delete api("/hooks/#{hook.id}/url_variables/abc", admin, admin_mode: true)
    end

    it_behaves_like 'audits the system hook update', ['url_variables']
  end

  describe 'PUT /hooks/:hook_id/custom_headers/:key' do
    subject(:request) do
      put api("/hooks/#{hook.id}/custom_headers/X-Custom", admin, admin_mode: true), params: { value: 'changed-value' }
    end

    it_behaves_like 'audits the system hook update', ['custom_headers']
  end
end
