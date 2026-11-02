# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Terraform::States::DestroyService, :geo, feature_category: :infrastructure_as_code do
  include EE::GeoHelpers

  let_it_be_with_refind(:state) { create(:terraform_state, :with_version, :deletion_in_progress) }
  let_it_be(:version) { state.versions.first }

  describe '#execute' do
    subject(:result) { described_class.new(state).execute }

    before do
      stub_feature_flags(terraform_state_delayed_deletion: false)
    end

    context 'when on a Geo primary with secondaries' do
      let_it_be(:primary) { create(:geo_node, :primary) }
      let_it_be(:secondary) { create(:geo_node) }

      before do
        stub_current_geo_node(primary)
      end

      it 'creates deletion events for associated state versions' do
        expect(Geo::TerraformStateVersionReplicator)
          .to receive(:bulk_create_delete_events_async)
          .with([version.replicator.deleted_params])

        result
      end
    end

    context 'when Geo is not enabled' do
      it 'does not create deletion events' do
        expect(Geo::TerraformStateVersionReplicator).not_to receive(:bulk_create_delete_events_async)

        result
      end
    end
  end

  describe 'audit events for permanent deletion', :aggregate_failures do
    let_it_be(:project) { create(:project) }
    let_it_be(:user) { create(:user, maintainer_of: project) }

    let(:permanent_state) { create(:terraform_state, :with_version, project: project, deleted_at: Time.current) }

    subject(:execute) { described_class.new(permanent_state, permanent: true, current_user: user).execute }

    it 'records the audit event once the state is destroyed' do
      allow(::Gitlab::Audit::Auditor).to receive(:audit)
      expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
        hash_including(
          name: 'terraform_state_permanently_deleted',
          author: user,
          scope: project,
          target: permanent_state,
          message: 'Terraform state permanently deleted'
        )
      ).and_call_original

      expect { execute }.to change { AuditEventReader.count }.by(1)
      expect(Terraform::State.exists?(permanent_state.id)).to be(false)
    end

    context 'when the state is restored before the worker runs' do
      before do
        permanent_state.update!(deleted_at: nil)
      end

      it 'does not record an audit event' do
        expect { execute }.not_to change { AuditEventReader.count }
        expect(Terraform::State.exists?(permanent_state.id)).to be(true)
      end
    end

    context 'when the deletion is not permanent' do
      subject(:execute) { described_class.new(permanent_state, current_user: user).execute }

      before do
        stub_feature_flags(terraform_state_delayed_deletion: false)
      end

      it 'does not record the permanent deletion audit event' do
        expect { execute }.not_to change { AuditEventReader.count }
      end
    end

    context 'when no user is given' do
      subject(:execute) { described_class.new(permanent_state, permanent: true).execute }

      it 'destroys the state without recording an audit event' do
        expect { execute }.not_to change { AuditEventReader.count }
        expect(Terraform::State.exists?(permanent_state.id)).to be(false)
      end
    end
  end
end
