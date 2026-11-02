# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Authn::IamService::RemoteOauthApplication, feature_category: :system_access do
  describe '.from_managed_client' do
    let(:created_at) { Time.zone.parse('2026-10-01T10:00:00Z') }
    let(:managed_client) do
      ::Gitlab::Iam::Auth::V1::ManagedClient.new(
        client_id: 'remote-client',
        client_name: 'Remote app',
        owner: 'Jane Doe',
        dynamic: false,
        created_at: Google::Protobuf::Timestamp.new(seconds: created_at.to_i)
      )
    end

    subject(:application) { described_class.from_managed_client(managed_client) }

    it 'copies the fields the Authorized applications page shows', :aggregate_failures do
      expect(application).to have_attributes(
        client_id: 'remote-client',
        name: 'Remote app',
        owner_label: 'Jane Doe',
        created_at: created_at
      )
      expect(application).not_to be_dynamic
      expect(application).not_to be_placeholder
    end

    context 'when the client has no owner label' do
      before do
        managed_client.owner = ''
      end

      it 'leaves the owner label nil' do
        expect(application.owner_label).to be_nil
      end
    end

    context 'when the client is dynamically registered' do
      before do
        managed_client.dynamic = true
      end

      it 'is dynamic' do
        expect(application).to be_dynamic
      end
    end

    context 'when the client has no name' do
      before do
        managed_client.client_name = ''
      end

      it 'falls back to the client id so the row still has a label' do
        expect(application.name).to eq('remote-client')
      end
    end
  end

  describe '.placeholder' do
    subject(:application) { described_class.placeholder('remote-client') }

    it 'is named after the client id and carries no details', :aggregate_failures do
      expect(application).to be_placeholder
      expect(application).to have_attributes(client_id: 'remote-client', name: 'remote-client', owner_label: nil,
        created_at: nil)
      expect(application).not_to be_dynamic
    end
  end
end
