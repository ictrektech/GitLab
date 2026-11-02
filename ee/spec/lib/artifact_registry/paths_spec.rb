# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::Paths, :aggregate_failures, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  let(:host) do
    Class.new do
      include ArtifactRegistry::Paths

      public(*ArtifactRegistry::Paths.private_instance_methods(false))
    end.new
  end

  describe 'path helpers' do
    subject(:built_path) { host.public_send(helper, *args) }

    context 'with plain segments' do
      # rubocop:disable Layout/LineLength -- Required for formatting of table
      where(:helper, :args, :path) do
        :namespaces_path            | []                                               | 'api/gitlab/v1/namespaces'
        :namespace_path             | ['ns-1']                                         | 'api/gitlab/v1/namespaces/ns-1'
        :namespace_condition_path   | %w[ns-1 disable]                                 | 'api/gitlab/v1/namespaces/ns-1/disable'
        :verifications_path         | ['ns-1']                                         | 'api/gitlab/v1/namespaces/ns-1/repositories/verifications'
        :repositories_path          | ['acme']                                         | 'api/v1/acme/repositories'
        :namespace_statistics_path  | ['acme']                                         | 'api/v1/acme/statistics'
        :connection_test_path       | ['acme']                                         | 'api/v1/acme/connection_test'
        :namespace_details_path     | ['acme']                                         | 'api/v1/acme/namespace'
        :repository_path            | %w[acme local]                                   | 'api/v1/acme/repositories/local'
        :repository_test_path       | %w[acme local]                                   | 'api/v1/acme/repositories/local/test'
        :repository_statistics_path | %w[acme local]                                   | 'api/v1/acme/repositories/local/statistics'
        :artifacts_path             | %w[acme local npm packages]                      | 'api/v1/acme/repositories/local/npm/packages'
        :artifact_path              | %w[acme local npm packages pkg-1]                | 'api/v1/acme/repositories/local/npm/packages/pkg-1'
        :sub_collection_path        | %w[acme local npm packages pkg-1 versions]       | 'api/v1/acme/repositories/local/npm/packages/pkg-1/versions'
        :sub_collection_member_path | %w[acme local npm packages pkg-1 versions ver-1] | 'api/v1/acme/repositories/local/npm/packages/pkg-1/versions/ver-1'
        :manifest_path              | %w[acme local oci img-1 dgst-1]                  | 'api/v1/acme/repositories/local/oci/images/img-1/manifests/dgst-1'
        :bulk_delete_path           | %w[acme local maven packages]                    | 'api/v1/acme/repositories/local/maven/packages/bulk_delete'
        :nested_bulk_delete_path    | %w[acme local maven packages pkg-1 versions]     | 'api/v1/acme/repositories/local/maven/packages/pkg-1/versions/bulk_delete'
      end
      # rubocop:enable Layout/LineLength

      with_them do
        it 'builds the path' do
          is_expected.to eq(path)
        end
      end
    end

    context 'with segments that need percent-encoding' do
      # rubocop:disable Layout/LineLength -- Required for formatting of table
      where(:helper, :args, :path) do
        :namespace_path             | ['a/b']                                        | 'api/gitlab/v1/namespaces/a%2Fb'
        :namespace_condition_path   | %w[a/b c/d]                                    | 'api/gitlab/v1/namespaces/a%2Fb/c%2Fd'
        :artifact_path              | ['acme corp', 'a/b', 'n?m', 'packages', 'x#y'] | 'api/v1/acme%20corp/repositories/a%2Fb/n%3Fm/packages/x%23y'
        :sub_collection_path        | %w[acme local npm packages x/y versions]       | 'api/v1/acme/repositories/local/npm/packages/x%2Fy/versions'
        :sub_collection_member_path | %w[acme local npm packages pkg-1 versions x/y] | 'api/v1/acme/repositories/local/npm/packages/pkg-1/versions/x%2Fy'
        :manifest_path              | %w[acme local oci img-1 sha256:abc]            | 'api/v1/acme/repositories/local/oci/images/img-1/manifests/sha256%3Aabc'
      end
      # rubocop:enable Layout/LineLength

      with_them do
        it 'percent-encodes each segment' do
          is_expected.to eq(path)
        end
      end
    end
  end

  describe '#encode_segment' do
    subject(:encoded_segment) { host.encode_segment(value) }

    where(:value, :encoded) do
      'a/b'   | 'a%2Fb'
      'a b'   | 'a%20b'
      '..'    | '..'
      'v1.0~' | 'v1.0~'
      42      | '42'
      nil     | ''
    end

    with_them do
      it 'percent-encodes the value as one path segment' do
        is_expected.to eq(encoded)
      end
    end
  end
end
