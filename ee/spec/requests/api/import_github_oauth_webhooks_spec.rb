# frozen_string_literal: true

require 'spec_helper'

RSpec.describe API::ImportGithubOauthWebhooks, feature_category: :importers do
  describe 'POST /projects/:id/github/webhooks' do
    let_it_be(:project) { create(:project) }
    let_it_be_with_reload(:repository) do
      create(:import_sync_repository, :oauth, project: project, provider_webhook_xid: 42, webhook_secret: 'shh')
    end

    let(:body) { { action: 'opened' }.to_json }
    let(:signature) { "sha256=#{OpenSSL::HMAC.hexdigest('sha256', repository.webhook_secret, body)}" }
    let(:headers) do
      {
        'Content-Type' => 'application/json',
        'X-Hub-Signature-256' => signature,
        'X-GitHub-Delivery' => SecureRandom.uuid,
        'X-GitHub-Event' => 'pull_request'
      }
    end

    def make_request(custom_body = body, custom_headers = headers)
      post api("/projects/#{project.id}/github/webhooks"), params: custom_body, headers: custom_headers
    end

    it 'accepts a delivery with a valid signature' do
      expect(Gitlab::GithubImport::Logger).to receive(:info)
        .with(hash_including(Labkit::Fields::GL_PROJECT_ID => project.id))

      make_request

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'returns 429 with a Retry-After header once the per-project delivery limit is hit, with the limiter ' \
      'stubbed' do
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?)
        .with(anything, nil, :github_oauth_webhook_delivery, scope: { project: project }).and_return(true)

      make_request

      expect(response).to have_gitlab_http_status(:too_many_requests)
      expect(response.headers['Retry-After']).to eq(60)
      expect(response.headers['RateLimit-Name']).to eq('github_oauth_webhook_delivery')
    end

    it 'does not count an unverified delivery against the limit' do
      expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled_request?)

      make_request(body, headers.merge('X-Hub-Signature-256' => 'sha256=invalid'))

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'rejects a delivery with an invalid signature' do
      make_request(body, headers.merge('X-Hub-Signature-256' => 'sha256=invalid'))

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'rejects a delivery with a missing signature' do
      make_request(body, headers.except('X-Hub-Signature-256'))

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'rejects a blank signature header' do
      make_request(body, headers.merge('X-Hub-Signature-256' => ''))

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'rejects a same-length signature made with the wrong secret' do
      wrong_digest = OpenSSL::HMAC.hexdigest('sha256', 'a-different-secret-of-similar-len', body)

      make_request(body, headers.merge('X-Hub-Signature-256' => "sha256=#{wrong_digest}"))

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'rejects a tampered body' do
      tampered_body = { action: 'closed' }.to_json

      make_request(tampered_body, headers)

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns 404 for an unknown project' do
      post api("/projects/#{non_existing_record_id}/github/webhooks"), params: body, headers: headers

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns 404 for a project pending deletion, even with a valid signature' do
      other_project = create(:project, pending_delete: true)
      other_repository = create(:import_sync_repository, :oauth, project: other_project, webhook_secret: 'shh')
      other_digest = OpenSSL::HMAC.hexdigest('sha256', other_repository.webhook_secret, body)

      post api("/projects/#{other_project.id}/github/webhooks"),
        params: body, headers: headers.merge('X-Hub-Signature-256' => "sha256=#{other_digest}")

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns 404 for a hidden project, even with a valid signature' do
      other_project = create(:project, :hidden)
      other_repository = create(:import_sync_repository, :oauth, project: other_project, webhook_secret: 'shh')
      other_digest = OpenSSL::HMAC.hexdigest('sha256', other_repository.webhook_secret, body)

      post api("/projects/#{other_project.id}/github/webhooks"),
        params: body, headers: headers.merge('X-Hub-Signature-256' => "sha256=#{other_digest}")

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns 404 when the project has no webhook configured' do
      other_project = create(:project)

      post api("/projects/#{other_project.id}/github/webhooks"), params: body, headers: headers

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns 404 when the webhook secret is blank' do
      repository.update!(webhook_secret: nil)

      post api("/projects/#{project.id}/github/webhooks"), params: body, headers: {
        'Content-Type' => 'application/json',
        'X-Hub-Signature-256' => 'sha256=irrelevant',
        'X-GitHub-Delivery' => SecureRandom.uuid,
        'X-GitHub-Event' => 'pull_request'
      }

      expect(response).to have_gitlab_http_status(:not_found)
    end

    it 'returns 400 for a malformed JSON body' do
      malformed_body = '{'
      malformed_digest = OpenSSL::HMAC.hexdigest('sha256', repository.webhook_secret, malformed_body)
      bad_headers = headers.merge('X-Hub-Signature-256' => "sha256=#{malformed_digest}")

      make_request(malformed_body, bad_headers)

      expect(response).to have_gitlab_http_status(:bad_request)
    end

    it 'returns 400 both times for a repeated malformed delivery' do
      malformed_body = '{'
      malformed_digest = OpenSSL::HMAC.hexdigest('sha256', repository.webhook_secret, malformed_body)
      bad_headers = headers.merge('X-Hub-Signature-256' => "sha256=#{malformed_digest}")

      make_request(malformed_body, bad_headers)
      expect(response).to have_gitlab_http_status(:bad_request)

      make_request(malformed_body, bad_headers)
      expect(response).to have_gitlab_http_status(:bad_request)
    end

    it 'accepts an empty body with a signature computed over the empty string' do
      empty_digest = OpenSSL::HMAC.hexdigest('sha256', repository.webhook_secret, '')
      empty_headers = headers.merge('X-Hub-Signature-256' => "sha256=#{empty_digest}")

      expect(Gitlab::GithubImport::Logger).to receive(:info)

      make_request('', empty_headers)

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'accepts a body over 1 megabyte, since GitHub caps deliveries at 25 megabytes' do
      large_body = { data: 'a' * (1.megabyte + 1) }.to_json
      large_digest = OpenSSL::HMAC.hexdigest('sha256', repository.webhook_secret, large_body)

      expect(Gitlab::GithubImport::Logger).to receive(:info)

      make_request(large_body, headers.merge('X-Hub-Signature-256' => "sha256=#{large_digest}"))

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'returns 400 when the delivery id is missing' do
      make_request(body, headers.except('X-GitHub-Delivery'))

      expect(response).to have_gitlab_http_status(:bad_request)
    end

    it 'does not process a duplicate delivery twice' do
      expect(Gitlab::GithubImport::Logger).to receive(:info).once

      make_request
      expect(response).to have_gitlab_http_status(:ok)

      make_request
      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'processes a valid delivery even after a prior invalid-signature attempt with the same id' do
      shared_delivery = SecureRandom.uuid
      bad_headers = headers.merge('X-Hub-Signature-256' => 'sha256=invalid', 'X-GitHub-Delivery' => shared_delivery)
      good_headers = headers.merge('X-GitHub-Delivery' => shared_delivery)

      make_request(body, bad_headers)
      expect(response).to have_gitlab_http_status(:not_found)

      expect(Gitlab::GithubImport::Logger).to receive(:info)

      make_request(body, good_headers)
      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'logs a non-object payload without raising' do
      array_body = [1, 2].to_json
      array_digest = OpenSSL::HMAC.hexdigest('sha256', repository.webhook_secret, array_body)
      array_headers = headers.merge('X-Hub-Signature-256' => "sha256=#{array_digest}")

      expect(Gitlab::GithubImport::Logger).to receive(:info)
        .with(hash_including('github_action' => nil))

      make_request(array_body, array_headers)

      expect(response).to have_gitlab_http_status(:ok)
    end

    it 'does not trigger reconciliation for a disconnected repository' do
      repository.update!(authority_state: :disconnected, disconnect_reason: :token_revoked,
        restore_authority_state: :provider_canonical)

      expect(Gitlab::GithubImport::Logger).not_to receive(:info)

      make_request

      expect(response).to have_gitlab_http_status(:ok)
    end

    context 'when the project organization is under maintenance' do
      let_it_be_with_reload(:maintenance_organization) { create(:organization) }
      let_it_be(:maintenance_project) { create(:project, organization: maintenance_organization) }
      let_it_be_with_reload(:maintenance_repository) do
        create(:import_sync_repository, :oauth, project: maintenance_project, webhook_secret: 'shh')
      end

      before do
        stub_feature_flags(organization_maintenance_enforcement: true)
        maintenance_organization.start_maintenance(maintenance_reason: 'migration')
        maintenance_organization.confirm_maintenance
      end

      it 'returns service unavailable with a Retry-After header, even with a valid signature' do
        digest = OpenSSL::HMAC.hexdigest('sha256', maintenance_repository.webhook_secret, body)

        post api("/projects/#{maintenance_project.id}/github/webhooks"),
          params: body, headers: headers.merge('X-Hub-Signature-256' => "sha256=#{digest}")

        expect(response).to have_gitlab_http_status(:service_unavailable)
        expect(response.headers['Retry-After']).to eq('60')
      end
    end

    context 'when the webhook was registered by the import stage' do
      let_it_be(:imported_project) { create(:project) }
      let(:client) { instance_double(Gitlab::GithubImport::Client, parallel?: true) }
      let(:hook_config) { {} }

      before do
        create(:import_sync_repository, :oauth, project: imported_project)

        allow(client).to receive(:create_hook) do |_repository_xid, config, _options|
          hook_config.merge!(config)
          { id: 42 }
        end
        allow(Import::Sync::Repositories::ReconcileWorker).to receive(:perform_async)
        allow(Gitlab::GithubImport::Stage::FinishImportWorker).to receive(:perform_async)
      end

      it 'accepts a delivery sent to the registered URL and signed with the registered secret' do
        Gitlab::GithubImport::Stage::EnableContinuousSyncWorker.new.import(client, imported_project)

        digest = OpenSSL::HMAC.hexdigest('sha256', hook_config[:secret], body)

        post URI(hook_config[:url]).path, params: body,
          headers: headers.merge('X-Hub-Signature-256' => "sha256=#{digest}")

        expect(response).to have_gitlab_http_status(:ok)
      end
    end
  end
end
