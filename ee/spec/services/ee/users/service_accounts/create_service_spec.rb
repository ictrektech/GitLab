# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Users::ServiceAccounts::CreateService, feature_category: :user_management do
  let_it_be(:organization) { create(:organization) }
  let(:params) { { organization_id: organization.id } }

  subject(:service) { described_class.new(current_user, params) }

  describe '#execute audit events', :enable_admin_mode do
    let_it_be(:current_user) { create(:admin) }

    before do
      # Service account creation triggers multiple audit events through the
      # user creation chain. Allow them so the expectations below can focus
      # on the service_account_created event.
      allow(::Gitlab::Audit::Auditor).to receive(:audit).with(hash_including(name: 'user_created')).and_call_original
      allow(::Gitlab::Audit::Auditor).to receive(:audit).with(hash_including(name: 'email_created'))
      allow(::Gitlab::Audit::Auditor).to receive(:audit).with(hash_including(name: 'email_confirmation_sent'))
    end

    it 'logs a service_account_created audit event' do
      expect(::Gitlab::Audit::Auditor).to receive(:audit).with(hash_including(
        name: 'service_account_created'
      )).and_call_original

      service.execute
    end

    it 'sets the correct scope to the created user (instance-level)' do
      expect(::Gitlab::Audit::Auditor).to receive(:audit).with(hash_including(
        name: 'service_account_created'
      )) do |args|
        user = args[:target]
        expect(args[:author]).to eq(current_user)
        expect(args[:scope]).to eq(user)
        expect(args[:target_details]).to eq(user.username)
        expect(args[:message]).to eq("Created service account #{user.username}")
      end

      service.execute
    end

    it 'also fires the user_created audit event' do
      expect(::Gitlab::Audit::Auditor).to receive(:audit).with(hash_including(
        name: 'service_account_created'
      )).and_call_original
      expect(::Gitlab::Audit::Auditor).to receive(:audit).with(hash_including(
        name: 'user_created'
      )).and_call_original

      service.execute
    end

    context 'when creation fails due to user save error' do
      it 'does not log a service_account_created audit event' do
        allow_next_instance_of(User) do |user|
          allow(user).to receive(:save).and_return(false)
        end

        expect(::Gitlab::Audit::Auditor).not_to receive(:audit).with(hash_including(
          name: 'service_account_created'
        ))

        allow(::Gitlab::Audit::Auditor).to receive(:audit)

        service.execute
      end
    end
  end

  describe '#execute audit events when the current user is not an admin' do
    let_it_be(:current_user) { create(:user) }

    it 'does not log a service_account_created audit event' do
      expect(::Gitlab::Audit::Auditor).not_to receive(:audit).with(hash_including(
        name: 'service_account_created'
      ))

      service.execute
    end
  end
end
