# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::Admin::SshCertificates, feature_category: :source_code_management do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:admin) { create(:admin) }

  let_it_be(:user) { create(:user) }
  let(:current_user) { admin }
  let(:admin_mode) { true }

  describe 'POST /admin/ssh_certificates' do
    let(:params) { { title: 'Engineering CA', key: build(:rsa_key_4096).key } }

    subject(:perform_request) do
      post api('/admin/ssh_certificates', current_user, admin_mode: admin_mode), params: params
    end

    before do
      stub_licensed_features(admin_audit_log: true)
    end

    it 'records an audit event for the created certificate', :aggregate_failures do
      expect { perform_request }.to change { AuditEvents::InstanceAuditEvent.count }.by(1)

      expect(response).to have_gitlab_http_status(:created)
      event = AuditEvents::InstanceAuditEvent.order(:id).last

      expect(event).to have_attributes(
        event_name: 'create_instance_ssh_certificate',
        author_id: admin.id,
        entity_path: 'gitlab_instance',
        target_id: json_response['id'],
        target_type: 'InstanceSshCertificate',
        target_details: params[:title]
      )
      expect(event.details[:custom_message]).to eq(
        "Created instance SSH certificate with id #{json_response['id']} and title #{params[:title]} " \
          "and fingerprint #{Gitlab::SSHPublicKey.new(params[:key]).fingerprint_sha256}"
      )
    end

    context 'when the caller is unauthorized' do
      where(:current_user, :admin_mode, :expected_status) do
        nil         | false | :unauthorized
        ref(:user)  | true  | :forbidden
        ref(:admin) | false | :forbidden
      end

      with_them do
        it 'rejects the request without creating a certificate or audit event', :aggregate_failures do
          expect { perform_request }.to not_change { InstanceSshCertificate.count }
            .and not_change { AuditEvents::InstanceAuditEvent.count }

          expect(response).to have_gitlab_http_status(expected_status)
        end
      end
    end
  end

  describe 'DELETE /admin/ssh_certificates/:id' do
    let_it_be(:certificate) do
      create(:instance_ssh_certificate, title: 'Engineering CA', key: build(:rsa_key_4096).key)
    end

    subject(:perform_request) do
      delete api("/admin/ssh_certificates/#{certificate.id}", current_user, admin_mode: admin_mode)
    end

    before do
      stub_licensed_features(admin_audit_log: true)
    end

    it 'records an audit event for the deleted certificate', :aggregate_failures do
      expect { perform_request }.to change { AuditEvents::InstanceAuditEvent.count }.by(1)

      expect(response).to have_gitlab_http_status(:no_content)
      event = AuditEvents::InstanceAuditEvent.order(:id).last

      expect(event).to have_attributes(
        event_name: 'delete_instance_ssh_certificate',
        author_id: admin.id,
        author_name: admin.name,
        entity_type: 'Gitlab::Audit::InstanceScope',
        entity_path: 'gitlab_instance',
        target_id: certificate.id,
        target_type: 'InstanceSshCertificate',
        target_details: certificate.title
      )
      expect(event.details[:custom_message]).to eq(
        "Deleted instance SSH certificate with id #{certificate.id} and title #{certificate.title} " \
          "and fingerprint SHA256:#{certificate.fingerprint}"
      )
    end

    context 'when the caller is unauthorized' do
      where(:current_user, :admin_mode, :expected_status) do
        nil         | false | :unauthorized
        ref(:user)  | true  | :forbidden
        ref(:admin) | false | :forbidden
      end

      with_them do
        it 'rejects the request without deleting a certificate or creating an audit event', :aggregate_failures do
          expect { perform_request }.to not_change { InstanceSshCertificate.count }
            .and not_change { AuditEvents::InstanceAuditEvent.count }

          expect(response).to have_gitlab_http_status(expected_status)
        end
      end
    end
  end
end
