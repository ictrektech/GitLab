# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Ml::ModelVersionPresenter, feature_category: :mlops do
  let_it_be(:project) { build_stubbed(:project) }
  let_it_be(:model) { build_stubbed(:ml_models, name: 'a_model', project: project) }
  let_it_be(:model_version) { build_stubbed(:ml_model_versions, :with_package, model: model, version: '1.1.1') }
  let_it_be(:model_version_without_package) { build_stubbed(:ml_model_versions, model: model, version: '1.1.1') }
  let_it_be(:presenter) { model_version.present }

  describe '.display_name' do
    subject { presenter.display_name }

    it { is_expected.to eq('a_model / 1.1.1') }
  end

  describe '#path' do
    subject { presenter.path }

    it { is_expected.to eq("/#{project.full_path}/-/ml/models/#{model.id}/versions/#{model_version.id}") }
  end

  describe '#package_path' do
    subject { presenter.package_path }

    it { is_expected.to eq("/#{project.full_path}/-/packages/#{model_version.package_id}") }
  end

  describe '#import_path' do
    subject { presenter.import_path }

    it { is_expected.to eq("/api/v4/projects/#{project.id}/packages/ml_models/#{model_version.id}/files/") }
  end

  describe '#auhor' do
    subject { presenter.author }

    it { is_expected.to eq(model_version.package.creator) }
  end

  describe 'when author is not present' do
    let_it_be(:presenter) { model_version_without_package.present }

    subject { presenter.author }

    it { is_expected.to be_nil }
  end

  # rubocop:disable RSpec/FactoryBot/AvoidCreate -- artifacts_count runs a SQL count
  describe '#artifacts_count' do
    let(:model_version) { create(:ml_model_versions, :with_package) }

    subject { model_version.present.artifacts_count }

    before do
      create(:package_file, package: model_version.package)
      create(:package_file, :pending_destruction, package: model_version.package)
    end

    it 'counts the installable files' do
      is_expected.to eq(1)
    end
  end
  # rubocop:enable RSpec/FactoryBot/AvoidCreate
end
