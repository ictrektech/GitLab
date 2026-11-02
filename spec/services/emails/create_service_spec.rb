# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Emails::CreateService, feature_category: :user_management do
  let_it_be(:user) { create(:user) }

  let(:opts) { { email: 'new@email.com', user: user } }

  subject(:service) { described_class.new(user, opts) }

  describe '#execute' do
    it 'creates an email with valid attributes' do
      expect { service.execute }.to change { Email.count }.by(1)
      expect(Email.where(opts)).not_to be_empty
    end

    it 'creates an email with additional attributes' do
      expect { service.execute(confirmation_token: 'abc') }.to change { Email.count }.by(1)
      expect(Email.find_by(opts).confirmation_token).to eq 'abc'
    end

    it 'has the right user association' do
      service.execute

      expect(user.emails).to include(Email.find_by(opts))
    end

    context 'when an instance admin asks to skip confirmation' do
      let_it_be(:instance_admin) { create(:admin) }

      let(:opts) { { email: 'new@email.com', user: user, skip_confirmation: true } }

      subject(:service) { described_class.new(instance_admin, opts) }

      context 'when in admin mode', :enable_admin_mode do
        it 'confirms the email' do
          expect(service.execute).to be_confirmed
        end
      end

      context 'when not in admin mode' do
        it 'does not confirm the email' do
          expect(service.execute).not_to be_confirmed
        end
      end
    end

    it 'sends a notification to the user' do
      expect_next_instance_of(NotificationService) do |notification_service|
        expect(notification_service).to receive(:new_email_address_added)
      end

      service.execute
    end

    it 'does not send a notification when the email is not persisted' do
      allow_next_instance_of(NotificationService) do |notification_service|
        expect(notification_service).not_to receive(:new_email_address_added)
      end

      service.execute(email: 'invalid@@example.com')
    end

    it 'does not send a notification email when the email is the primary, because we are creating the user' do
      allow_next_instance_of(NotificationService) do |notification_service|
        expect(notification_service).not_to receive(:new_email_address_added)
      end

      # This is here to ensure that the service is actually called.
      allow_next_instance_of(described_class) do |create_service|
        expect(create_service).to receive(:execute).and_call_original
      end

      create(:user)
    end
  end
end
