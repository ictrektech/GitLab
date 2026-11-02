# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Github::Oauth::ReauthorizeService, feature_category: :importers do
  let_it_be_with_reload(:repository) { create(:import_sync_repository, :token_revoked) }

  let(:github_user) { Sawyer::Resource.new(Sawyer::Agent.new(''), id: repository.provider_account_xid) }
  let(:octokit) { instance_double(Octokit::Client, user: github_user) }
  let(:client) { instance_double(Gitlab::GithubImport::Client, parallel?: true, octokit: octokit) }
  let(:callback_url) { "https://gitlab.example.com/api/v4/projects/#{repository.project_id}/github/webhooks" }

  subject(:service) { described_class.new(repository, client: client, callback_url: callback_url) }

  describe '#execute' do
    before do
      allow(client).to receive(:create_hook).and_return({ id: 42 })
    end

    it 'restores the authority state and re-creates the webhook' do
      response = service.execute

      expect(response).to be_success
      expect(repository.reload).to be_provider_canonical
      expect(repository.disconnect_reason).to be_nil
      expect(repository.restore_authority_state).to be_nil
      expect(repository).to have_attributes(provider_webhook_xid: 42)
    end

    context 'when the repository is not disconnected' do
      before do
        repository.restore!
      end

      it 'returns an error without calling GitHub' do
        expect(client).not_to receive(:create_hook)

        response = service.execute

        expect(response).to be_error
      end
    end

    context 'when the reauthorized account does not match the original connection' do
      let(:github_user) { Sawyer::Resource.new(Sawyer::Agent.new(''), id: repository.provider_account_xid + 1) }

      it 'returns an error and leaves the repository disconnected' do
        expect(client).not_to receive(:create_hook)

        response = service.execute

        expect(response).to be_error
        expect(response.reason).to eq(:account_mismatch)
        expect(repository.reload).to be_disconnected
      end
    end

    context 'when GitHub rejects the re-created webhook' do
      before do
        allow(client).to receive(:create_hook).and_raise(Octokit::UnprocessableEntity)
      end

      it 'returns an error and puts the repository back into the disconnected state' do
        response = service.execute

        expect(response).to be_error
        expect(response.reason).to eq(:provider_error)
        expect(repository.reload).to be_disconnected
        expect(repository).to be_disconnected_because_token_revoked
        expect(repository).to be_restore_to_provider_canonical
      end
    end
  end
end
