# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Organizations::HardDeleteService, feature_category: :organization do
  let_it_be(:user) { create(:user) }
  let_it_be_with_reload(:organization) { create(:organization) }

  before_all do
    create(:organization_user, :owner, organization: organization, user: user)
  end

  subject(:response) { described_class.new(organization, current_user: user).execute }

  describe '#execute' do
    context 'with a workforce hierarchy' do
      let!(:hierarchy) { create(:workforce_hierarchy, :instance_level, organization: organization) }
      let!(:person) { create(:workforce_person, hierarchy: hierarchy) }
      let!(:other_person) { create(:workforce_person) }

      before do
        organization.soft_delete!(transition_user: user)
        allow(organization).to receive(:destroy!).and_return(true)
      end

      it 'deletes the hierarchy and its people before the organization' do
        expect(::Workforce::Hierarchy).to receive(:delete_for_tenant)
          .with(organization: organization).ordered.and_call_original
        expect(organization).to receive(:destroy!).ordered

        response

        expect(::Workforce::Hierarchy.exists?(hierarchy.id)).to be(false)
        expect(::Workforce::Person.all).to contain_exactly(other_person)
      end
    end

    context 'for audit events' do
      before do
        stub_licensed_features(admin_audit_log: true)
        organization.soft_delete!(transition_user: user)
        # Avoid the FK constraint between organizations and organization_users;
        # cascade cleanup is out of scope for the initial service plumbing.
        allow(organization).to receive(:destroy!).and_return(true)
      end

      it 'logs an audit event with instance scope' do
        expect(::Gitlab::Audit::Auditor).to receive(:audit).with(
          hash_including(
            name: 'organization_hard_deleted',
            author: user,
            scope: instance_of(::Gitlab::Audit::InstanceScope),
            target: organization,
            message: "Hard deleted organization '#{organization.name}'"
          )
        ).and_call_original

        expect { response }.to change { AuditEventReader.count }.by(1)
      end

      context 'when destroy! raises' do
        before do
          allow(organization).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed, 'boom')
        end

        it 'does not log an audit event' do
          expect(::Gitlab::Audit::Auditor).not_to receive(:audit)

          expect { response }.to raise_error(ActiveRecord::RecordNotDestroyed)
        end
      end
    end
  end
end
