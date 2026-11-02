# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organization Artifact Registry setup page', :js, :with_current_organization,
  feature_category: :artifact_registry do
  let_it_be(:user) { create(:organization_owner, organization: current_organization).user }

  before do
    sign_in(user)
  end

  it 'renders the claim form for an owner', :aggregate_failures do
    visit artifact_registry_organization_index_path(current_organization)

    expect(page).to have_testid('page-heading', text: 'Set up Artifact registry')
    expect(page).to have_field('artifact-registry-handle', placeholder: 'my-registry')
    # The frontend builds the client base URL from the origin of `api_url` alone
    # (ADR-009), so this compares against the configured value only because the test
    # config sets it as a bare origin. The derivation itself is covered in
    # ee/spec/helpers/organizations/artifact_registry_helper_spec.rb.
    expect(find_by_testid('handle-url-prefix'))
      .to have_content("#{Gitlab.config.artifact_registry['api_url']}/")

    expect(page).to be_axe_clean.within_testid('artifact-registry-setup')
  end

  context 'when the organization was activated after the page loaded' do
    let(:claimed_slug) { 'claimed-elsewhere' }
    let(:client) { instance_double(::ArtifactRegistry::Client) }
    let(:mapping) { create(:artifact_registry_namespace_mapping, organization: current_organization) }
    let(:live_namespace) do
      ::ArtifactRegistry::Namespace.new(
        'id' => mapping.ar_namespace_id, 'slug' => claimed_slug, 'status' => 'active',
        'created_at' => '2026-07-01T10:00:00Z'
      )
    end

    let(:registry) do
      ::ArtifactRegistry::NamespaceMapping::Registry.new(
        slug: claimed_slug, status: 'active', created_at: '2026-07-01T10:00:00Z'
      )
    end

    before do
      visit artifact_registry_organization_index_path(current_organization)
      find_field('artifact-registry-handle')

      # The row lands after the visit: with it present the route would redirect instead of serving the form.
      mapping
      allow(::ArtifactRegistry::Client).to receive(:new).and_return(client)
      allow(client).to receive_messages(
        namespace: live_namespace,
        repositories: ::ArtifactRegistry::Page.new(nodes: []),
        namespace_details: nil
      )
      allow_next_found_instance_of(::ArtifactRegistry::NamespaceMapping) do |mapping|
        allow(mapping).to receive(:registry).and_return(registry)
      end
    end

    it 'reloads into the registry with a banner naming the claimed handle, shown once', :aggregate_failures do
      fill_in 'artifact-registry-handle', with: 'stale-tab-handle'
      click_button s_('ArtifactRegistry|Enable Artifact registry')

      expect(page).to have_current_path(
        artifact_registry_repositories_organization_path(current_organization, claimed_slug), ignore_query: true
      )
      expect(page).to have_content(s_('ArtifactRegistry|Artifact registry is already enabled'))
      expect(page).to have_content(
        format(
          s_('ArtifactRegistry|Your organization is using the handle %{handle}. The handle you entered was not ' \
            'claimed.'),
          handle: claimed_slug
        )
      )
      expect(page).not_to have_content('stale-tab-handle')

      visit current_path

      expect(page).to have_testid('repositories-shell')
      expect(page).not_to have_content(s_('ArtifactRegistry|Artifact registry is already enabled'))
    end
  end
end
