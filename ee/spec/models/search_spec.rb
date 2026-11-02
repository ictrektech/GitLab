# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ::Search, feature_category: :global_search do
  describe '.hash_namespace_id' do
    it 'returns modulo of string hash value' do
      namespace_id = instance_double(Integer)
      hash_value = 123
      maximum = 100

      expect(namespace_id).to receive_message_chain(:to_s, :hash).and_return hash_value
      expect(described_class.hash_namespace_id(namespace_id, maximum: maximum)).to eq(hash_value % maximum)
    end

    context 'when namespace id is nil' do
      it 'returns nil' do
        expect(described_class.hash_namespace_id(nil)).to be_nil
      end
    end
  end

  describe '.organization_traversal_ids' do
    it 'prefixes the traversal ids with the organization id' do
      expect(described_class.organization_traversal_ids(24, '9970-123-456-')).to eq('24/9970-123-456-')
    end

    # The longer value is the one that must not match: a prefix query for namespace 12
    # scans documents, and namespace 123's document is what could wrongly match it.
    # Asserting it the other way round passes for free, since a shorter string can never
    # start with a longer one.
    it 'keeps the trailing separator, so a prefix query for 12 cannot match 123' do
      expect(described_class.organization_traversal_ids(24, '9970-123-')).not_to start_with(
        described_class.organization_traversal_ids(24, '9970-12-')
      )
    end

    context 'when the organization id is missing' do
      it 'returns nil' do
        expect(described_class.organization_traversal_ids(nil, '9970-')).to be_nil
      end
    end

    context 'when the traversal ids are missing' do
      it 'returns nil' do
        expect(described_class.organization_traversal_ids(24, nil)).to be_nil
      end
    end
  end

  describe '.default_concurrency_limit' do
    it 'returns the default concurrency limit' do
      expect(described_class.default_concurrency_limit).to eq(described_class::DEFAULT_CONCURRENCY_LIMIT)
    end
  end
end
