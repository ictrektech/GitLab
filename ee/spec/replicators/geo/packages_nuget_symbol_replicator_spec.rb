# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Geo::PackagesNugetSymbolReplicator, feature_category: :geo_replication do
  let(:model_record) { create(:nuget_symbol) }

  include_examples 'a blob replicator'

  it_behaves_like 'a blob replicator whose blob path can be reused' do
    let(:record_reusing_path) do
      create(:nuget_symbol, package: model_record.package, signature: model_record.signature)
    end

    let(:record_with_other_path) do
      create(:nuget_symbol, package: model_record.package, signature: "other#{model_record.signature}")
    end
  end
end
