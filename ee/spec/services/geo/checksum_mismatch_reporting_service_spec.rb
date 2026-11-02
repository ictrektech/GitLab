# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Geo::ChecksumMismatchReportingService, :geo, feature_category: :geo_replication do
  include ::EE::GeoHelpers

  let_it_be(:primary) { create(:geo_node, :primary) }
  let_it_be(:secondary) do
    create(:geo_node, checksum_mismatch_report_threshold: 3, checksum_mismatch_self_heal_cooldown_minutes: 60)
  end

  subject(:service) { described_class.new(secondary) }

  before do
    stub_current_geo_node(secondary)
    allow(Gitlab::Geo).to receive(:repository_replicator_classes).and_return([Geo::ProjectRepositoryReplicator])
  end

  def stub_http_success
    allow(Gitlab::HTTP).to receive(:perform_request)
      .and_return(double(success?: true, parsed_response: { 'message' => 'OK' })) # rubocop:disable RSpec/VerifiedDoubles -- generic HTTP response double
  end

  describe '#execute' do
    context 'when there are no persistent checksum mismatches' do
      it 'does not perform a request and returns false' do
        expect(Gitlab::HTTP).not_to receive(:perform_request)

        expect(service.execute).to be(false)
      end
    end

    context 'when a registry has mismatched below the threshold' do
      before do
        create(:geo_project_repository_registry, :verification_failed, checksum_mismatch: true,
          verification_retry_count: 2)
      end

      it 'does not report it' do
        expect(Gitlab::HTTP).not_to receive(:perform_request)

        expect(service.execute).to be(false)
      end
    end

    context 'when a registry has persistently mismatched at or above the threshold' do
      let!(:registry) do
        create(:geo_project_repository_registry, :verification_failed,
          checksum_mismatch: true,
          verification_retry_count: 3,
          verification_checksum_mismatched: 'abc123')
      end

      it 'reports it to the primary' do
        stub_http_success

        expect(Gitlab::HTTP).to receive(:perform_request).with(
          Net::HTTP::Post,
          primary.checksum_mismatch_reports_url,
          hash_including(body: hash_including(
            geo_node_id: secondary.id,
            failures: [hash_including(
              error_type: 'checksum_mismatch',
              replicable_name: 'project_repository',
              replicable_id: registry.model_record_id,
              verification_retry_count: 3,
              context: { primary_checksum_at_mismatch: 'abc123' }
            )]
          ))
        )

        expect(service.execute).to be_truthy
      end

      it 'does not report the same registry again within the cooldown window' do
        stub_http_success

        service.execute

        expect(Gitlab::HTTP).not_to receive(:perform_request)

        expect(described_class.new(secondary).execute).to be(false)
      end

      it 'sets the dedup marker to expire after the cooldown window' do
        stub_http_success

        service.execute

        ttl = Gitlab::Redis::SharedState.with do |redis|
          redis.ttl("geo:checksum_mismatch_reported:project_repository:#{registry.model_record_id}")
        end

        expect(ttl).to be_within(5).of(60.minutes.to_i)
      end

      it 'reports the registry again once the dedup marker has expired' do
        stub_http_success

        service.execute

        Gitlab::Redis::SharedState.with do |redis|
          redis.del("geo:checksum_mismatch_reported:project_repository:#{registry.model_record_id}")
        end

        expect(Gitlab::HTTP).to receive(:perform_request).and_return(
          double(success?: true, parsed_response: { 'message' => 'OK' }) # rubocop:disable RSpec/VerifiedDoubles -- generic HTTP response double
        )

        expect(described_class.new(secondary).execute).to be_truthy
      end
    end

    context 'when mismatches across replicable types exceed the primary request limit' do
      let(:limit) { 2 }
      let(:requests) { [] }

      let!(:project_registries) do
        create_list(:geo_project_repository_registry, limit, :verification_failed,
          checksum_mismatch: true, verification_retry_count: 3, verification_checksum_mismatched: 'abc')
      end

      let!(:container_registries) do
        create_list(:geo_container_repository_registry, limit, :verification_failed,
          checksum_mismatch: true, verification_retry_count: 3, verification_checksum_mismatched: 'def')
      end

      before do
        stub_const("#{described_class}::BATCH_SIZE", limit)
        stub_const('Geo::VerificationFailureReportWorker::MAX_FAILURES_PER_REQUEST', limit)

        allow(Gitlab::Geo).to receive(:repository_replicator_classes)
          .and_return([Geo::ProjectRepositoryReplicator, Geo::ContainerRepositoryReplicator])

        # Mimics the primary's POST /geo/failures size check
        allow(Gitlab::HTTP).to receive(:perform_request) do |_method, _url, options|
          failures = options[:body][:failures]
          requests << failures

          if failures.size > Geo::VerificationFailureReportWorker::MAX_FAILURES_PER_REQUEST
            double(success?: false, code: 400, message: 'Bad Request', # rubocop:disable RSpec/VerifiedDoubles -- generic HTTP response double
              parsed_response: { 'message' => '400 Bad request - Too many failures' })
          else
            double(success?: true, parsed_response: { 'message' => 'OK' }) # rubocop:disable RSpec/VerifiedDoubles -- generic HTTP response double
          end
        end
      end

      def reported?(replicable_name, registry)
        Gitlab::Redis::SharedState.with do |redis|
          redis.exists?("geo:checksum_mismatch_reported:#{replicable_name}:#{registry.model_record_id}")
        end
      end

      it 'never sends more failures in one request than the primary accepts' do
        service.execute

        expect(requests.map(&:size)).to all(be <= limit)
      end

      it 'reports every candidate and returns true' do
        expect(service.execute).to be(true)

        expect(requests.flatten.pluck(:replicable_name).tally)
          .to eq('project_repository' => limit, 'container_repository' => limit)
        expect(project_registries).to all(satisfy { |r| reported?('project_repository', r) })
        expect(container_registries).to all(satisfy { |r| reported?('container_repository', r) })
      end

      context 'when the primary rejects one of the requests' do
        before do
          allow(Gitlab::HTTP).to receive(:perform_request).and_return(
            double(success?: false, code: 500, message: 'Internal Server Error', parsed_response: {}), # rubocop:disable RSpec/VerifiedDoubles -- generic HTTP response double
            double(success?: true, parsed_response: { 'message' => 'OK' }) # rubocop:disable RSpec/VerifiedDoubles -- generic HTTP response double
          )
        end

        it 'still sends the remaining requests and only marks the accepted ones as reported' do
          expect(service.execute).to be(false)

          expect(project_registries).to all(satisfy { |r| !reported?('project_repository', r) })
          expect(container_registries).to all(satisfy { |r| reported?('container_repository', r) })
        end
      end
    end
  end

  describe 'BATCH_SIZE' do
    it 'matches the number of failures the primary accepts per request' do
      expect(described_class::BATCH_SIZE).to eq(Geo::VerificationFailureReportWorker::MAX_FAILURES_PER_REQUEST)
    end
  end
end
