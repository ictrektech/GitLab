# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Github::Oauth::WebhookManagementService, feature_category: :importers do
  include ExclusiveLeaseHelpers

  let_it_be_with_reload(:repository) { create(:import_sync_repository) }

  let(:client) { instance_double(Gitlab::GithubImport::Client, parallel?: true) }
  let(:callback_url) { "https://gitlab.example.com/api/v4/projects/#{repository.project_id}/github/webhooks" }
  let(:lock_key) { "import_sync:repository:#{repository.id}:webhook" }
  let(:log_payload) do
    {
      Labkit::Fields::GL_PROJECT_ID => repository.project_id,
      'import_sync_repository_id' => repository.id
    }
  end

  subject(:service) { described_class.new(repository, client: client, callback_url: callback_url) }

  describe '#initialize' do
    context 'when the client is not parallel' do
      let(:client) { instance_double(Gitlab::GithubImport::Client, parallel?: false) }

      it 'raises an ArgumentError' do
        expect { service }.to raise_error(ArgumentError, 'client must be parallel')
      end
    end
  end

  describe '#enable' do
    before do
      allow(SecureRandom).to receive(:hex).with(32).and_return('generated-secret')
    end

    it 'creates the hook on GitHub and records its id and secret' do
      expect(client).to receive(:create_hook).with(
        repository.provider_repository_xid,
        { url: callback_url, content_type: 'json', secret: 'generated-secret' },
        { events: %w[push pull_request pull_request_review_comment], active: true }
      ).and_return({ id: 42 })

      service.enable

      expect(repository.reload).to have_attributes(provider_webhook_xid: 42, webhook_secret: 'generated-secret')
    end

    it 'clears a stale auth failure count on success' do
      repository.update!(consecutive_auth_failures: 1)
      allow(client).to receive(:create_hook).and_return({ id: 42 })

      service.enable

      expect(repository.reload.consecutive_auth_failures).to eq(0)
    end

    context 'when the repository is disconnected' do
      before do
        repository.disconnect!(:token_revoked)
      end

      it 'does not create a hook' do
        expect(client).not_to receive(:create_hook)

        service.enable
      end
    end

    context 'when the repository was released or stopped' do
      where(:state) { [[:bootstrap_canceled], [:gitlab_canonical], [:cutting_over], [:cutover_failed]] }

      with_them do
        it 'does not create a hook' do
          Import::Sync::Repository.find(repository.id).update_column(:authority_state, state)

          expect(client).not_to receive(:create_hook)

          service.enable

          expect(repository.reload.provider_webhook_xid).to be_nil
        end
      end
    end

    context 'when GitHub rejects the token as unauthorized' do
      before do
        allow(client).to receive(:create_hook).and_raise(Octokit::Unauthorized)
      end

      it 'records an auth failure and re-raises' do
        expect { service.enable }.to raise_error(Octokit::Unauthorized)

        expect(repository.reload.consecutive_auth_failures).to eq(1)
      end

      it 'disconnects once the failure threshold is reached' do
        max = Import::Sync::Repository::MAX_CONSECUTIVE_AUTH_FAILURES

        max.times { expect { service.enable }.to raise_error(Octokit::Unauthorized) }

        expect(repository.reload).to be_disconnected
        expect(repository).to be_disconnected_because_token_revoked
      end
    end

    context 'when a webhook is already recorded' do
      before do
        repository.update!(provider_webhook_xid: 42, webhook_secret: 'existing-secret')
      end

      it 'does not create another hook' do
        expect(client).not_to receive(:create_hook)

        service.enable

        expect(repository.reload.webhook_secret).to eq('existing-secret')
      end
    end

    context 'when another process recorded a webhook after this record was loaded' do
      before do
        Import::Sync::Repository.find(repository.id).update!(provider_webhook_xid: 42, webhook_secret: 'other-secret')
      end

      it 'does not create another hook' do
        expect(client).not_to receive(:create_hook)

        service.enable
      end
    end

    context 'when another process holds the webhook lock' do
      before do
        stub_exclusive_lease_taken(lock_key, timeout: described_class::LEASE_TTL)
      end

      it 'raises without calling GitHub' do
        expect(client).not_to receive(:create_hook)

        expect { service.enable }.to raise_error(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
      end
    end

    context 'when GitHub rejects the hook' do
      it 'raises and records nothing' do
        allow(client).to receive(:create_hook).and_raise(Octokit::UnprocessableEntity)

        expect { service.enable }.to raise_error(Octokit::UnprocessableEntity)
        expect(repository.reload).to have_attributes(provider_webhook_xid: nil, webhook_secret: nil)
      end
    end

    context 'when saving the record fails' do
      before do
        allow(client).to receive(:create_hook).and_return({ id: 42 })
        allow(repository).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
      end

      it 'deletes the just-created hook and re-raises' do
        expect(client).to receive(:delete_hook).with(repository.provider_repository_xid, 42)

        expect { service.enable }.to raise_error(ActiveRecord::RecordInvalid)
      end

      context 'when deleting the hook also fails' do
        it 'logs the failed delete and re-raises the original error' do
          allow(client).to receive(:delete_hook).and_raise(Octokit::InternalServerError)
          expect(Gitlab::GithubImport::Logger).to receive(:warn).with(
            hash_including(log_payload)
          )

          expect { service.enable }.to raise_error(ActiveRecord::RecordInvalid)
        end
      end
    end
  end

  describe '#disable' do
    context 'when a webhook is recorded' do
      before do
        repository.update!(provider_webhook_xid: 42, webhook_secret: 'existing-secret')
      end

      it 'deletes the hook on GitHub and clears the record' do
        expect(client).to receive(:delete_hook).with(repository.provider_repository_xid, 42)

        service.disable

        expect(repository.reload).to have_attributes(provider_webhook_xid: nil, webhook_secret: nil)
      end

      [Octokit::NotFound, Octokit::Unauthorized, Octokit::Forbidden].each do |error|
        context "when GitHub raises #{error}" do
          it 'logs the failure and still clears the record' do
            allow(client).to receive(:delete_hook).and_raise(error)
            expect(Gitlab::GithubImport::Logger).to receive(:warn).with(
              hash_including(log_payload)
            )

            service.disable

            expect(repository.reload).to have_attributes(provider_webhook_xid: nil, webhook_secret: nil)
          end
        end
      end

      context 'when GitHub fails with a temporary error' do
        it 'raises and keeps the record so the caller can retry' do
          allow(client).to receive(:delete_hook).and_raise(Octokit::InternalServerError)

          expect { service.disable }.to raise_error(Octokit::InternalServerError)
          expect(repository.reload).to have_attributes(provider_webhook_xid: 42, webhook_secret: 'existing-secret')
        end
      end

      context 'when another process holds the webhook lock' do
        before do
          stub_exclusive_lease_taken(lock_key, timeout: described_class::LEASE_TTL)
        end

        it 'raises without calling GitHub' do
          expect(client).not_to receive(:delete_hook)

          expect { service.disable }.to raise_error(Gitlab::ExclusiveLeaseHelpers::FailedToObtainLockError)
        end
      end
    end

    context 'when no webhook is recorded' do
      it 'does not call GitHub' do
        expect(client).not_to receive(:delete_hook)

        service.disable
      end
    end
  end
end
