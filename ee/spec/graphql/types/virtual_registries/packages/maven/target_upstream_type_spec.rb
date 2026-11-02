# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['MavenTargetUpstream'], feature_category: :virtual_registry do
  it 'unions the remote and local upstream types' do
    expect(described_class.possible_types).to contain_exactly(
      Types::VirtualRegistries::Packages::Maven::UpstreamType,
      Types::VirtualRegistries::Packages::Maven::Local::UpstreamType
    )
  end

  describe '.resolve_type' do
    it 'resolves a remote upstream' do
      object = build(:virtual_registries_packages_maven_upstream)

      expect(described_class.resolve_type(object, {})).to eq(Types::VirtualRegistries::Packages::Maven::UpstreamType)
    end

    it 'resolves a local upstream' do
      object = build(:virtual_registries_packages_maven_local_upstream)

      expect(described_class.resolve_type(object, {}))
        .to eq(Types::VirtualRegistries::Packages::Maven::Local::UpstreamType)
    end

    it 'raises an error when the type is not known' do
      expect { described_class.resolve_type(build(:group), {}) }
        .to raise_error(described_class::TypeNotSupportedError, 'no Maven target upstream type for Group')
    end
  end
end
