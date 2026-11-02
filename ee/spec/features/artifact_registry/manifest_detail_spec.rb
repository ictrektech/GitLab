# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Organization Artifact Registry manifest page', :js, :with_current_organization,
  feature_category: :artifact_registry do
  index_digest = "sha256:#{'a1' * 32}"
  child_digest = "sha256:#{'b2' * 32}"
  referrer_digest = "sha256:#{'c3' * 32}"
  second_referrer_digest = "sha256:#{'e4' * 32}"

  index_short_digest = 'a1a1a1a1a1a1'
  child_short_digest = 'b2b2b2b2b2b2'
  referrer_short_digest = 'c3c3c3c3c3c3'
  second_referrer_short_digest = 'e4e4e4e4e4e4'

  next_cursor = 'eyJpZCI6MjB9'
  prev_cursor = 'eyJpZCI6MTB9'

  include_context 'with a signed-in organization member and an active Artifact Registry'
  include_context 'with a repository the Artifact Registry client returns'

  let(:name) { 'container-images' }
  let(:format) { 'docker' }
  let(:artifact_id) { '01937b2e-0000-7000-8000-000000000001' }

  let(:versions_page_path) { "#{repositories_base_path}/#{name}/#{artifact_id}" }
  let(:manifest_page_path) { "#{versions_page_path}/manifests/#{index_digest}" }
  let(:image) { ::ArtifactRegistry::Image.new('id' => artifact_id, 'name' => 'payment-service') }

  let(:index_attributes) do
    {
      'id' => '01937b2e-0000-7000-8000-000000000201',
      'digest' => index_digest,
      'media_type' => 'application/vnd.docker.distribution.manifest.list.v2+json',
      'size' => 2_097_152,
      'created_at' => '2026-06-10T00:00:00Z'
    }
  end

  let(:child_attributes) do
    {
      'id' => '01937b2e-0000-7000-8000-000000000202',
      'digest' => child_digest,
      'media_type' => 'application/vnd.oci.image.manifest.v1+json',
      'size' => 1_048_576,
      'created_at' => '2026-04-02T00:00:00Z'
    }
  end

  let(:manifests_page) do
    ::ArtifactRegistry::Page.new(
      nodes: [
        ::ArtifactRegistry::Manifest.new(index_attributes),
        ::ArtifactRegistry::Manifest.new(child_attributes)
      ]
    )
  end

  let(:index_manifest) do
    ::ArtifactRegistry::ManifestDetail.new(
      index_attributes.merge(
        'tags' => %w[latest trixie],
        'tags_count' => 2,
        'children' => [
          { 'digest' => child_digest, 'architecture' => 'amd64', 'os' => 'linux', 'os_variant' => nil }
        ],
        'children_count' => 1,
        'parent_digests' => [],
        'parents_count' => 0,
        'referrers_count' => 1
      )
    )
  end

  let(:child_manifest) do
    ::ArtifactRegistry::ManifestDetail.new(
      child_attributes.merge(
        'architecture' => 'amd64',
        'os' => 'linux',
        'tags' => [],
        'tags_count' => 0,
        'children' => [],
        'children_count' => 0,
        'parent_digests' => [index_digest],
        'parents_count' => 1,
        'referrers_count' => 0
      )
    )
  end

  let(:first_referrers_page) do
    ::ArtifactRegistry::Page.new(
      nodes: [
        ::ArtifactRegistry::Manifest.new(
          'id' => '01937b2e-0000-7000-8000-000000000301',
          'digest' => referrer_digest,
          'media_type' => 'application/vnd.oci.image.manifest.v1+json',
          'artifact_type' => 'application/vnd.dev.cosign.artifact.sig.v1+json',
          'subject_digest' => index_digest,
          'created_at' => '2026-06-12T00:00:00Z'
        )
      ],
      next_cursor: next_cursor
    )
  end

  let(:second_referrers_page) do
    ::ArtifactRegistry::Page.new(
      nodes: [
        ::ArtifactRegistry::Manifest.new(
          'id' => '01937b2e-0000-7000-8000-000000000302',
          'digest' => second_referrer_digest,
          'media_type' => 'application/vnd.oci.image.manifest.v1+json',
          'artifact_type' => 'application/spdx+json',
          'subject_digest' => index_digest,
          'created_at' => '2026-06-13T00:00:00Z'
        )
      ],
      prev_cursor: prev_cursor
    )
  end

  before do
    allow(client).to receive(:image)
      .with(slug: slug, repository_name: name, format: format, id: artifact_id)
      .and_return(image)
    allow(client).to receive(:manifests)
      .with(hash_including(slug: slug, repository_name: name, format: format, image_id: artifact_id))
      .and_return(manifests_page)
    allow(client).to receive(:manifest)
      .with(slug: slug, repository_name: name, format: format, image_id: artifact_id,
        digest: index_digest)
      .and_return(index_manifest)
    allow(client).to receive(:manifest)
      .with(slug: slug, repository_name: name, format: format, image_id: artifact_id,
        digest: child_digest)
      .and_return(child_manifest)
    allow(client).to receive(:manifest_referrers).and_return(first_referrers_page)
    allow(client).to receive(:manifest_referrers)
      .with(hash_including(cursor: next_cursor)).and_return(second_referrers_page)
  end

  describe 'reached by clicking a row on the manifest list' do
    before do
      visit versions_page_path

      within_testid('repositories-shell') do
        click_link index_short_digest
      end
    end

    it 'heads the manifest page and trails the whole path to it', :aggregate_failures do
      within_testid('repositories-shell') do
        expect(find_by_testid('manifest-digest')).to have_text(index_short_digest)
        expect(find_by_testid('manifest-kind')).to have_text('Index · 1 platform')
        expect(find_by_testid('image-name')).to have_text('payment-service')
      end

      within_testid('breadcrumb-links') do
        expect(page).to have_link('Repositories')
        expect(page).to have_link(name)
        expect(page).to have_link('payment-service')
        expect(page).to have_text(index_short_digest)
      end

      expect(client).to have_received(:manifest)
        .with(slug: slug, repository_name: name, format: format, image_id: artifact_id,
          digest: index_digest).once
    end

    it 'badges every tag the index resolves under' do
      within_testid('repositories-shell') do
        expect(all_by_testid('tag-badge').map(&:text)).to eq(%w[latest trixie])
      end
    end

    it 'passes axe automated accessibility testing' do
      expect(find_by_testid('manifest-digest')).to have_text(index_short_digest)
      expect(page).to be_axe_clean.within_testid('repositories-shell')
        .skipping :'link-in-text-block'
    end
  end

  describe 'the untagged single image below the index' do
    before do
      visit manifest_page_path

      within_testid('repositories-shell') do
        click_link child_short_digest
      end
    end

    it 'renders it with no tag row and the index it hangs under', :aggregate_failures do
      within_testid('repositories-shell') do
        expect(find_by_testid('manifest-digest')).to have_text(child_short_digest)
        expect(find_by_testid('manifest-kind')).to have_text('Image')
        expect(page).to have_no_testid('tag-badges')
        expect(find_by_testid('manifest-referenced-by')).to have_text(index_short_digest)
      end
    end

    it 'passes axe automated accessibility testing' do
      expect(find_by_testid('manifest-digest')).to have_text(child_short_digest)
      expect(page).to be_axe_clean.within_testid('repositories-shell')
        .skipping :'link-in-text-block'
    end
  end

  describe 'the delete manifest action' do
    context 'when the repository verdict allows deleteArtifact' do
      it 'reads the verdict and offers the actions menu', :aggregate_failures do
        visit manifest_page_path

        within_testid('repositories-shell') do
          expect(find_by_testid('manifest-digest')).to have_text(index_short_digest)
          expect(page).to have_testid('manifest-actions')
        end

        expect(client).to have_received(:repository)
          .with(slug: slug, name: name, include_permissions: true).once
      end
    end

    context 'when the repository verdict denies deleteArtifact' do
      let(:repository_verdicts) { super().merge('delete_artifact' => false) }

      it 'renders no actions menu' do
        visit manifest_page_path

        within_testid('repositories-shell') do
          expect(find_by_testid('manifest-digest')).to have_text(index_short_digest)

          wait_for('the permissions read to settle') do
            page.evaluate_script('window.pendingApolloRequests') == 0
          end

          expect(page).to have_no_testid('manifest-actions')
        end
      end
    end
  end

  describe 'the Referrers tab' do
    before do
      visit manifest_page_path

      within_testid('repositories-shell') do
        click_link 'Referrers'
      end
    end

    it 'lists the referrers the connection returned and offers the next page', :aggregate_failures do
      within_testid('repositories-shell') do
        expect(find_by_testid('referrer-digest')).to have_text(referrer_short_digest)
        expect(find_by_testid('referrer-kind')).to have_text('Signature')
        expect(page).to have_button('Next', disabled: false)
      end

      expect(client).to have_received(:manifest_referrers)
        .with(hash_including(image_id: artifact_id, digest: index_digest, limit: 20)).once
    end

    it 'reads the next page with the cursor the connection handed back', :aggregate_failures do
      within_testid('repositories-shell') do
        click_button 'Next'

        expect(find_by_testid('referrer-digest')).to have_text(second_referrer_short_digest)
        expect(page).to have_button('Previous', disabled: false)
      end
    end

    it 'reads the previous page with the cursor the second page handed back', :aggregate_failures do
      within_testid('repositories-shell') do
        click_button 'Next'
        expect(find_by_testid('referrer-digest')).to have_text(second_referrer_short_digest)

        click_button 'Previous'
        expect(find_by_testid('referrer-digest')).to have_text(referrer_short_digest)
      end

      # No stub matches prev_cursor, so a wrong cursor would still render page one; assert the cursor sent.
      expect(client).to have_received(:manifest_referrers)
        .with(hash_including(digest: index_digest, limit: 20, cursor: prev_cursor)).once
    end

    it 'passes axe automated accessibility testing' do
      expect(find_by_testid('referrer-digest')).to have_text(referrer_short_digest)
      expect(page).to be_axe_clean.within_testid('repositories-shell')
        .skipping :'link-in-text-block'
    end
  end

  describe 'a manifest Artifact Registry does not hold' do
    let(:index_manifest) { nil }

    before do
      visit manifest_page_path
    end

    it 'renders the in-SPA not-found state for the manifest the read did not find', :aggregate_failures do
      within_testid('repositories-shell') do
        expect(page).to have_css('h1', text: 'Page not found')
      end

      expect(client).to have_received(:manifest)
        .with(slug: slug, repository_name: name, format: format, image_id: artifact_id, digest: index_digest).once
    end
  end
end
