# frozen_string_literal: true

require 'spec_helper'

RSpec.describe InstanceSshCertificates::DestroyService, :enable_admin_mode, feature_category: :source_code_management do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:admin) { create(:admin) }
  let_it_be(:certificate) do
    create(:instance_ssh_certificate, title: 'Instance CA', key: build(:rsa_key_4096).key)
  end

  let(:current_user) { admin }
  let(:certificate_id) { certificate.id }

  subject(:result) { described_class.new(certificate_id, current_user: current_user).execute }

  before do
    stub_licensed_features(admin_audit_log: true)
  end

  describe '#execute' do
    it 'records an instance audit event with the certificate details', :aggregate_failures do
      expect { result }.to change { AuditEvents::InstanceAuditEvent.count }.by(1)

      expect(result).to be_success
      expect(result.payload[:ssh_certificate]).to eq(certificate)
      expect(result.payload[:ssh_certificate]).to be_destroyed

      event = AuditEvents::InstanceAuditEvent.order(:id).last

      expect(event).to have_attributes(
        author_id: admin.id,
        author_name: admin.name,
        event_name: 'delete_instance_ssh_certificate',
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

    it 'excludes the CA key from logged data' do
      result

      event = AuditEvents::InstanceAuditEvent.order(:id).last
      expect(Gitlab::Json.dump(event.as_json)).not_to include(certificate.key, certificate.key.split[1])
    end

    shared_examples 'a failed deletion without an audit event' do
      it 'returns an error without auditing', :aggregate_failures do
        expect(Gitlab::Audit::Auditor).not_to receive(:audit)
        expect(result).to be_error
      end
    end

    context 'when the certificate does not exist' do
      let(:certificate_id) { non_existing_record_id }

      it_behaves_like 'a failed deletion without an audit event'
    end

    context 'when the certificate cannot be destroyed' do
      before do
        allow_next_found_instance_of(InstanceSshCertificate) do |record|
          allow(record).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed)
        end
      end

      it_behaves_like 'a failed deletion without an audit event'
    end

    context 'when the caller is unauthorized' do
      where(:current_user) { [nil, ref(:non_admin)] }

      let(:non_admin) { build_stubbed(:user) }

      with_them do
        it_behaves_like 'a failed deletion without an audit event'
      end
    end

    context 'when auditing is not licensed' do
      before do
        stub_licensed_features(admin_audit_log: false, audit_events: false, extended_audit_events: false)
      end

      it 'deletes the certificate without an audit event', :aggregate_failures do
        expect { result }.not_to change { AuditEvents::InstanceAuditEvent.count }

        expect(result).to be_success
        expect(result.payload[:ssh_certificate]).to be_destroyed
      end
    end
  end
end
