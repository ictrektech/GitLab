# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Creating an Artifact Registry repository', feature_category: :artifact_registry do
  include GraphqlHelpers
  using RSpec::Parameterized::TableSyntax

  let_it_be(:current_organization) { create(:organization) }
  let_it_be(:current_user) { create(:organization_user, organization: current_organization).user }
  let_it_be(:non_member) { create(:user) }
  let_it_be(:namespace_mapping) { create(:artifact_registry_namespace_mapping, organization: current_organization) }

  let(:slug) { 'resolved-handle' }
  let(:namespace) do
    ArtifactRegistry::Namespace.new('id' => namespace_mapping.ar_namespace_id, 'slug' => slug, 'status' => 'active')
  end

  let(:repository_attributes) do
    {
      'id' => 'c3d4e5f6-0000-0000-0000-000000000000',
      'name' => 'my-repo',
      'format' => 'maven',
      'kind' => 'hosted',
      'visibility' => 'private',
      'description' => 'A repo',
      'artifacts_count' => 0,
      'downloads_count' => 0,
      'size_bytes' => 0,
      'settings' => {}
    }
  end

  let(:created_repository) { ArtifactRegistry::Repository.new(repository_attributes) }

  let(:client) { instance_double(ArtifactRegistry::Client) }

  let(:input) do
    {
      'name' => 'my-repo',
      'format' => 'MAVEN',
      'visibility' => 'PRIVATE',
      'description' => 'A repo'
    }
  end

  let(:mutation) { graphql_mutation(:artifact_registry_repository_create, input) }

  def mutation_response
    graphql_mutation_response(:artifact_registry_repository_create)
  end

  context 'when the artifact_registry_ui flag is on' do
    before do
      # The organization is a let_it_be record that memoizes its client, so the
      # memo can carry a double from one example into the next. Clear it, then
      # stub Client.new to return this example's double.
      current_organization.clear_memoization(:artifact_registry_client)
      allow(ArtifactRegistry::Client).to receive(:new).and_return(client)
      allow(client).to receive(:namespace).with(uuid: namespace_mapping.ar_namespace_id).and_return(namespace)
    end

    context 'when creating a virtual repository with an upstream list' do
      let(:input) do
        {
          'name' => 'my-repo',
          'format' => 'MAVEN',
          'kind' => 'VIRTUAL',
          'upstreamRepositoryIds' => %w[
            01928f3a-7b2c-7d4e-8f5a-000000000003
            01928f3a-7b2c-7d4e-8f5a-000000000001
            01928f3a-7b2c-7d4e-8f5a-000000000002
          ]
        }
      end

      it 'calls the client once with the ids in order and returns the repository', :aggregate_failures do
        expect(client).to receive(:create_repository).once.with(
          slug: slug,
          name: 'my-repo',
          format: 'maven',
          kind: 'virtual',
          visibility: nil,
          description: nil,
          settings: nil,
          upstream_repository_ids: %w[
            01928f3a-7b2c-7d4e-8f5a-000000000003
            01928f3a-7b2c-7d4e-8f5a-000000000001
            01928f3a-7b2c-7d4e-8f5a-000000000002
          ]
        ).and_return(created_repository)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['repository']).to include('name' => 'my-repo')
      end

      context 'when the list repeats an id or runs past 20 entries' do
        where(:upstream_repository_ids) do
          [
            [%w[01928f3a-7b2c-7d4e-8f5a-000000000001 01928f3a-7b2c-7d4e-8f5a-000000000001]],
            [Array.new(21) { |i| format('01928f3a-7b2c-7d4e-8f5a-%012d', i) }]
          ]
        end

        with_them do
          let(:input) { super().merge('upstreamRepositoryIds' => upstream_repository_ids) }

          it 'forwards the list unchanged for Artifact Registry to judge', :aggregate_failures do
            expect(client).to receive(:create_repository)
              .with(hash_including(upstream_repository_ids: upstream_repository_ids))
              .and_return(created_repository)

            post_graphql_mutation(mutation, current_user: current_user)

            expect(mutation_response['errors']).to be_empty
          end
        end
      end

      context 'when Artifact Registry rejects duplicate upstream ids' do
        let(:input) do
          super().merge('upstreamRepositoryIds' =>
            %w[01928f3a-7b2c-7d4e-8f5a-000000000001 01928f3a-7b2c-7d4e-8f5a-000000000001])
        end

        it 'renders one payload error without a refused upstream id', :aggregate_failures do
          expect(client).to receive(:create_repository)
            .with(hash_including(upstream_repository_ids: input['upstreamRepositoryIds']))
            .and_raise(ArtifactRegistry::Client::ApiError.new(
              'upstream_repository_ids must list each id once', status: 400, code: 'bad_request'
            ))

          post_graphql_mutation(mutation, current_user: current_user)

          expect(graphql_errors).to be_nil
          expect(mutation_response['errors']).to eq(['upstream_repository_ids must list each id once'])
          expect(mutation_response['repository']).to be_nil
          expect(mutation_response['refusedUpstreamRepositoryId']).to be_nil
        end
      end

      context 'when Artifact Registry refuses an entry' do
        it 'renders the payload error and returns the refused upstream id', :aggregate_failures do
          allow(client).to receive(:create_repository).and_raise(
            ArtifactRegistry::Client::ApiError.new(
              'upstream repository is not eligible', status: 422, code: 'unprocessable_entity',
              details: { 'upstream_repository_id' => '01928f3a-7b2c-7d4e-8f5a-000000000001' }
            )
          )

          post_graphql_mutation(mutation, current_user: current_user)

          expect(mutation_response['errors']).to eq(['upstream repository is not eligible'])
          expect(mutation_response['refusedUpstreamRepositoryId']).to eq('01928f3a-7b2c-7d4e-8f5a-000000000001')
          expect(mutation_response['repository']).to be_nil
        end
      end

      context 'when Artifact Registry refuses the list without details' do
        it 'renders the payload error and returns no refused upstream id', :aggregate_failures do
          allow(client).to receive(:create_repository).and_raise(
            ArtifactRegistry::Client::ApiError.new(
              'upstream_repository_ids exceeds 20 entries', status: 422, code: 'limit_exceeded'
            )
          )

          post_graphql_mutation(mutation, current_user: current_user)

          expect(mutation_response['errors']).to eq(['upstream_repository_ids exceeds 20 entries'])
          expect(mutation_response['refusedUpstreamRepositoryId']).to be_nil
        end
      end
    end

    context 'when upstreamRepositoryIds is explicitly null' do
      let(:input) { { 'name' => 'my-repo', 'format' => 'MAVEN', 'kind' => 'VIRTUAL', 'upstreamRepositoryIds' => nil } }

      it 'rejects the argument rather than forwarding the null', :aggregate_failures do
        expect(client).not_to receive(:create_repository)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => "upstreamRepositoryIds can't be null"))
      end
    end

    context 'when upstreamRepositoryIds runs past 1000 entries' do
      let(:input) do
        {
          'name' => 'my-repo',
          'format' => 'MAVEN',
          'kind' => 'VIRTUAL',
          'upstreamRepositoryIds' => Array.new(1001) { |i| format('01928f3a-7b2c-7d4e-8f5a-%012d', i) }
        }
      end

      it 'rejects the argument before calling Artifact Registry', :aggregate_failures do
        expect(client).not_to receive(:create_repository)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(
          a_hash_including('message' => 'upstreamRepositoryIds is too long (maximum is 1000)')
        )
      end
    end

    it 'creates the repository and returns it with no errors', :aggregate_failures do
      expect(client).to receive(:create_repository).with(
        slug: slug,
        name: 'my-repo',
        format: 'maven',
        kind: nil,
        visibility: 'private',
        description: 'A repo',
        settings: nil,
        upstream_repository_ids: nil
      ).and_return(created_repository)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(response).to have_gitlab_http_status(:success)
      expect(mutation_response['errors']).to be_empty
      expect(mutation_response['repository']).to include(
        'id' => 'c3d4e5f6-0000-0000-0000-000000000000', 'name' => 'my-repo', 'description' => 'A repo'
      )
    end

    context 'when Artifact Registry rejects the name (duplicate or invalid)' do
      it 'surfaces the error in the payload errors', :aggregate_failures do
        allow(client).to receive(:create_repository)
          .and_raise(ArtifactRegistry::Client::ApiError.new('name has already been taken', status: 409))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(response).to have_gitlab_http_status(:success)
        expect(mutation_response['errors']).to include(a_string_matching(/already been taken/))
        expect(mutation_response['repository']).to be_nil
      end
    end

    context 'when Artifact Registry denies the create (403)' do
      it 'renders a top-level ResourceNotAvailable' do
        allow(client).to receive(:create_repository)
          .and_raise(ArtifactRegistry::Client::AuthorizationError.new('forbidden', status: 403))

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
      end
    end

    context 'when an optional enum argument is explicitly null' do
      let(:input) { { 'name' => 'my-repo', 'format' => 'MAVEN', 'visibility' => nil } }

      it 'rejects the argument rather than dropping the null', :aggregate_failures do
        expect(client).not_to receive(:create_repository)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => "visibility can't be null"))
      end
    end

    context 'when settings is explicitly null' do
      let(:input) { { 'name' => 'my-repo', 'format' => 'MAVEN', 'settings' => nil } }

      it 'rejects the argument rather than forwarding the null', :aggregate_failures do
        expect(client).not_to receive(:create_repository)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(graphql_errors).to include(a_hash_including('message' => "settings can't be null"))
      end
    end

    context 'when creating a remote repository' do
      let(:repository_attributes) do
        super().merge(
          'kind' => 'remote',
          'settings' => {
            'url' => 'https://upstream.test',
            'cache_validity_hours' => 24,
            'metadata_cache_validity_hours' => 1,
            'has_credentials' => false,
            'last_health_status' => 'unknown',
            'last_health_checked_at' => nil
          }
        )
      end

      let(:input) do
        {
          'name' => 'my-repo',
          'format' => 'MAVEN',
          'kind' => 'REMOTE',
          'settings' => {
            'url' => 'https://upstream.test',
            'cacheValidityHours' => 24,
            'metadataCacheValidityHours' => 1
          }
        }
      end

      it 'sends the kind and the writable settings, and returns the created settings', :aggregate_failures do
        expect(client).to receive(:create_repository).with(
          hash_including(
            kind: 'remote',
            settings: { url: 'https://upstream.test', cache_validity_hours: 24, metadata_cache_validity_hours: 1 }
          )
        ).and_return(created_repository)

        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to be_empty
        expect(mutation_response['repository']['settings']).to include(
          'url' => 'https://upstream.test',
          'cacheValidityHours' => 24,
          'metadataCacheValidityHours' => 1,
          'hasCredentials' => false
        )
      end

      context 'when credentials are supplied' do
        let(:input) do
          super().merge('settings' => { 'url' => 'https://upstream.test',
                                        'credentials' => { 'username' => 'robot', 'password' => 'secret' } })
        end

        it 'forwards the credential object' do
          expect(client).to receive(:create_repository).with(
            hash_including(settings: { url: 'https://upstream.test',
                                       credentials: { username: 'robot', password: 'secret' } })
          ).and_return(created_repository)

          post_graphql_mutation(mutation, current_user: current_user)

          expect(mutation_response['errors']).to be_empty
        end
      end
    end

    context 'when a metadata cache window is sent on a container format' do
      let(:input) do
        {
          'name' => 'my-repo',
          'format' => 'DOCKER',
          'kind' => 'REMOTE',
          'settings' => { 'url' => 'https://upstream.test', 'metadataCacheValidityHours' => 1 }
        }
      end

      it 'reaches Artifact Registry rather than being dropped, and its rejection surfaces' do
        expect(client).to receive(:create_repository)
          .with(hash_including(settings: hash_including(metadata_cache_validity_hours: 1)))
          .and_raise(
            ArtifactRegistry::Client::ApiError.new('unknown field metadata_cache_validity_hours', status: 400)
          )

        post_graphql_mutation(mutation, current_user: current_user)

        expect(mutation_response['errors']).to include(a_string_matching(/metadata_cache_validity_hours/))
      end
    end
  end

  context 'with the real Artifact Registry client' do
    let(:base_url) { 'https://artifact-registry.example.test' }
    let(:repositories_url) { "#{base_url}/api/v1/#{slug}/repositories" }
    let(:json_headers) { { 'Content-Type' => 'application/json' } }

    before do
      current_organization.clear_memoization(:artifact_registry_client)
      stub_config(artifact_registry: { api_url: base_url })

      allow_next_instance_of(ArtifactRegistry::ServiceCredential) do |credential|
        allow(credential).to receive(:token).and_return('ar-service-credential')
      end

      allow_next_instance_of(ArtifactRegistry::TokenExchange) do |token_exchange|
        allow(token_exchange).to receive(:token_for).and_return('ar-request-spec-credential')
      end

      stub_request(:get, "#{base_url}/api/gitlab/v1/namespaces/#{namespace_mapping.ar_namespace_id}").to_return(
        status: 200,
        headers: json_headers,
        body: Gitlab::Json.dump(id: namespace_mapping.ar_namespace_id, slug: slug, status: 'active')
      )
    end

    context 'when an upstream list is sent on a create that is not virtual' do
      where(
        kind_input: [{}, { 'kind' => 'HOSTED' },
          { 'kind' => 'REMOTE', 'settings' => { 'url' => 'https://upstream.test' } }],
        upstream_repository_ids: [[], %w[01928f3a-7b2c-7d4e-8f5a-000000000001]]
      )

      with_them do
        let(:input) do
          { 'name' => 'my-repo', 'format' => 'MAVEN',
            'upstreamRepositoryIds' => upstream_repository_ids }.merge(kind_input)
        end

        it 'refuses the argument before sending a create request', :aggregate_failures do
          post_graphql_mutation(mutation, current_user: current_user)

          expect(graphql_errors).to include(
            a_hash_including('message' => 'upstream_repository_ids is only accepted for a virtual repository')
          )
          expect(WebMock).not_to have_requested(:post, repositories_url)
        end
      end
    end

    context 'when creating a virtual repository with no upstreams' do
      where(:upstream_input, :upstream_body) do
        {} | {}
        { 'upstreamRepositoryIds' => [] } | { upstream_repository_ids: [] }
      end

      with_them do
        let(:input) { { 'name' => 'my-repo', 'format' => 'MAVEN', 'kind' => 'VIRTUAL' }.merge(upstream_input) }

        it 'sends the supplied fields and returns the repository', :aggregate_failures do
          creation = stub_request(:post, repositories_url)
            .with(body: { name: 'my-repo', format: 'maven', kind: 'virtual' }.merge(upstream_body))
            .to_return(status: 201, headers: json_headers,
              body: Gitlab::Json.dump(repository_attributes.merge('kind' => 'virtual')))

          post_graphql_mutation(mutation, current_user: current_user)

          expect(creation).to have_been_requested.once
          expect(mutation_response['errors']).to be_empty
          expect(mutation_response['repository']).to include('name' => 'my-repo', 'kind' => 'VIRTUAL')
        end
      end
    end

    context 'when Artifact Registry refuses an upstream entry' do
      let(:input) do
        { 'name' => 'my-repo', 'format' => 'MAVEN', 'kind' => 'VIRTUAL',
          'upstreamRepositoryIds' => %w[01928f3a-7b2c-7d4e-8f5a-000000000001] }
      end

      where(:refused_id, :expected_refused_id) do
        '01928f3a-7b2c-7d4e-8f5a-000000000001' | '01928f3a-7b2c-7d4e-8f5a-000000000001'
        '01928F3A-7B2C-7D4E-8F5A-000000000001' | nil
      end

      with_them do
        it 'returns only an allowlisted refused upstream id', :aggregate_failures do
          creation = stub_request(:post, repositories_url).to_return(
            status: 422,
            headers: json_headers,
            body: Gitlab::Json.dump(error: {
              code: 'unprocessable_entity', message: 'upstream repository is not eligible',
              details: { upstream_repository_id: refused_id }
            })
          )

          post_graphql_mutation(mutation, current_user: current_user)

          expect(creation).to have_been_requested.once
          expect(graphql_errors).to be_nil
          expect(mutation_response['errors']).to eq(['upstream repository is not eligible'])
          expect(mutation_response['refusedUpstreamRepositoryId']).to eq(expected_refused_id)
          expect(mutation_response['repository']).to be_nil
        end
      end
    end
  end

  context 'when the user cannot read the organization registry' do
    it 'raises a top-level ResourceNotAvailable and makes no client call', :aggregate_failures do
      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_graphql_mutation(mutation, current_user: non_member)

      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end

  context 'when the artifact_registry_ui flag is off' do
    before do
      stub_feature_flags(artifact_registry_ui: false)
    end

    it 'raises a top-level ResourceNotAvailable and makes no client call', :aggregate_failures do
      expect(ArtifactRegistry::Client).not_to receive(:new)

      post_graphql_mutation(mutation, current_user: current_user)

      expect(graphql_errors).to include(a_hash_including('message' => /don't have permission/))
    end
  end
end
