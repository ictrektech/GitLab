# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Gitlab::Schema::Validation::Validators::MissingIndexes, feature_category: :database do
  missing_indexes = %w[
    missing_index
    renamed_index
    index_namespaces_public_groups_name_id
    index_on_deploy_keys_id_and_type_and_public
    index_users_on_public_email_excluding_null_and_empty
    missing_partition_index
    detached_partition_index
    relocated_partition_index
    invalid_index
    redefined_invalid_index
  ]

  include_examples 'index validators', described_class, missing_indexes

  describe 'hints' do
    let(:hints) { result.to_h { |inconsistency| [inconsistency.object_name, inconsistency.details[:hint]] } }

    it 'hints at REINDEX for an invalid index with the structure.sql definition' do
      expect(hints['invalid_index']).to include('REINDEX INDEX CONCURRENTLY public.invalid_index')
    end

    it 'hints at dropping an invalid index with a different definition' do
      expect(hints['redefined_invalid_index']).to include('DROP INDEX CONCURRENTLY public.redefined_invalid_index')
    end

    it 'gives no hint for an absent index' do
      expect(hints['missing_index']).to be_nil
    end
  end
end
