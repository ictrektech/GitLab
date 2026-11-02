# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Import::Sync::Github::Oauth::WebhookReceiverService, feature_category: :importers do
  let_it_be(:project) { create(:project) }
  let_it_be_with_reload(:repository) do
    create(:import_sync_repository, :oauth, project: project, provider_webhook_xid: 42, webhook_secret: 'shh')
  end

  let(:body) { { action: 'opened' }.to_json }
  let(:signature) { "sha256=#{OpenSSL::HMAC.hexdigest('sha256', repository.webhook_secret, body)}" }
  let(:headers) do
    {
      'X-Hub-Signature-256' => signature,
      'X-GitHub-Delivery' => SecureRandom.uuid,
      'X-GitHub-Event' => 'pull_request'
    }
  end

  let(:request) do
    instance_double(
      Grape::Request, headers: headers, body: StringIO.new(body), get_header: nil,
      ip: '198.51.100.1', request_method: 'POST', GET: {}, fullpath: '/api/v4/projects/1/github/webhooks'
    )
  end

  subject(:service) { described_class.new(project, request: request) }

  describe '#execute' do
    it 'returns a success response and logs the delivery' do
      expect(Gitlab::GithubImport::Logger).to receive(:info)
        .with(hash_including(Labkit::Fields::GL_PROJECT_ID => project.id))

      expect(service.execute).to be_success
    end

    it 'returns a rate_limited error once the per-project delivery limit is hit, with the limiter stubbed' do
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?)
        .with(request, nil, :github_oauth_webhook_delivery, scope: { project: project }).and_return(true)

      result = service.execute

      expect(result).to be_error
      expect(result.reason).to eq(:rate_limited)
    end

    it 'does not process the delivery when rate limited, with the limiter stubbed' do
      allow(Gitlab::ApplicationRateLimiter).to receive(:throttled_request?).and_return(true)

      expect(Gitlab::GithubImport::Logger).not_to receive(:info)

      service.execute
    end

    it 'does not count an unsigned delivery against the limit' do
      expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled_request?)

      result = described_class.new(
        project, request: instance_double(Grape::Request, headers: {}, body: StringIO.new(body))
      ).execute

      expect(result).to be_error
      expect(result.reason).to eq(:not_found)
    end

    context 'with the real limit applied', :freeze_time, :clean_gitlab_redis_rate_limiting do
      let_it_be(:other_project) { create(:project) }
      let_it_be_with_reload(:other_repository) do
        create(:import_sync_repository, :oauth, project: other_project, webhook_secret: 'other-shh')
      end

      let(:other_signature) { "sha256=#{OpenSSL::HMAC.hexdigest('sha256', other_repository.webhook_secret, body)}" }
      let(:other_request) do
        instance_double(
          Grape::Request,
          headers: headers.merge('X-Hub-Signature-256' => other_signature),
          body: StringIO.new(body),
          get_header: nil
        )
      end

      it 'throttles the 301st verified delivery for a project but not another project' do
        allow(Gitlab::GithubImport::Logger).to receive(:info)

        limit = Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits.limit_for(
          described_class::RATE_LIMIT_KEY
        )
        limit.times { expect(service.execute).to be_success }

        expect(service.execute.reason).to eq(:rate_limited)
        expect(described_class.new(other_project, request: other_request).execute).to be_success
      end
    end

    it 'returns a not_found error when no repository is configured' do
      other_project = create(:project)
      other_request = instance_double(Grape::Request, headers: headers, body: StringIO.new(body))

      result = described_class.new(other_project, request: other_request).execute

      expect(result).to be_error
      expect(result.reason).to eq(:not_found)
    end

    it 'accepts a payload larger than 1 megabyte, since GitHub caps deliveries at 25 megabytes' do
      large_body = { action: 'opened', description: 'a' * 1.2.megabytes }.to_json
      large_signature = "sha256=#{OpenSSL::HMAC.hexdigest('sha256', repository.webhook_secret, large_body)}"
      large_request = instance_double(
        Grape::Request,
        headers: headers.merge('X-Hub-Signature-256' => large_signature),
        body: StringIO.new(large_body)
      )

      allow(Gitlab::GithubImport::Logger).to receive(:info)

      expect(described_class.new(project, request: large_request).execute).to be_success
    end

    it 'rejects a body over 25 megabytes with a bad_request error before checking the project' do
      oversized_body = 'a' * (25.megabytes + 1)
      oversized_request = instance_double(Grape::Request, headers: headers, body: StringIO.new(oversized_body))

      result = described_class.new(project, request: oversized_request).execute

      expect(result).to be_error
      expect(result.reason).to eq(:bad_request)
    end

    it 'rejects an oversized body the same way for a project with no GitHub sync configured, so the ' \
      'response does not reveal whether sync is configured' do
      other_project = create(:project)
      oversized_body = 'a' * (25.megabytes + 1)
      oversized_request = instance_double(Grape::Request, headers: headers, body: StringIO.new(oversized_body))

      result = described_class.new(other_project, request: oversized_request).execute

      expect(result).to be_error
      expect(result.reason).to eq(:bad_request)
    end

    it 'returns a bad_request error for malformed JSON' do
      malformed_body = '{'
      malformed_digest = OpenSSL::HMAC.hexdigest('sha256', repository.webhook_secret, malformed_body)
      malformed_headers = headers.merge('X-Hub-Signature-256' => "sha256=#{malformed_digest}")
      malformed_request = instance_double(
        Grape::Request, headers: malformed_headers, body: StringIO.new(malformed_body)
      )

      result = described_class.new(project, request: malformed_request).execute

      expect(result).to be_error
      expect(result.reason).to eq(:bad_request)
    end

    context 'when a review comment is deleted on GitHub' do
      let(:body) { { action: 'deleted', comment: { id: 402 } }.to_json }
      let(:headers) { super().merge('X-GitHub-Event' => 'pull_request_review_comment') }

      it 'enqueues the removal of its note' do
        expect(Import::Sync::Repositories::RemoveDeletedReviewCommentWorker)
          .to receive(:perform_async).with(repository.id, 402)

        expect(service.execute).to be_success
      end

      context 'when the comment is edited instead' do
        let(:body) { { action: 'edited', comment: { id: 402 } }.to_json }

        it 'does not enqueue a removal' do
          expect(Import::Sync::Repositories::RemoveDeletedReviewCommentWorker).not_to receive(:perform_async)

          expect(service.execute).to be_success
        end
      end

      context 'when the comment id is missing' do
        let(:body) { { action: 'deleted', comment: {} }.to_json }

        it 'does not enqueue a removal' do
          expect(Import::Sync::Repositories::RemoveDeletedReviewCommentWorker).not_to receive(:perform_async)

          expect(service.execute).to be_success
        end
      end
    end

    it 'does not enqueue a removal for other events' do
      expect(Import::Sync::Repositories::RemoveDeletedReviewCommentWorker).not_to receive(:perform_async)

      service.execute
    end

    it 'releases the delivery lease when processing raises, so a retry is not blocked' do
      allow(Gitlab::GithubImport::Logger).to receive(:info).and_raise(StandardError, 'boom')

      expect { service.execute }.to raise_error(StandardError, 'boom')

      request.body.rewind
      allow(Gitlab::GithubImport::Logger).to receive(:info)

      expect(described_class.new(project, request: request).execute).to be_success
    end

    describe 'delivery counter' do
      let(:counter) { instance_double(Prometheus::Client::Counter, increment: nil) }

      before do
        allow(Gitlab::Metrics).to receive(:counter).and_call_original
        allow(Gitlab::Metrics).to receive(:counter).with(:gitlab_import_sync_webhook_deliveries_total, anything)
          .and_return(counter)
        allow(Gitlab::GithubImport::Logger).to receive(:info)
      end

      it 'counts a processed delivery' do
        service.execute

        expect(counter).to have_received(:increment).with(result: 'success').once
      end

      it 'counts a rejected delivery by its error reason' do
        described_class.new(project, request: instance_double(Grape::Request, headers: {}, body: StringIO.new(body)))
          .execute

        expect(counter).to have_received(:increment).with(result: 'not_found').once
      end

      it 'counts a delivery that raises' do
        allow(Gitlab::GithubImport::Logger).to receive(:info).and_raise(StandardError)

        expect { service.execute }.to raise_error(StandardError)

        expect(counter).to have_received(:increment).with(result: 'error').once
      end
    end
  end
end
