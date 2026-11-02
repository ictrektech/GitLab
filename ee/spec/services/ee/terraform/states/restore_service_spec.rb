# frozen_string_literal: true

require 'spec_helper'
RSpec.describe Terraform::States::RestoreService, feature_category: :infrastructure_as_code do
  let_it_be(:project) { create(:project) }
  let_it_be(:user) { create(:user, maintainer_of: project) }
  let_it_be_with_reload(:state) do
    create(:terraform_state, project: project, deleted_at: Time.current)
  end

  context 'for audit events' do
    it 'saves the restore audit event' do
      allow(::Gitlab::Audit::Auditor).to receive(:audit)
      expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
        hash_including(
          name: 'terraform_state_restored',
          author: user,
          scope: project,
          target: state,
          message: 'Terraform state restored'
        )
      ).and_call_original
      expect { described_class.new(state, current_user: user).execute }
        .to change { AuditEventReader.count }.by(1)
    end
  end
end
