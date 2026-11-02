# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ArtifactRegistry::ManifestPresenter, feature_category: :artifact_registry do
  let(:organization) { build_stubbed(:organization) }
  let(:repository) do
    ArtifactRegistry::RepositoryPresenter.new(
      ArtifactRegistry::Repository.new('name' => 'container-images', 'format' => 'docker'),
      organization: organization
    )
  end

  let(:image_id) { 'e5f6a7b8-0000-0000-0000-000000000000' }

  let(:attributes) do
    {
      'id' => 'm1000000-0000-0000-0000-000000000000',
      'digest' => 'sha256:aaaa',
      'media_type' => 'application/vnd.oci.image.index.v1+json'
    }
  end

  let(:manifest) { ArtifactRegistry::ManifestDetail.new(attributes) }

  subject(:presenter) do
    described_class.new(manifest, repository: repository, image_id: image_id)
  end

  it 'carries the repository, organization, and image id the manifest was read through' do
    aggregate_failures do
      expect(presenter.repository).to be(repository)
      expect(presenter.organization).to be(organization)
      expect(presenter.image_id).to eq(image_id)
    end
  end

  it 'reads the manifest fields through to the value object' do
    aggregate_failures do
      expect(presenter.id).to eq('m1000000-0000-0000-0000-000000000000')
      expect(presenter.digest).to eq('sha256:aaaa')
      expect(presenter.media_type).to eq('application/vnd.oci.image.index.v1+json')
    end
  end

  describe 'required construction keywords' do
    it 'requires the repository keyword' do
      expect { described_class.new(manifest, image_id: image_id) }
        .to raise_error(ArgumentError, /repository/)
    end

    it 'requires the image_id keyword' do
      expect { described_class.new(manifest, repository: repository) }
        .to raise_error(ArgumentError, /image_id/)
    end

    it 'rejects a separate organization keyword, deriving it from the repository instead' do
      expect { described_class.new(manifest, repository: repository, organization: organization, image_id: image_id) }
        .to raise_error(ArgumentError, /organization/)
    end
  end

  describe '#declarative_policy_subject' do
    it 'authorizes against the organization, not the manifest' do
      expect(presenter.declarative_policy_subject).to be(organization)
    end

    # Why the method exists. Today's field skips the ability, so nothing reaches a policy; drop
    # that skip and the inherited delegate resolves to the bare value object, which has no policy
    # class, and `class_for` raises rather than denying -- a 500, not a 403.
    it 'resolves to a policy, where the bare value object has none', :aggregate_failures do
      expect { DeclarativePolicy.class_for(manifest) }
        .to raise_error(RuntimeError, /no policy for ArtifactRegistry::ManifestDetail/)

      expect(DeclarativePolicy.class_for(presenter.declarative_policy_subject))
        .to eq(::Organizations::OrganizationPolicy)
    end
  end
end
