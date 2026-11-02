# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organization Artifact Registry repositories SPA', :js, :with_current_organization,
  feature_category: :artifact_registry do
  include_context 'with a signed-in organization member and an active Artifact Registry'

  let(:repository_statistics) { ::ArtifactRegistry::RepositoryStatistics.new('packages_count' => 2) }

  def verdicts(scope, read, allowed)
    actions = ::ArtifactRegistry::Permissions::Verdicts::ACTIONS_BY_SCOPE.fetch(scope)

    ::ArtifactRegistry::Permissions::Verdicts.new(actions.index_with(allowed), scope: scope, read: read, slug: slug)
  end

  def denied_verdicts(scope, read)
    verdicts(scope, read, false)
  end

  it 'boots the Vue SPA shell on the resolved-slug repositories route' do
    allow(client).to receive_messages(
      repositories: ::ArtifactRegistry::Page.new(nodes: []),
      namespace_statistics: ::ArtifactRegistry::NamespaceStatistics.new(
        'repositories_count' => 0, 'deduplicated_size_bytes' => 0
      )
    )

    visit repositories_base_path

    expect(page).to have_testid('repositories-shell')
  end

  it 'serves a deep unregistered sub-path via the Rails catch-all and renders the in-SPA NotFound fallback' do
    # The path reads as a repository name, so the route resolves and the page asks the server
    # whether that repository exists. Faking the client keeps the example independent of whether
    # an Artifact Registry is reachable, which decides between not-found and service-unavailable.
    allow(client).to receive(:repository)
      .with(slug: slug, name: 'does-not-exist', include_permissions: anything).and_return(nil)

    visit "#{repositories_base_path}/does-not-exist"

    within_testid('repositories-shell') do
      expect(page).to have_css('h1', text: 'Page not found')
    end
  end

  describe 'the repositories list' do
    # Faked at the client rather than over HTTP: the wire format is the client's own contract,
    # and these examples are about what the connection renders in a browser.
    let(:repository_attributes) do
      {
        'id' => '01937b2e-0000-7000-8000-000000000010',
        'name' => 'maven-releases',
        'format' => 'maven',
        'kind' => 'hosted',
        'visibility' => 'private',
        'downloads_count' => 340,
        'size_bytes' => 2048,
        'last_updated_at' => '2026-07-02T11:30:00Z'
      }
    end

    let(:repositories_page) do
      ::ArtifactRegistry::Page.new(
        nodes: [
          ::ArtifactRegistry::Repository.new(repository_attributes, verdicts(:repository, :repositories, true))
        ],
        permissions: verdicts(:namespace, :repositories, true)
      )
    end

    before do
      allow(client).to receive_messages(
        repositories: repositories_page,
        namespace_statistics: ::ArtifactRegistry::NamespaceStatistics.new(
          'repositories_count' => 1, 'deduplicated_size_bytes' => 2048
        )
      )
    end

    it 'renders the page the connection returns' do
      visit repositories_base_path

      within_testid('repositories-shell') do
        expect(page).to have_css('h1', text: 'Repositories')
        expect(page).to have_link('maven-releases')
        expect(page).to have_content('Maven')
        expect(page).to have_content('Hosted')
        expect(page).to have_content('340')
        expect(page).to have_content('2.00 KiB')
      end
    end

    it 'renders the controls the verdicts allow' do
      visit repositories_base_path

      within_testid('repositories-shell') do
        expect(page).to have_button('New repository')
        expect(page).to have_button('More actions for maven-releases')
      end
    end

    describe 'with every verdict denied' do
      let(:repositories_page) do
        ::ArtifactRegistry::Page.new(
          nodes: [
            ::ArtifactRegistry::Repository.new(repository_attributes, denied_verdicts(:repository, :repositories))
          ],
          permissions: denied_verdicts(:namespace, :repositories)
        )
      end

      it 'renders the list without its gated controls and passes axe automated accessibility testing' do
        visit repositories_base_path

        within_testid('repositories-shell') do
          expect(page).to have_link('maven-releases')
          expect(page).to have_no_button('New repository')
          expect(page).to have_no_button('More actions for maven-releases')
        end

        expect(page).to be_axe_clean.within_testid('repositories-shell')
      end
    end

    it 'passes axe automated accessibility testing' do
      visit repositories_base_path

      expect(page).to have_link('maven-releases')
      expect(page).to be_axe_clean.within_testid('repositories-shell')
    end
  end

  # The single-repository read the detail page and the edit form share. A green Jest suite cannot
  # speak for these two: their repository leaves the browser as a GraphQL document and comes back
  # resolved by the schema, so nothing short of a rendered page says which layer answered.
  describe 'a repository the schema resolves' do
    include_context 'with a repository the Artifact Registry client returns'

    let(:name) { 'oci-repository' }
    let(:format) { 'maven' }
    let(:description) { 'Build artifacts for the payments domain.' }
    let(:repository_attributes) { default_repository_attributes.merge('description' => description) }

    let(:packages_page) do
      ::ArtifactRegistry::Page.new(
        nodes: [
          ::ArtifactRegistry::MavenPackage.new(
            'id' => '01937b2e-0000-7000-8000-000000000001',
            'group_id' => 'com.example.payments',
            'artifact_id' => 'payment-core'
          ),
          ::ArtifactRegistry::MavenPackage.new(
            'id' => '01937b2e-0000-7000-8000-000000000002',
            'group_id' => 'com.example.payments',
            'artifact_id' => 'payment-api'
          )
        ]
      )
    end

    before do
      allow(client).to receive(:packages).and_return(packages_page)
      allow(client).to receive(:repository_statistics)
        .with(slug: slug, repository_name: name, format: 'maven').and_return(repository_statistics)
    end

    # The name deliberately says one format while the repository carries another, because the
    # front end guesses a format from the name wherever no read has resolved one. A page
    # rendering OCI here is one answering from that guess.
    it 'renders the detail page from the repository, not from the name' do
      visit "#{repositories_base_path}/#{name}"

      within_testid('repositories-shell') do
        expect(find_by_testid('repository-name')).to have_text(name)
        expect(find_by_testid('repository-format-name', visible: :all)).to have_text(:all, 'Maven')
        expect(page).to have_css('[data-testid="repository-visibility"][aria-label="Private"]')
        expect(find_by_testid('repository-description')).to have_text(description)
        expect(page).to have_content('Hosted')
        expect(find_by_testid('repository-stat-artifacts')).to have_text('2 Packages')
      end
    end

    it 'renders the artifact page the packages connection returns' do
      visit "#{repositories_base_path}/#{name}"

      within_testid('repositories-shell') do
        expect(page).to have_link('com.example.payments:payment-core')
        expect(page).to have_link('com.example.payments:payment-api')
        expect(page).to have_button('More actions for com.example.payments:payment-core')
        expect(page).to have_button('Copy package name', count: 2)
        expect(find_by_testid('artifacts-announcement', visible: :all))
          .to have_text(:all, 'Artifact list updated.')
      end
    end

    # Visibility is left out: the closed beta offers the single Private value, so its radio is
    # selected whether the read answered or not.
    it 'prefills the edit form from the repository' do
      visit "#{repositories_base_path}/#{name}/edit"

      within_testid('repositories-shell') do
        expect(page).to have_field(with: name, readonly: true)
        expect(page).to have_field(with: description, type: 'textarea')
        expect(page).to have_css('[data-testid="repository-format-logo"][src*="maven"]')
      end
    end
  end

  describe 'a virtual repository the schema resolves' do
    include_context 'with a repository the Artifact Registry client returns'

    let(:name) { 'maven-virtual' }
    let(:format) { 'maven' }

    let(:repository_attributes) do
      default_repository_attributes.merge(
        'id' => '01937b2e-0000-7000-8000-000000000020',
        'kind' => 'virtual',
        'description' => 'Resolves through the Maven upstreams.',
        'artifacts_count' => 0,
        'downloads_count' => 0,
        'size_bytes' => 0
      )
    end

    let(:upstream_repositories) do
      [
        ::ArtifactRegistry::UpstreamRepositoryAssociation.new(
          {
            'id' => 'a1000000-0000-4000-8000-000000000001',
            'position' => 1,
            'upstream_repository' => {
              'id' => 'd1000000-0000-4000-8000-000000000001',
              'name' => 'maven-central-proxy',
              'format' => 'maven',
              'kind' => 'remote'
            }
          },
          verdicts(:repository, :upstream_repositories, true)
        ),
        ::ArtifactRegistry::UpstreamRepositoryAssociation.new(
          {
            'id' => 'a1000000-0000-4000-8000-000000000002',
            'position' => 2,
            'upstream_repository' => {
              'id' => 'd1000000-0000-4000-8000-000000000002',
              'name' => 'payments-releases',
              'format' => 'maven',
              'kind' => 'hosted'
            }
          },
          verdicts(:repository, :upstream_repositories, true)
        )
      ]
    end

    before do
      allow(client).to receive(:upstream_repositories)
        .with(slug: slug, repository_name: name, format: 'maven', include_permissions: true)
        .and_return(upstream_repositories)
    end

    it 'renders the upstream table and passes axe automated accessibility testing', :aggregate_failures do
      expect(client).not_to receive(:packages)

      visit "#{repositories_base_path}/#{name}"

      within_testid('repositories-shell') do
        expect(page).to have_testid('upstream-name', count: 2)

        expect(all_by_testid('upstream-position').map(&:text)).to eq(%w[1 2])
        expect(all_by_testid('upstream-name').map(&:text))
          .to eq(%w[maven-central-proxy payments-releases])
        expect(all_by_testid('upstream-kind').map(&:text)).to eq(%w[Remote Hosted])

        expect(find_by_testid('repository-stat-repositories')).to have_text('2 Repositories')
      end

      expect(page).to be_axe_clean.within_testid('repositories-shell')
    end

    it 'renders the row actions the upstream verdicts allow', :aggregate_failures do
      visit "#{repositories_base_path}/#{name}"

      within_testid('repositories-shell') do
        click_button('More actions for maven-central-proxy')

        within_testid('disclosure-content') do
          expect(page).to have_button('Clear cache')
          expect(page).to have_link('Edit repository')
        end

        send_keys :escape

        expect(page).to have_no_testid('disclosure-content')

        click_button('More actions for payments-releases')

        within_testid('disclosure-content') do
          expect(page).to have_link('Edit repository')
          expect(page).to have_no_button('Clear cache')
        end
      end
    end
  end

  describe 'with every verdict denied' do
    include_context 'with a repository the Artifact Registry client returns'

    let(:name) { 'maven-releases' }
    let(:format) { 'maven' }
    let(:repository_attributes) { default_repository_attributes.merge('artifacts_count' => 1) }
    let(:repository_verdicts) { ::ArtifactRegistry::Permissions::Verdicts::REPOSITORY_ACTIONS.index_with(false) }

    let(:packages_page) do
      ::ArtifactRegistry::Page.new(
        nodes: [
          ::ArtifactRegistry::MavenPackage.new(
            'id' => '01937b2e-0000-7000-8000-000000000001',
            'group_id' => 'com.example.payments',
            'artifact_id' => 'payment-core'
          )
        ]
      )
    end

    before do
      allow(client).to receive(:packages).and_return(packages_page)
      allow(client).to receive(:repository_statistics)
        .with(slug: slug, repository_name: name, format: 'maven').and_return(repository_statistics)
    end

    it 'renders the detail without its gated controls and passes axe automated accessibility testing' do
      visit "#{repositories_base_path}/#{name}"

      within_testid('repositories-shell') do
        expect(page).to have_link('com.example.payments:payment-core')
        expect(page).to have_no_link('Edit')
        expect(page).to have_no_button('More actions for com.example.payments:payment-core')
        expect(page).to have_button('Copy package name')
      end

      expect(page).to be_axe_clean.within_testid('repositories-shell')
    end
  end

  # The artifact route reads the same single repository, so whether it exists is Artifact
  # Registry's answer rather than the URL's. A page that rendered without asking would tell a
  # viewer a repository they cannot see is there. Nothing is asserted about the artifact itself,
  # which the browser still resolves for itself.
  describe 'an artifact of a repository Artifact Registry does not hold' do
    let(:name) { 'no-such-repository' }
    let(:artifact_id) { '01937b2e-0000-7000-8000-000000000001' }

    it 'asks Artifact Registry for the repository and renders its not-found state' do
      expect(client).to receive(:repository)
        .with(slug: slug, name: name, include_permissions: true).at_least(:once).and_return(nil)

      visit "#{repositories_base_path}/#{name}/#{artifact_id}"

      within_testid('repositories-shell') do
        expect(page).to have_css('h1', text: 'Page not found')
      end
    end
  end
end
