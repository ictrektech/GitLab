# frozen_string_literal: true

RSpec.shared_context 'with a signed-in organization member and an active Artifact Registry' do
  let_it_be(:mapping) do
    create(:artifact_registry_namespace_mapping, organization: current_organization)
  end

  let(:user) { create(:user, organizations: [current_organization]) }
  let(:slug) { 'acme' }
  let(:repositories_base_path) { "/o/#{current_organization.path}/-/artifact_registry/#{slug}/repositories" }
  let(:client) { instance_double(::ArtifactRegistry::Client) }

  # Resolution is covered over HTTP in the controller request spec; faking it at
  # the model boundary here keeps browser tests independent of the Artifact
  # Registry wire contract and Rails.cache.
  let(:registry) do
    ::ArtifactRegistry::NamespaceMapping::Registry.new(
      slug: slug, status: 'active', created_at: '2026-07-01T10:00:00Z'
    )
  end

  before do
    allow_next_found_instance_of(::ArtifactRegistry::NamespaceMapping) do |mapping|
      allow(mapping).to receive(:registry).and_return(registry)
    end

    allow(::ArtifactRegistry::Client).to receive(:new)
      .with(current_user: user, organization: current_organization).and_return(client)

    sign_in(user)
  end
end

# Needs the client and slug of 'with a signed-in organization member and an active Artifact Registry'.
# Every example needs `name` and `format` in scope.
RSpec.shared_context 'with a repository the Artifact Registry client returns' do
  # A let in the including group cannot reach this context's let with `super()`,
  # so it overrides by merging onto this instead.
  def default_repository_attributes
    {
      'id' => '01937b2e-0000-7000-8000-000000000010',
      'name' => name,
      'format' => format,
      'kind' => 'hosted',
      'visibility' => 'private',
      'artifacts_count' => 3,
      'downloads_count' => 340,
      'size_bytes' => 2048,
      'created_at' => '2026-05-12T09:24:00Z',
      'last_updated_at' => '2026-07-02T11:30:00Z'
    }
  end

  let(:repository_attributes) { default_repository_attributes }

  let(:repository) { ::ArtifactRegistry::Repository.new(repository_attributes) }

  let(:repository_verdicts) { ::ArtifactRegistry::Permissions::Verdicts::REPOSITORY_ACTIONS.index_with(true) }

  let(:permissions) do
    ::ArtifactRegistry::Permissions::Verdicts.new(
      repository_verdicts, scope: :repository, read: :repository, slug: slug
    )
  end

  before do
    allow(client).to receive(:repository)
      .with(slug: slug, name: name, include_permissions: false).and_return(repository)
    allow(client).to receive(:repository)
      .with(slug: slug, name: name, include_permissions: true)
      .and_return(::ArtifactRegistry::Repository.new(repository_attributes, permissions))
  end
end
