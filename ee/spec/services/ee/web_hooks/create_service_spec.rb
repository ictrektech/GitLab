# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WebHooks::CreateService, :sidekiq_inline, feature_category: :webhooks do
  let_it_be(:current_user) { create(:user) }

  describe '#execute' do
    # Testing with a project hook only - for permission tests, see policy specs.
    let_it_be(:project) { create(:project) }
    let_it_be(:relation) { ProjectHook.none }
    let(:hook_params) { { url: 'https://example.com/hook', project_id: project.id } }

    subject(:webhook_created) { described_class.new(current_user) }

    context 'when creating a project hook succeeds' do
      it 'creates an audit event', :aggregate_failures do
        webhook_created.execute(hook_params, relation)

        expect(AuditEventReader.last).to have_attributes(
          author_name: current_user.name,
          author_id: current_user.id,
          target_type: "ProjectHook",
          target_details: "Hook #{ProjectHook.last.id}",
          details: include(custom_message: "Created project hook")
        )
      end
    end

    context 'when creating a project hook fails' do
      it 'does not create an audit event' do
        hook_params[:url] = 'invalid_url'

        response = webhook_created.execute(hook_params, relation)

        expect { response }.not_to change { AuditEventReader.count }
      end
    end

    context 'when creating a system hook' do
      let_it_be(:organization) { create(:organization) }
      let_it_be(:relation) { SystemHook.none }
      let(:hook_params) { { url: 'https://example.com/hook' } }

      it 'records the event at instance scope with the organization in the details', :aggregate_failures do
        expect { webhook_created.execute(hook_params, relation, organization) }
          .to change { AuditEvents::InstanceAuditEvent.count }.by(1)
          .and not_change { AuditEvents::UserAuditEvent.count }

        expect(AuditEvents::InstanceAuditEvent.last).to have_attributes(
          author_id: current_user.id,
          target_type: "SystemHook",
          target_details: "Hook #{SystemHook.last.id}",
          details: include(
            custom_message: "Created system hook",
            organization_id: organization.id
          )
        )
      end

      context 'when the acting user belongs to a different organization' do
        let_it_be(:other_organization) { create(:organization) }
        let_it_be(:current_user) { create(:user, organization: other_organization) }

        it "attributes the event to the hook's organization, not the user's" do
          webhook_created.execute(hook_params, relation, organization)

          expect(AuditEvents::InstanceAuditEvent.last.details[:organization_id]).to eq(organization.id)
        end
      end
    end

    context 'when creating a service hook for an instance-level integration' do
      let_it_be(:integration) { create(:integration, :instance) }
      let_it_be(:relation) { ServiceHook.none }
      let(:hook_params) do
        { url: 'https://example.com/hook', integration_id: integration.id, organization_id: integration.organization_id }
      end

      before do
        # User-scoped events are persisted only with an instance-level audit license,
        # since User does not respond to licensed_feature_available?.
        stub_licensed_features(admin_audit_log: true)
      end

      it 'keeps the acting user as the scope', :aggregate_failures do
        expect { webhook_created.execute(hook_params, relation) }
          .to change { AuditEvents::UserAuditEvent.where(user_id: current_user.id).count }.by(1)
          .and not_change { AuditEvents::InstanceAuditEvent.count }

        event = AuditEvents::UserAuditEvent.where(user_id: current_user.id).order(:id).last
        expect(event.details).not_to have_key(:organization_id)
      end
    end
  end
end
