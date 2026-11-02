# frozen_string_literal: true

require 'spec_helper'

RSpec.describe GitlabSchema.types['MavenLocalUpstream'], feature_category: :virtual_registry do
  include GraphqlHelpers

  subject { described_class }

  it { is_expected.to require_graphql_authorizations(:read_virtual_registry) }

  it 'exposes the expected fields' do
    expected_field_types = {
      id: 'ID!',
      name: 'String!',
      cacheValidityHours: 'Int!',
      metadataCacheValidityHours: 'Int!',
      localGroup: 'MavenLocalUpstreamTargetGroup',
      localProject: 'MavenLocalUpstreamTargetProject'
    }

    expect(described_class).to have_graphql_fields(*expected_field_types.keys)
    expected_field_types.each do |field_name, type_signature|
      expect(described_class.fields[field_name.to_s].type.to_type_signature).to eq(type_signature)
    end
  end

  describe 'target fields' do
    let_it_be(:user) { create(:user) }
    let_it_be(:group) { create(:group) }

    before_all do
      group.add_developer(user)
    end

    def resolve_target(field, upstream)
      ::Gitlab::Graphql::Lazy.force(resolve_field(field, upstream, current_user: user))
    end

    context 'when the upstream targets a group' do
      let_it_be(:local_group) { create(:group, parent: group) }
      let_it_be(:upstream) do
        create(:virtual_registries_packages_maven_local_upstream, :local_group,
          group: group, local_group: local_group)
      end

      it 'resolves the group and leaves the project nil' do
        expect(resolve_target(:local_group, upstream)).to eq(local_group)
        expect(resolve_target(:local_project, upstream)).to be_nil
      end
    end

    context 'when the upstream targets a project' do
      let_it_be(:local_project) { create(:project, group: group) }
      let_it_be(:upstream) do
        create(:virtual_registries_packages_maven_local_upstream, group: group, local_project: local_project)
      end

      it 'resolves the project and leaves the group nil' do
        expect(resolve_target(:local_project, upstream)).to eq(local_project)
        expect(resolve_target(:local_group, upstream)).to be_nil
      end
    end
  end
end
