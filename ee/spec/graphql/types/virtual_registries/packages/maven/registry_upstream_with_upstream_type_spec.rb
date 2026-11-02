# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['MavenRegistryUpstreamWithUpstream'], feature_category: :virtual_registry do
  include GraphqlHelpers

  let_it_be(:user) { create(:user) }
  let_it_be(:fields) { %i[id position upstream targetUpstream] }
  let_it_be(:registry) { create(:virtual_registries_packages_maven_registry) }
  let_it_be(:upstream) { create(:virtual_registries_packages_maven_upstream) }
  let_it_be(:registry_upstream) { create(:virtual_registries_packages_maven_registry_upstream, registry:, upstream:) }

  let(:batch_loader) { instance_double(Gitlab::Graphql::Loaders::BatchModelLoader) }

  subject { described_class }

  before_all do
    registry.group.add_developer(user)
  end

  it { is_expected.to have_graphql_fields(fields) }
  it { is_expected.to require_graphql_authorizations(:read_virtual_registry) }
  it { is_expected.to have_attributes(interfaces: include(Types::VirtualRegistries::RegistryUpstreamInterface)) }

  it 'keeps upstream non-null' do
    expect(described_class.fields['upstream'].type).to be_non_null
  end

  it 'declares targetUpstream as the nullable remote or local union' do
    expect(described_class.fields['targetUpstream'].type.to_type_signature).to eq('MavenTargetUpstream')
  end

  describe '#upstream' do
    subject(:resolved_upstream) { resolve_field(:upstream, registry_upstream, current_user: user) }

    it 'fetches the upstream' do
      expect(Gitlab::Graphql::Loaders::BatchModelLoader)
        .to receive(:new)
        .with(::VirtualRegistries::Packages::Maven::Upstream, upstream.id)
        .and_return(batch_loader)
      expect(batch_loader).to receive(:find)

      resolved_upstream
    end
  end

  describe '#target_upstream' do
    it 'resolves the remote upstream for a remote row' do
      expect(batch_sync { resolve_field(:target_upstream, registry_upstream, current_user: user) }).to eq(upstream)
    end

    context 'with a local registry upstream' do
      let_it_be(:local_upstream) do
        create(:virtual_registries_packages_maven_local_upstream, :local_group, group: registry.group)
      end

      let_it_be(:local_registry_upstream) do
        create(:virtual_registries_packages_maven_registry_upstream, :with_local_upstream,
          registry: registry, local_upstream: local_upstream)
      end

      it 'resolves the local upstream' do
        expect(batch_sync { resolve_field(:target_upstream, local_registry_upstream, current_user: user) })
          .to eq(local_upstream)
      end

      it 'loads only the local upstream' do
        expect(Gitlab::Graphql::Loaders::BatchModelLoader)
          .to receive(:new)
          .with(::VirtualRegistries::Packages::Maven::Local::Upstream, local_upstream.id)
          .and_return(batch_loader)
        expect(batch_loader).to receive(:find)

        resolve_field(:target_upstream, local_registry_upstream, current_user: user)
      end
    end
  end
end
