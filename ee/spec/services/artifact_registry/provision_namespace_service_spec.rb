# frozen_string_literal: true

require 'spec_helper'

# Every claim that reaches provisioning counts against the organization's rate
# limit, so the counter is cleaned per example rather than shared across them.
RSpec.describe ArtifactRegistry::ProvisionNamespaceService, :clean_gitlab_redis_rate_limiting,
  feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  let_it_be_with_reload(:organization) { create(:organization) }
  let_it_be(:billing_group) { create(:group, organization: organization) }

  let(:slug) { 'my-slug' }
  let(:ar_namespace_id) { 'a1b2c3d4-0000-0000-0000-000000000000' }
  let(:ar_namespace) { instance_double(ArtifactRegistry::Namespace, id: ar_namespace_id) }
  let(:service_credential) { instance_double(ArtifactRegistry::ServiceCredential) }
  let(:client) { instance_double(ArtifactRegistry::Client) }

  subject(:execute) do
    described_class.new(organization: organization, slug: slug, service_credential: service_credential).execute
  end

  before do
    allow(ArtifactRegistry::Client).to receive(:new).with(service_credential: service_credential).and_return(client)
    allow(client).to receive(:provision_namespace).and_return(ar_namespace)
  end

  describe '#execute' do
    context 'with a valid slug and a single top-level group' do
      it 'calls AR with the slug and both derived anchors, then writes the mapping row', :aggregate_failures do
        expect { execute }.to change { organization.reload.artifact_registry_namespace_mapping }.from(nil)

        expect(client).to have_received(:provision_namespace).with(
          slug: slug,
          platform: 'gitlab',
          entity_type: 'organization',
          entity_id: organization.uuid,
          billing_entity_type: 'top_level_group',
          billing_entity_id: billing_group.id
        )

        mapping = organization.reload.artifact_registry_namespace_mapping
        expect(execute).to be_success
        expect(execute.payload[:namespace_mapping]).to eq(mapping)
        # The fetched namespace rides back on the payload so the caller reads its
        # status without a second AR call.
        expect(execute.payload[:ar_namespace]).to eq(ar_namespace)
        expect(mapping.ar_namespace_id).to eq(ar_namespace_id)
      end
    end

    context 'with the real client against a stubbed AR endpoint' do
      let(:base_url) { 'https://artifact-registry.example.test' }
      let(:service_token) { 'ar-service-token' }
      let(:service_credential) { ArtifactRegistry::ServiceCredential.new }
      let(:namespaces_url) { "#{base_url}/api/gitlab/v1/namespaces" }

      before do
        allow(ArtifactRegistry::Client).to receive(:new).and_call_original
        stub_config(artifact_registry: { api_url: base_url })
        allow(service_credential).to receive(:token).and_return(service_token)
      end

      it 'posts the derived anchors with the UUID owner id and writes the returned UUID', :aggregate_failures do
        request = stub_request(:post, namespaces_url)
          .with(
            headers: { ArtifactRegistry::Transport::SERVICE_TOKEN_HEADER => service_token },
            body: hash_including(
              'slug' => slug,
              'platform' => 'gitlab',
              'entity_type' => 'organization',
              'entity_id' => organization.uuid,
              'billing_entity_type' => 'top_level_group',
              'billing_entity_id' => billing_group.id.to_s
            )
          )
          .to_return(
            status: 201,
            body: { 'id' => ar_namespace_id, 'slug' => slug }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        expect(execute).to be_success
        expect(request).to have_been_requested
        expect(organization.reload.artifact_registry_namespace_mapping.ar_namespace_id).to eq(ar_namespace_id)
      end

      # Criterion 2: an exact-anchor replay answers 200, not 201.
      it 'writes the row when AR replays with 200' do
        stub_request(:post, namespaces_url).to_return(
          status: 200,
          body: { 'id' => ar_namespace_id, 'slug' => slug }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

        expect(execute).to be_success
        expect(organization.reload.artifact_registry_namespace_mapping.ar_namespace_id).to eq(ar_namespace_id)
      end

      # Criterion 29 (service half): the real client reports before it raises.
      it 'lets the client report the typed exception before mapping the failure', :aggregate_failures do
        allow(Gitlab::ErrorTracking).to receive(:log_exception)
        stub_request(:post, namespaces_url).to_return(status: 503)

        expect(execute).to be_error
        expect(execute.reason).to eq(:service_unavailable)
        expect(Gitlab::ErrorTracking).to have_received(:log_exception)
          .with(instance_of(ArtifactRegistry::Client::UnavailableError), anything)
      end

      # A malformed id casts to nil and fails presence on ar_namespace_id, not
      # organization uniqueness, so it must not be misread as a concurrency resolve.
      it 'raises rather than reporting :mapping_lost when AR returns a malformed id' do
        stub_request(:post, namespaces_url).to_return(
          status: 201,
          body: { 'id' => 'not-a-uuid', 'slug' => slug }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

        expect { execute }.to raise_error(ActiveRecord::RecordInvalid)
      end

      context 'when the service credential yields no token' do
        # The fail-closed ServiceCredential returns a nil token, so the client
        # raises AuthorizationError before any request; it must propagate.
        before do
          allow(service_credential).to receive(:token).and_return(nil)
        end

        it 'propagates the authorization error and issues no request', :aggregate_failures do
          request = stub_request(:post, namespaces_url)

          expect { execute }.to raise_error(ArtifactRegistry::Client::AuthorizationError)
          expect(request).not_to have_been_requested
        end
      end
    end

    # The second construction site takes the same default provider as the
    # CachesClient one, so both present the credential the deployment mounts
    # rather than disagreeing on what a service credential is.
    context 'with a real ServiceCredential reading the mounted secret' do
      let(:base_url) { 'https://artifact-registry.example.test' }
      let(:secret_file) { '/etc/gitlab/artifact-registry/.gitlab_artifact_registry_secret' }
      let(:namespaces_url) { "#{base_url}/api/gitlab/v1/namespaces" }
      let(:service_credential) { ArtifactRegistry::ServiceCredential.new }

      before do
        allow(ArtifactRegistry::Client).to receive(:new).and_call_original
        stub_config(artifact_registry: { api_url: base_url, service_token: { secret_file: secret_file } })
        stub_file_read(secret_file, content: "mounted-service-token\n")
      end

      it 'presents the mounted secret in the service-token header', :aggregate_failures do
        request = stub_request(:post, namespaces_url)
          .with(headers: { ArtifactRegistry::Transport::SERVICE_TOKEN_HEADER => 'mounted-service-token' })
          .to_return(
            status: 201,
            body: { 'id' => ar_namespace_id, 'slug' => slug }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        expect(execute).to be_success
        expect(request).to have_been_requested
      end
    end

    context 'with no service credential injected' do
      it 'requires the keyword rather than inheriting a default provider' do
        expect { described_class.new(organization: organization, slug: slug) }
          .to raise_error(ArgumentError, /service_credential/)
      end
    end

    context 'when the organization already has a mapping' do
      let_it_be(:existing) { create(:artifact_registry_namespace_mapping, organization: organization) }

      let(:claimed_slug) { 'my-slug' }
      let(:claimed_status) { 'active' }
      let(:live_namespace) do
        instance_double(ArtifactRegistry::Namespace, id: existing.ar_namespace_id, slug: claimed_slug,
          status: claimed_status, created_at: Time.zone.parse('2026-01-01T00:00:00Z'))
      end

      before do
        allow(client).to receive(:namespace).with(uuid: existing.ar_namespace_id).and_return(live_namespace)
      end

      # expire_registry_cache touches the row to move its versioned cache key.
      def stored_row
        ArtifactRegistry::NamespaceMapping.find(existing.id).attributes.except('updated_at')
      end

      shared_examples 'a repeat request that provisions nothing' do
        it 'issues no provisioning call, spends no claim, and leaves the row unchanged', :aggregate_failures do
          expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)

          expect { execute }.not_to change { stored_row }
          expect(client).not_to have_received(:provision_namespace)
          expect(client).to have_received(:namespace).once
        end
      end

      # mapping.registry builds its own service client, so that route to Client.new must return
      # the double too, constrained to the service-authenticated form the render path uses.
      shared_context 'with the render-path client doubled' do
        before do
          allow(ArtifactRegistry::Client).to receive(:new)
            .with(current_user: nil, organization: organization).and_return(client)
          organization.clear_memoization(:artifact_registry_client)
        end

        after do
          organization.clear_memoization(:artifact_registry_client)
        end
      end

      # Seeds the cache through its public reader rather than by hand-writing the cache key.
      shared_context 'with a stale cached registry' do
        include_context 'with the render-path client doubled'

        let(:stale_slug) { claimed_slug }
        let(:stale_status) { 'active' }
        let(:stale_namespace) do
          instance_double(ArtifactRegistry::Namespace, id: existing.ar_namespace_id, slug: stale_slug,
            status: stale_status, created_at: nil)
        end

        before do
          allow(client).to receive(:namespace).and_return(stale_namespace)
          existing.registry
          allow(client).to receive(:namespace).with(uuid: existing.ar_namespace_id).and_return(live_namespace)
        end
      end

      shared_context 'with a negatively cached registry' do
        include_context 'with the render-path client doubled'

        before do
          allow(client).to receive(:namespace)
            .and_raise(ArtifactRegistry::Client::UnavailableError.new('registry timed out', status: 503))
          existing.registry
          allow(client).to receive(:namespace).with(uuid: existing.ar_namespace_id).and_return(live_namespace)
        end
      end

      context 'and the submitted slug is the claimed handle' do
        it_behaves_like 'a repeat request that provisions nothing'

        it 'resolves to the existing mapping with the live namespace', :aggregate_failures do
          expect(execute).to be_success
          expect(execute.payload[:namespace_mapping]).to eq(existing)
          expect(execute.payload[:ar_namespace]).to eq(live_namespace)
        end

        it 'still resolves when cache invalidation fails', :aggregate_failures do
          allow_next_found_instance_of(ArtifactRegistry::NamespaceMapping) do |instance|
            allow(instance).to receive(:expire_registry_cache).and_raise(StandardError, 'redis down')
          end
          expect(::Gitlab::ErrorTracking).to receive(:track_exception).with(instance_of(StandardError))

          expect(execute).to be_success
        end

        context 'and the organization now has several top-level groups' do
          before do
            create(:group, organization: organization)
          end

          it 'still resolves rather than refusing the anchor', :aggregate_failures do
            expect(execute).to be_success
            expect(execute.payload[:namespace_mapping]).to eq(existing)
            expect(client).not_to have_received(:provision_namespace)
          end
        end

        context 'and the render-path cache holds a different handle', :use_clean_rails_memory_store_caching do
          include_context 'with a stale cached registry' do
            let(:stale_slug) { 'stale-handle' }
          end

          it 'resolves against the live handle and refreshes the cache', :aggregate_failures do
            expect(existing.registry.slug).to eq(stale_slug)

            expect(execute).to be_success
            expect(execute.payload[:ar_namespace]).to eq(live_namespace)
            expect(existing.registry.slug).to eq(claimed_slug)
          end
        end

        context 'and the render-path cache holds a failed resolution', :use_clean_rails_memory_store_caching do
          include_context 'with a negatively cached registry'

          it 'resolves against the live read and clears the failed entry', :aggregate_failures do
            expect(existing.registry).to be_a(ArtifactRegistry::NamespaceMapping::ResolutionFailure)

            expect(execute).to be_success
            expect(existing.registry.slug).to eq(claimed_slug)
          end
        end
      end

      context 'and the submitted slug differs from the claimed handle' do
        let(:slug) { 'other-slug' }
        let(:logger) { instance_double(ArtifactRegistry::Logger, info: nil) }

        before do
          allow(ArtifactRegistry::Logger).to receive(:build).and_return(logger)
        end

        it_behaves_like 'a repeat request that provisions nothing'

        it 'refuses as already activated, naming only the claimed handle', :aggregate_failures do
          expect(execute).to be_error
          expect(execute.reason).to eq(:already_activated)
          expect(execute.message).to include(claimed_slug)
          expect(execute.message).not_to include(slug)
          expect(execute.payload).to eq(namespace_mapping: existing, ar_namespace: live_namespace)
        end

        # The double answers info only, so any other severity raises on its own.
        it 'writes no log entry' do
          execute

          expect(logger).not_to have_received(:info)
        end

        context 'and the submitted slug also breaks a syntactic rule' do
          let(:slug) { 'a' }

          it 'refuses as already activated rather than as invalid', :aggregate_failures do
            expect(execute.reason).to eq(:already_activated)
            expect(execute.payload).to include(:namespace_mapping, :ar_namespace)
            expect(client).not_to have_received(:provision_namespace)
          end
        end

        context 'and the render-path cache holds the submitted handle', :use_clean_rails_memory_store_caching do
          include_context 'with a stale cached registry' do
            let(:stale_slug) { slug }
          end

          it 'refuses against the live handle and refreshes the cache', :aggregate_failures do
            expect(existing.registry.slug).to eq(slug)

            expect(execute.reason).to eq(:already_activated)
            expect(existing.registry.slug).to eq(claimed_slug)
          end
        end
      end

      context 'and the namespace resolves as purged' do
        let(:claimed_status) { 'purged' }

        it_behaves_like 'a repeat request that provisions nothing'

        it 'refuses as re-onboarding not being available, even for the claimed handle', :aggregate_failures do
          expect(execute).to be_error
          expect(execute.reason).to eq(:reonboarding_unavailable)
          expect(execute.message).not_to include(claimed_slug)
          expect(execute.payload).to be_empty
        end

        context 'and the render-path cache still holds the registry as active', :use_clean_rails_memory_store_caching do
          include_context 'with a stale cached registry'

          it 'refuses against the live status and refreshes the cache', :aggregate_failures do
            expect(existing.registry.status).to eq('active')

            expect(execute.reason).to eq(:reonboarding_unavailable)
            expect(existing.registry.status).to eq('purged')
          end
        end
      end

      context 'and AR answers 404 for the stored UUID' do
        before do
          allow(client).to receive(:namespace).with(uuid: existing.ar_namespace_id).and_return(nil)
        end

        it_behaves_like 'a repeat request that provisions nothing'

        it 'refuses as service-unavailable rather than granting an uncompared handle', :aggregate_failures do
          expect(execute).to be_error
          expect(execute.reason).to eq(:service_unavailable)
          expect(execute.payload).to be_empty
        end

        context 'and the render-path cache still holds the registry as active', :use_clean_rails_memory_store_caching do
          include_context 'with a stale cached registry'

          before do
            allow(client).to receive(:namespace).with(uuid: existing.ar_namespace_id).and_return(nil)
          end

          it 'refreshes the cache so the render path stops serving the vanished registry', :aggregate_failures do
            expect(existing.registry.status).to eq('active')

            expect(execute.reason).to eq(:service_unavailable)
            expect(existing.registry.status).to eq('unknown')
          end
        end
      end

      context 'and the resolution fails with a transport error' do
        before do
          allow(client).to receive(:namespace).with(uuid: existing.ar_namespace_id)
            .and_raise(ArtifactRegistry::Client::UnavailableError.new('registry timed out', status: 503))
        end

        it_behaves_like 'a repeat request that provisions nothing'

        it 'refuses as service-unavailable carrying the client message', :aggregate_failures do
          expect(execute).to be_error
          expect(execute.reason).to eq(:service_unavailable)
          expect(execute.message).to eq('registry timed out')
        end
      end

      context 'and the resolution is refused by AR' do
        before do
          allow(client).to receive(:namespace).with(uuid: existing.ar_namespace_id)
            .and_raise(ArtifactRegistry::Client::AuthorizationError.new('forbidden', status: 403))
        end

        # Not rescued: the mutation's shared error mapping renders it as not-available, as on the provision path.
        it 'propagates the authorization error and provisions nothing', :aggregate_failures do
          expect { execute }.to raise_error(ArtifactRegistry::Client::AuthorizationError)
          expect(client).not_to have_received(:provision_namespace)
        end
      end
    end

    context 'when create! hits an already-persisted mapping' do
      # The model validation raises RecordInvalid on a sequential duplicate; the
      # DB index raises RecordNotUnique on a true race. The service must resolve
      # either to the stored row rather than erroring the caller.
      let_it_be(:winner) { create(:artifact_registry_namespace_mapping, organization: organization) }

      # A genuinely-invalid duplicate: validating it populates the
      # (:organization, :taken) error the service's rescue keys on.
      let(:duplicate) do
        build(:artifact_registry_namespace_mapping, organization: organization).tap(&:valid?)
      end

      let(:record_invalid) { ActiveRecord::RecordInvalid.new(duplicate) }
      let(:record_not_unique) { ActiveRecord::RecordNotUnique.new('duplicate key') }

      where(:case_name, :error) do
        [
          ['a sequential duplicate (RecordInvalid)', ref(:record_invalid)],
          ['a concurrent race (RecordNotUnique)', ref(:record_not_unique)]
        ]
      end

      with_them do
        before do
          # The initial association read saw no mapping, so the service reaches
          # create!; after it raises, reset re-reads and finds the stored row.
          allow(organization).to receive(:reset).and_return(organization)
          allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(nil, winner)
          allow(ArtifactRegistry::NamespaceMapping).to receive(:create!).and_raise(error)
        end

        it 'resolves to the persisted row rather than erroring', :aggregate_failures do
          expect { execute }.not_to change { ArtifactRegistry::NamespaceMapping.count }
          expect(execute).to be_success
          expect(execute.payload[:namespace_mapping]).to eq(winner)
        end
      end
    end

    context 'when create! raises RecordInvalid for a reason other than the taken organization' do
      # A blank ar_namespace_id (e.g. a malformed AR id cast to nil) is a real
      # error, not a concurrency re-resolve, so it must not become :mapping_lost.
      let(:invalid_record) do
        build(:artifact_registry_namespace_mapping, organization: organization, ar_namespace_id: nil).tap(&:valid?)
      end

      before do
        allow(organization).to receive(:artifact_registry_namespace_mapping).and_return(nil)
        allow(ArtifactRegistry::NamespaceMapping).to receive(:create!)
          .and_raise(ActiveRecord::RecordInvalid.new(invalid_record))
      end

      it 're-raises rather than resolving' do
        expect { execute }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context 'when the persisted row is gone before the post-conflict re-read' do
      before do
        # create! hits an existing row, but that row is deleted (e.g. a concurrent
        # deactivation) before reset re-reads, so the association reloads to nil.
        allow(ArtifactRegistry::NamespaceMapping).to receive(:create!)
          .and_raise(ActiveRecord::RecordNotUnique.new('duplicate key'))
        allow(organization).to receive_messages(reset: organization, artifact_registry_namespace_mapping: nil)
      end

      it 'returns a :mapping_lost error rather than a nil-mapping success', :aggregate_failures do
        expect(execute).to be_error
        expect(execute.reason).to eq(:mapping_lost)
        expect(execute.message).to eq(s_('ArtifactRegistry|Namespace mapping was removed during a concurrent request.'))
      end
    end

    context 'when the slug breaks a syntactic rule' do
      let(:slug) { 'bad.slug' }

      it 'is refused with no client call and spends no claim', :aggregate_failures do
        expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)

        expect(execute).to be_error
        expect(execute.reason).to eq(:invalid_slug)
        expect(client).not_to have_received(:provision_namespace)
        expect(ArtifactRegistry::NamespaceMapping.count).to eq(0)
      end
    end

    context 'when the organization has no top-level group' do
      let_it_be(:organization) { create(:organization) }

      it 'is refused with no client call and spends no claim', :aggregate_failures do
        expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)

        expect(execute).to be_error
        expect(execute.reason).to eq(:no_billing_anchor)
        expect(execute.message).to eq(s_('ArtifactRegistry|Organization has no top-level groups.'))
        expect(client).not_to have_received(:provision_namespace)
      end
    end

    context 'when the organization has several top-level groups' do
      before do
        create(:group, organization: organization)
      end

      it 'is refused with no client call and spends no claim', :aggregate_failures do
        expect(Gitlab::ApplicationRateLimiter).not_to receive(:throttled?)

        expect(execute).to be_error
        expect(execute.reason).to eq(:multiple_billing_anchors)
        expect(execute.message).to eq(s_('ArtifactRegistry|Organization has more than one top-level group.'))
        expect(client).not_to have_received(:provision_namespace)
      end
    end

    context 'when AR refuses the claim with a 409 or a 422' do
      let(:logger) { instance_double(ArtifactRegistry::Logger, info: nil, warn: nil) }
      let(:request_id) { 'req-refused' }

      where(:status, :code, :ar_message, :reason) do
        409 | 'conflict'             | 'slug already taken'   | :conflict
        422 | 'unprocessable_entity' | 'slug is reserved'     | :unprocessable
        422 | 'unprocessable_entity' | 'entity_id is invalid' | :unprocessable
      end

      with_them do
        before do
          allow(ArtifactRegistry::Logger).to receive(:build).and_return(logger)
          allow(client).to receive(:provision_namespace).and_raise(
            ArtifactRegistry::Client::ApiError.new(ar_message, status: status, code: code, request_id: request_id)
          )
        end

        it "returns the availability refusal without AR's text and writes no row", :aggregate_failures do
          expect { execute }.not_to change { ArtifactRegistry::NamespaceMapping.count }
          expect(execute).to be_error
          expect(execute.reason).to eq(reason)
          expect(execute.message).to eq(s_('ArtifactRegistry|This handle is not available. Choose a different handle.'))
        end

        it "logs AR's status, code, request ID, and text" do
          execute

          expect(logger).to have_received(:warn).with(
            hash_including(
              message: 'provision_namespace refused',
              Labkit::Fields::CLASS_NAME => described_class.name,
              Labkit::Fields::GL_ORGANIZATION_ID => organization.id,
              Labkit::Fields::HTTP_STATUS_CODE => status,
              Labkit::Fields::ERROR_MESSAGE => ar_message,
              code: code,
              request_id: request_id
            )
          )
        end
      end
    end

    context 'when AR returns another API error the client surfaces as ApiError' do
      # 400 is a reachable ApiError; the client routes 429 and 5xx to UnavailableError.
      before do
        allow(client).to receive(:provision_namespace)
          .and_raise(ArtifactRegistry::Client::ApiError.new('bad request', status: 400))
      end

      it "falls back to :api_error, keeping AR's message, and writes no row", :aggregate_failures do
        expect { execute }.not_to change { ArtifactRegistry::NamespaceMapping.count }
        expect(execute).to be_error
        expect(execute.reason).to eq(:api_error)
        expect(execute.message).to eq('bad request')
      end
    end

    context 'when AR is unavailable' do
      before do
        allow(client).to receive(:provision_namespace)
          .and_raise(ArtifactRegistry::Client::UnavailableError.new('service unavailable', status: 503))
      end

      it 'surfaces :service_unavailable and writes no row', :aggregate_failures do
        expect { execute }.not_to change { ArtifactRegistry::NamespaceMapping.count }
        expect(execute).to be_error
        expect(execute.reason).to eq(:service_unavailable)
      end
    end

    context 'when the client raises an authorization error' do
      before do
        allow(client).to receive(:provision_namespace)
          .and_raise(ArtifactRegistry::Client::AuthorizationError.new('no credential', status: 401))
      end

      # Deliberate: 401/403 propagate as a top-level error so the Step 5 mutation
      # renders resource-not-available per the S03 convention, rather than the
      # service swallowing them into a recoverable payload error.
      it 'lets the authorization error propagate and writes no row', :aggregate_failures do
        expect { execute }.to raise_error(ArtifactRegistry::Client::AuthorizationError)
        expect(ArtifactRegistry::NamespaceMapping.count).to eq(0)
      end
    end

    context 'with the per-organization claim rate limit' do
      let(:limit) do
        Gitlab::ApplicationRateLimiter::LabkitAdapter::SupportedRateLimits
          .limit_for(:artifact_registry_namespace_provisioning)
      end

      let(:taken_error) do
        ArtifactRegistry::Client::ApiError.new('slug already taken', status: 409, code: 'conflict')
      end

      def claim(org: organization, handle: slug)
        described_class.new(organization: org, slug: handle, service_credential: service_credential).execute
      end

      shared_examples 'a claim refused as throttled' do
        it 'refuses with the throttled refusal, logs it, issues no provisioning call, and writes no row',
          :aggregate_failures do
          logger = instance_double(ArtifactRegistry::Logger, info: nil, warn: nil)
          allow(ArtifactRegistry::Logger).to receive(:build).and_return(logger)
          expect(client).not_to receive(:provision_namespace)

          expect(claim).to have_attributes(
            status: :error,
            reason: :rate_limited,
            message: s_('ArtifactRegistry|Too many attempts to claim a handle. Try again later.')
          )
          expect(ArtifactRegistry::NamespaceMapping.count).to eq(0)
          expect(logger).to have_received(:warn).with(
            hash_including(
              message: 'provision_namespace throttled',
              Labkit::Fields::CLASS_NAME => described_class.name,
              Labkit::Fields::GL_ORGANIZATION_ID => organization.id,
              slug: slug
            )
          )
        end
      end

      context 'when AR refused every claim in the window' do
        before do
          allow(client).to receive(:provision_namespace).and_raise(taken_error)
          limit.times { claim }
        end

        it 'lets every claim in the window reach AR' do
          expect(client).to have_received(:provision_namespace).exactly(limit).times
        end

        it_behaves_like 'a claim refused as throttled'

        context 'and another organization claims' do
          let_it_be(:other_organization) { create(:organization) }
          let_it_be(:other_billing_group) { create(:group, organization: other_organization) }

          it 'provisions the other organization', :aggregate_failures do
            allow(client).to receive(:provision_namespace)
              .with(hash_including(entity_id: other_organization.uuid)).and_return(ar_namespace)

            expect(claim(org: other_organization)).to be_success
            expect(other_organization.reload.artifact_registry_namespace_mapping).to be_present
          end
        end
      end
    end

    context 'when logging the request and the returned UUID' do
      let(:logger) { instance_double(ArtifactRegistry::Logger) }

      before do
        allow(ArtifactRegistry::Logger).to receive(:build).and_return(logger)
        allow(logger).to receive(:info)
      end

      it 'writes both entries with the standard fields, including the slug', :aggregate_failures do
        execute

        expect(logger).to have_received(:info).with(
          hash_including(
            message: 'provision_namespace request',
            slug: slug,
            Labkit::Fields::CLASS_NAME => described_class.name,
            Labkit::Fields::GL_ORGANIZATION_ID => organization.id,
            Labkit::Fields::GL_ROOT_NAMESPACE_ID => billing_group.id
          )
        )
        expect(logger).to have_received(:info).with(
          hash_including(
            message: 'provision_namespace response',
            Labkit::Fields::CLASS_NAME => described_class.name,
            Labkit::Fields::GL_ORGANIZATION_ID => organization.id,
            ar_namespace_id: ar_namespace_id
          )
        )
      end

      context 'when the row write then fails' do
        before do
          allow(ArtifactRegistry::NamespaceMapping).to receive(:create!)
            .and_raise(ActiveRecord::StatementInvalid, 'boom')
        end

        # Criterion 8: the request and returned-UUID logs are the lost-write
        # recovery record, so both must already be written when the write fails.
        it 'has written both entries before the failed write', :aggregate_failures do
          expect { execute }.to raise_error(ActiveRecord::StatementInvalid)

          expect(logger).to have_received(:info).with(hash_including(message: 'provision_namespace request'))
          expect(logger).to have_received(:info).with(hash_including(message: 'provision_namespace response'))
        end
      end
    end
  end
end
