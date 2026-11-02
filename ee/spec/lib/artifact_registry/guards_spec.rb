# frozen_string_literal: true

require 'fast_spec_helper'

RSpec.describe ArtifactRegistry::Guards, :aggregate_failures, feature_category: :artifact_registry do
  using RSpec::Parameterized::TableSyntax

  let(:host) do
    Class.new do
      include ArtifactRegistry::Guards

      public(*ArtifactRegistry::Guards.private_instance_methods(false))
    end.new
  end

  let(:uuid_v7) { '0190a3b4-5c6d-7e8f-9a0b-1c2d3e4f5a6b' }
  let(:uuid_v4) { '3f2b1c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d' }

  describe '#guard_format!' do
    subject(:guard) { host.guard_format!(format_name, %w[maven npm]) }

    context 'with an allowed format' do
      let(:format_name) { 'npm' }

      it 'accepts it' do
        expect { guard }.not_to raise_error
      end
    end

    context 'with a format that is not allowed' do
      let(:format_name) { 'conda' }

      it 'names the allowed formats' do
        expect { guard }.to raise_error(ArgumentError, 'format must be one of: maven, npm')
      end
    end
  end

  describe '#guard_present!' do
    subject(:guard) { host.guard_present!(**fields) }

    context 'with present values' do
      let(:fields) { { slug: 'acme', name: 'maven-local' } }

      it 'accepts them' do
        expect { guard }.not_to raise_error
      end
    end

    context 'with a blank value' do
      where(:value) { [nil, '', '  '] }

      with_them do
        let(:fields) { { slug: value } }

        it 'rejects it' do
          expect { guard }.to raise_error(ArgumentError, 'slug is required')
        end
      end
    end

    context 'with the not-provided sentinel' do
      let(:fields) { { description: described_class::NOT_PROVIDED } }

      it 'rejects it' do
        expect { guard }.to raise_error(ArgumentError, 'description is required')
      end
    end

    context 'with several missing fields' do
      let(:fields) { { slug: 'acme', name: '', id: nil } }

      it 'names the first one' do
        expect { guard }.to raise_error(ArgumentError, 'name is required')
      end
    end
  end

  describe '#provided_fields' do
    subject(:provided) { host.provided_fields(**fields) }

    let(:fields) { { visibility: 'private', description: nil, settings: described_class::NOT_PROVIDED } }

    it 'drops only the fields left as the not-provided sentinel' do
      is_expected.to eq(visibility: 'private', description: nil)
    end
  end

  describe '#guard_segments!' do
    subject(:guard) { host.guard_segments!(**segments) }

    context 'with segments that contain dots but are not bare dot segments' do
      let(:segments) { { slug: 'acme', name: 'v1.0', id: '..id' } }

      it 'accepts them' do
        expect { guard }.not_to raise_error
      end
    end

    context 'with a bare dot segment' do
      where(:value) { ['.', '..'] }

      with_them do
        let(:segments) { { slug: 'acme', name: value } }

        it 'rejects it' do
          expect { guard }.to raise_error(ArgumentError, "name must not be a bare '.' or '..' segment")
        end
      end
    end

    context 'with a blank segment' do
      let(:segments) { { slug: '' } }

      it 'rejects it as missing' do
        expect { guard }.to raise_error(ArgumentError, 'slug is required')
      end
    end
  end

  describe '#guard_uuid!' do
    subject(:guard) { host.guard_uuid!(**fields) }

    context 'with UUIDs of any version or case' do
      let(:fields) { { entity_id: uuid_v4, billing_entity_id: uuid_v7.upcase } }

      it 'accepts them' do
        expect { guard }.not_to raise_error
      end
    end

    context 'with a value that is not a UUID' do
      where(:value) do
        [
          nil,
          '',
          'not-a-uuid',
          '0190a3b4-5c6d-7e8f-9a0b-1c2d3e4f5a6',
          "0190a3b4-5c6d-7e8f-9a0b-1c2d3e4f5a6b\n",
          "junk\n3f2b1c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d"
        ]
      end

      with_them do
        let(:fields) { { entity_id: value } }

        it 'rejects it' do
          expect { guard }.to raise_error(ArgumentError, 'entity_id must be a UUID')
        end
      end
    end
  end

  describe '#malformed_deep_link?' do
    subject(:malformed) { host.malformed_deep_link?('pkg-1', value) }

    context 'when every value can address a resource' do
      # The byte cap is an upper bound, so a value exactly at it still addresses a resource.
      where(:value) { ['v1.0', 'a' * described_class::MAX_DEEP_LINK_BYTES] }

      with_them do
        it { is_expected.to be(false) }
      end
    end

    context 'with a value that cannot address a resource' do
      where(:value) do
        [
          nil, '', '  ', '.', '..',
          'a' * (described_class::MAX_DEEP_LINK_BYTES + 1),
          'é' * described_class::MAX_DEEP_LINK_BYTES # within the cap in characters, over it in bytes
        ]
      end

      with_them do
        it { is_expected.to be(true) }
      end
    end
  end

  describe '#guard_batch!' do
    subject(:guard) { host.guard_batch!(:ids, list, 2) }

    context 'with a batch within the limit' do
      let(:list) { %w[a a] }

      it 'accepts it, counting repeats' do
        expect { guard }.not_to raise_error
      end
    end

    context 'with a list outside the limit' do
      where(list: [[], %w[a a a], 'a', nil])

      with_them do
        it 'rejects it' do
          expect { guard }.to raise_error(ArgumentError, 'ids must carry between 1 and 2 entries')
        end
      end
    end
  end

  describe '#guard_verification_input!' do
    subject(:guard) { host.guard_verification_input!(namespace_id, repository_ids) }

    let(:namespace_id) { uuid_v7 }
    let(:repository_ids) { [uuid_v7] }

    context 'with a canonical namespace id of any version and canonical UUIDv7 repository ids' do
      let(:namespace_id) { uuid_v4 }

      it 'accepts them' do
        expect { guard }.not_to raise_error
      end
    end

    context 'with a full batch' do
      let(:repository_ids) { Array.new(described_class::MAX_VERIFICATION_BATCH) { uuid_v7 } }

      it 'accepts it' do
        expect { guard }.not_to raise_error
      end
    end

    context 'with a namespace id that is not a canonical UUID' do
      where(:namespace_id) { [nil, '0190A3B4-5C6D-7E8F-9A0B-1C2D3E4F5A6B', 'not-a-uuid'] }

      with_them do
        it 'rejects it' do
          expect { guard }.to raise_error(ArgumentError, 'namespace_id must be a canonical UUID')
        end
      end
    end

    context 'with an oversized batch' do
      let(:repository_ids) { Array.new(described_class::MAX_VERIFICATION_BATCH + 1) { uuid_v7 } }

      it 'rejects it' do
        expect { guard }.to raise_error(
          ArgumentError, "repository_ids must carry between 1 and #{described_class::MAX_VERIFICATION_BATCH} entries"
        )
      end
    end

    context 'with a repository id that is not a canonical UUIDv7' do
      where(:repository_id) { %w[3f2b1c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d 0190A3B4-5C6D-7E8F-9A0B-1C2D3E4F5A6B] }

      with_them do
        let(:repository_ids) { [uuid_v7, repository_id] }

        it 'rejects it' do
          expect { guard }.to raise_error(ArgumentError, 'repository_ids must be canonical UUIDv7s')
        end
      end
    end
  end

  describe '#canonical_uuid?' do
    subject(:canonical_uuid) { host.canonical_uuid?(value) }

    where(:value, :canonical) do
      '3f2b1c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d'       | true
      '3F2B1C4D-5E6F-4A7B-8C9D-0E1F2A3B4C5D'       | false
      '3f2b1c4d5e6f4a7b8c9d0e1f2a3b4c5d'           | false
      "3f2b1c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d\n"     | false
      "junk\n3f2b1c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d" | false
      nil                                          | false
      :'3f2b1c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d'      | false
    end

    with_them do
      it 'accepts only a lowercase canonical UUID string' do
        is_expected.to be(canonical)
      end
    end
  end
end
