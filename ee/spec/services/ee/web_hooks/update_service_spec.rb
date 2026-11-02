# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WebHooks::UpdateService, :sidekiq_inline, feature_category: :webhooks do
  let_it_be(:current_user) { create(:admin) }

  subject(:update_hook) { described_class.new(current_user).execute(hook, hook_params) }

  describe '#execute' do
    let(:hook_params) { { url: 'https://example.com/changed' } }

    shared_examples 'audits the update' do |expected_message:|
      it 'creates a webhook_updated audit event listing the changed attribute names', :aggregate_failures do
        expect { update_hook }.to change { AuditEventReader.count }.by(1)

        expect(AuditEventReader.last).to have_attributes(
          author_id: current_user.id,
          target_type: hook.class.name,
          target_details: "Hook #{hook.id}",
          details: include(
            event_name: 'webhook_updated',
            custom_message: expected_message,
            changed_attributes: ['url']
          )
        )
      end
    end

    context 'with a project hook' do
      let_it_be(:project) { create(:project) }
      let(:hook) { create(:project_hook, project: project) }

      before_all do
        project.add_maintainer(current_user)
      end

      it_behaves_like 'audits the update', expected_message: 'Updated project hook'

      it 'scopes the event to the project' do
        update_hook

        expect(AuditEvents::ProjectAuditEvent.last.project_id).to eq(project.id)
      end

      context 'when secrets change' do
        let(:hook_params) do
          {
            token: 'new-secret-token',
            url: 'https://user:password@example.com/changed',
            url_variables: { 'abc' => 'hidden-value' },
            custom_headers: { 'X-Secret' => 'hidden-header' }
          }
        end

        it 'records attribute names only and never values', :aggregate_failures do
          update_hook

          details = AuditEventReader.last.details

          expect(details[:changed_attributes]).to match_array(%w[custom_headers token url url_variables])
          expect(details.to_json).not_to include('new-secret-token', 'password', 'hidden-value', 'hidden-header')
          expect(details.keys).not_to include(:encrypted_token, :encrypted_url_variables, :encrypted_custom_headers)
        end
      end

      context 'when nothing changes' do
        let(:hook_params) { { url: hook.url } }

        it 'does not create an audit event' do
          expect { update_hook }.not_to change { AuditEventReader.count }
        end
      end

      context 'when blank values replace nil values, as the edit form submits them' do
        let(:hook) do
          create(:project_hook, project: project, name: nil, description: nil, custom_webhook_template: nil)
        end

        let(:hook_params) { { name: '', description: '', custom_webhook_template: '' } }

        it 'does not create an audit event' do
          expect { update_hook }.not_to change { AuditEventReader.count }
        end
      end

      context 'when an encrypted attribute goes from nil to blank' do
        let(:hook_params) { { token: '' } }

        before do
          hook.update!(token: nil)
        end

        it 'does not create an audit event' do
          expect { update_hook }.not_to change { AuditEventReader.count }
        end
      end

      context 'when the update fails' do
        let(:hook_params) { { url: 'invalid_url' } }

        it 'does not create an audit event' do
          expect { update_hook }.not_to change { AuditEventReader.count }
        end
      end
    end

    context 'with a group hook' do
      let_it_be(:group) { create(:group) }
      let(:hook) { create(:group_hook, group: group) }

      before_all do
        group.add_owner(current_user)
      end

      it_behaves_like 'audits the update', expected_message: 'Updated group hook'

      it 'scopes the event to the group' do
        update_hook

        expect(AuditEvents::GroupAuditEvent.last.group_id).to eq(group.id)
      end
    end

    context 'with a system hook', :enable_admin_mode do
      let_it_be(:organization) { create(:organization) }
      let_it_be(:other_organization) { create(:organization) }
      let_it_be(:current_user) { create(:admin, organization: other_organization) }
      let(:hook) { create(:system_hook, organization: organization) }

      it_behaves_like 'audits the update', expected_message: 'Updated system hook'

      it 'records the event at instance scope with the hook organization in the details', :aggregate_failures do
        expect { update_hook }
          .to change { AuditEvents::InstanceAuditEvent.count }.by(1)
          .and not_change { AuditEvents::UserAuditEvent.count }

        expect(AuditEvents::InstanceAuditEvent.last.details[:organization_id]).to eq(organization.id)
      end
    end
  end
end
