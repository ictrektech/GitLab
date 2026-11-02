# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Geo::TerraformStateVersionReplicator, feature_category: :geo_replication do
  let_it_be(:ci_build) { create(:ci_build) }
  let_it_be_with_reload(:terraform_state) { create(:terraform_state, project: ci_build.project) }

  let(:model_record) { create(:terraform_state_version, build: ci_build, terraform_state: terraform_state) }

  include_examples 'a blob replicator'

  it_behaves_like 'a blob replicator whose blob path can be reused' do
    let(:record_reusing_path) do
      create(:terraform_state_version, build: ci_build, terraform_state: terraform_state, version: model_record.version)
    end

    let(:record_with_other_path) do
      create(:terraform_state_version, build: ci_build, terraform_state: terraform_state,
        version: model_record.version + 1)
    end
  end

  describe '#blob_location_in_use?' do
    let(:uploader_class) { model_record.file.class.to_s }

    it 'is false for a non-versioned path' do
      path = "#{terraform_state.project_id}/#{terraform_state.uuid}.tfstate"

      expect(replicator.blob_location_in_use?(path, uploader_class)).to be(false)
    end
  end
end
