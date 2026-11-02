# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::NamespaceMapping, feature_category: :artifact_registry do
  let_it_be(:organization) { create(:organization) }

  subject(:mapping) { build(:artifact_registry_namespace_mapping, organization: organization) }

  describe 'associations' do
    it { is_expected.to belong_to(:organization).class_name('Organizations::Organization').required }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:ar_namespace_id) }

    it 'allows at most one mapping per organization' do
      create(:artifact_registry_namespace_mapping, organization: organization)

      expect(mapping).to be_invalid
      expect(mapping.errors[:organization]).to include('has already been taken')
    end

    it 'enforces one mapping per organization at the database level' do
      create(:artifact_registry_namespace_mapping, organization: organization)
      duplicate = build(:artifact_registry_namespace_mapping, organization: organization)

      expect { duplicate.save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'schema' do
    it 'holds only the organization, the AR namespace UUID, and timestamps' do
      expect(described_class.column_names)
        .to contain_exactly('id', 'organization_id', 'ar_namespace_id', 'created_at', 'updated_at')
    end
  end

  describe 'organization deletion' do
    it 'cascades: destroying the organization removes the mapping' do
      persisted = create(:artifact_registry_namespace_mapping, organization: organization)

      organization.delete

      expect(described_class.exists?(persisted.id)).to be(false)
    end
  end

  describe 'Registry#resolved?' do
    it 'is true when a handle came back' do
      registry = described_class::Registry.new(slug: 'acme', status: 'active', created_at: nil)

      expect(registry.resolved?).to be(true)
    end

    it 'is false when the status is unknown, which carries no handle' do
      registry = described_class::Registry.new(slug: nil, status: described_class::UNKNOWN_STATUS,
        created_at: nil)

      expect(registry.resolved?).to be(false)
    end
  end

  describe 'ResolutionFailure#resolved?' do
    it 'is false, so a consumer picks a destination without type-checking first' do
      expect(described_class::ResolutionFailure.new(error_class: 'x').resolved?).to be(false)
    end
  end

  describe '#registry', :use_clean_rails_memory_store_caching do
    using RSpec::Parameterized::TableSyntax

    # Reloadable (not frozen) because #expire_registry_cache writes the row.
    let_it_be_with_reload(:persisted) { create(:artifact_registry_namespace_mapping, organization: organization) }

    let(:client) { instance_double(::ArtifactRegistry::Client) }
    let(:namespace) do
      instance_double(::ArtifactRegistry::Namespace, slug: 'acme', status: 'active', created_at: created_at)
    end

    let(:created_at) { Time.zone.parse('2026-01-01T00:00:00Z') }

    before do
      # Stubbed on Client.new, not one organization instance: a reloaded or re-found
      # mapping loads its own organization, which must reach the same double.
      allow(::ArtifactRegistry::Client).to receive(:new)
        .with(current_user: nil, organization: organization).and_return(client)
    end

    # One AR call per cache period across repeated reads, and a fresh call once the
    # period lapses. Parameterized over the success and failure periods, which differ
    # only by TTL, since both cache their result the same way.
    shared_examples 'a cached resolution' do |ttl_const|
      it 'issues one AR call across repeated reads within the period' do
        3.times { persisted.registry }

        expect(client).to have_received(:namespace).once
      end

      it 're-resolves once the period lapses' do
        persisted.registry

        travel_to(described_class.const_get(ttl_const, false).from_now + 1.second) { persisted.registry }

        expect(client).to have_received(:namespace).twice
      end
    end

    context 'when the client resolves the namespace' do
      before do
        allow(client).to receive(:namespace).with(uuid: persisted.ar_namespace_id).and_return(namespace)
      end

      it_behaves_like 'a cached resolution', :CACHE_TTL

      it "returns the row's UUID alongside the slug, status, and creation time" do
        registry = persisted.registry

        expect(registry).to have_attributes(
          ar_namespace_id: persisted.ar_namespace_id, slug: 'acme', status: 'active', created_at: created_at
        )
      end

      it 'reflects the change on the next read after an explicit invalidation' do
        persisted.registry
        persisted.expire_registry_cache
        persisted.registry

        expect(client).to have_received(:namespace).twice
      end

      # Two instances of one row stand in for two requests: the stale reader loaded the
      # row before the toggle, so its late write must not reach a reader loaded after.
      it 'does not serve a stale in-flight write that lands after an invalidation', :aggregate_failures do
        suspended = instance_double(::ArtifactRegistry::Namespace, slug: 'acme', status: 'suspended',
          created_at: created_at)
        allow(client).to receive(:namespace).and_return(namespace, suspended)
        stale_reader = described_class.find(persisted.id)

        persisted.expire_registry_cache
        stale_reader.registry

        expect(described_class.find(persisted.id).registry.status).to eq('suspended')
        expect(client).to have_received(:namespace).twice
      end

      # A reader on a lagging replica still computes the pre-touch key, so that entry
      # must be gone rather than left to serve until it expires.
      it 'drops the pre-invalidation entry for a reader that still holds the old row' do
        lagging_reader = described_class.find(persisted.id)
        lagging_reader.registry

        persisted.expire_registry_cache
        lagging_reader.registry

        expect(client).to have_received(:namespace).twice
      end

      it 'ignores an entry cached under the unversioned key', :aggregate_failures do
        Rails.cache.write([persisted.cache_key_with_version, 'registry'], {
          error: { class: 'ArtifactRegistry::Client::ApiError', status: 400, request_id: 'req-1', code: nil,
                   message: 'ArtifactRegistry::Client::ApiError' }
        })

        expect(persisted.registry).to have_attributes(slug: 'acme', status: 'active')
        expect(client).to have_received(:namespace).once
      end

      it 'passes race_condition_ttl: to fetch' do
        expect(Rails.cache).to receive(:fetch)
          .with(anything, hash_including(race_condition_ttl: described_class::RACE_CONDITION_TTL))
          .and_call_original

        persisted.registry
      end
    end

    context 'when the client answers 404 (nil)' do
      before do
        allow(client).to receive(:namespace).with(uuid: persisted.ar_namespace_id).and_return(nil)
      end

      # The UUID reads off the row, so it survives a resolution that returned nothing.
      it 'resolves to the unknown state, keeps the row, and still carries its UUID' do
        registry = persisted.registry

        expect(registry).to have_attributes(
          ar_namespace_id: persisted.ar_namespace_id, slug: nil,
          status: described_class::UNKNOWN_STATUS, created_at: nil
        )
        expect(described_class.exists?(persisted.id)).to be(true)
      end
    end

    context 'when the client resolves a namespace with a blank status' do
      it 'resolves to the unknown state rather than caching a nil the field cannot render' do
        blank = instance_double(::ArtifactRegistry::Namespace, slug: 'acme', status: '', created_at: created_at)
        allow(client).to receive(:namespace).and_return(blank)

        expect(persisted.registry.status).to eq(described_class::UNKNOWN_STATUS)
      end
    end

    context 'when the client raises a typed exception' do
      before do
        allow(client).to receive(:namespace).and_raise(
          ::ArtifactRegistry::Client::AuthorizationError.new('denied', status: 403, request_id: 'req-1')
        )
      end

      it_behaves_like 'a cached resolution', :NEGATIVE_CACHE_TTL

      it 'caches the failure, carrying the client error detail' do
        failure = persisted.registry

        expect(failure).to be_a(described_class::ResolutionFailure)
        expect(failure).to have_attributes(
          error_class: 'ArtifactRegistry::Errors::AuthorizationError', status: 403, request_id: 'req-1'
        )
      end
    end

    describe 'reconstructing the failure into a typed exception' do
      # The reconstructed class matches the raised one, carrying its status, code,
      # and request ID across the cache flattening.
      where(:raised, :status, :code, :request_id) do
        [
          ['AuthorizationError', 403, nil,       'req-1'],
          ['UnavailableError',   503, nil,       'req-2'],
          ['ApiError',           400, 'invalid', 'req-3']
        ]
      end

      with_them do
        it 'reconstructs the same class with its status, code, and request ID', :aggregate_failures do
          klass = ::ArtifactRegistry::Client.const_get(raised, false)
          allow(client).to receive(:namespace).and_raise(
            klass.new('boom', status: status, request_id: request_id, **(code ? { code: code } : {}))
          )

          error = persisted.registry.to_client_error

          expect(error).to be_a(klass)
          expect(error.status).to eq(status)
          expect(error.request_id).to eq(request_id)
          expect(error.code).to eq(code) if error.respond_to?(:code)
        end
      end
    end
  end
end
