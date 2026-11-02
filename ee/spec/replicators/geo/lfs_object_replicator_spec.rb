# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Geo::LfsObjectReplicator, feature_category: :geo_replication do
  let(:model_record) { create(:lfs_object, :with_file) }

  include_examples 'a blob replicator'

  it_behaves_like 'a blob replicator whose blob path can be reused' do
    let(:record_reusing_path) { create(:lfs_object, :with_file, oid: model_record.oid) }
    let(:record_with_other_path) { create(:lfs_object, :with_file) }
  end
end
