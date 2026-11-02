# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Packages::BuildInfo, feature_category: :package_registry do
  describe 'relationships' do
    it { is_expected.to belong_to(:package) }
    it { is_expected.to belong_to(:pipeline) }
    it { is_expected.to belong_to(:project) }
  end

  describe '#pipeline' do
    it_behaves_like 'a partition-pruned pipeline association' do
      let(:related_resource) { create(:package_build_info, pipeline_id: pipeline.id) }
    end
  end

  context 'with some build infos' do
    let_it_be(:package) { create(:generic_package) }
    let_it_be(:build_infos) { create_list(:package_build_info, 3, :with_pipeline, package: package) }
    let_it_be(:build_info_with_no_pipeline) { create(:package_build_info) }

    describe '.without_empty_pipelines' do
      subject { package.build_infos.without_empty_pipelines }

      it { is_expected.to match_array(build_infos) }
    end

    describe '.order_by_pipeline_id asc' do
      subject { package.build_infos.order_by_pipeline_id(:asc) }

      it { is_expected.to eq(build_infos) }
    end

    describe '.order_by_pipeline_id desc' do
      subject { package.build_infos.order_by_pipeline_id(:desc) }

      it { is_expected.to eq(build_infos.reverse) }
    end

    describe '.with_pipeline_id_less_than' do
      subject { package.build_infos.with_pipeline_id_less_than(build_infos[1].pipeline_id) }

      it { is_expected.to contain_exactly(build_infos[0]) }
    end

    describe '.with_pipeline_id_greater_than' do
      subject { package.build_infos.with_pipeline_id_greater_than(build_infos[1].pipeline_id) }

      it { is_expected.to contain_exactly(build_infos[2]) }
    end
  end

  describe '.latest_per_package' do
    let_it_be(:project) { create(:project) }
    let_it_be(:package) { create(:generic_package, project: project) }
    let_it_be(:other_package) { create(:generic_package, project: project) }
    let_it_be(:package_without_build_info) { create(:generic_package, project: project) }
    let_it_be(:older_build_info) { create(:package_build_info, :with_pipeline, package: package) }
    let_it_be(:newer_build_info) { create(:package_build_info, :with_pipeline, package: package) }
    let_it_be(:other_build_info) { create(:package_build_info, :with_pipeline, package: other_package) }

    subject(:latest_build_infos) do
      described_class.latest_per_package([package.id, other_package.id, package_without_build_info.id])
    end

    it 'returns the newest build info of each package, keyed by package id', :aggregate_failures do
      expect(latest_build_infos.keys).to contain_exactly(package.id, other_package.id)
      expect(latest_build_infos[package.id]).to eq(newer_build_info)
      expect(latest_build_infos[other_package.id]).to eq(other_build_info)
    end

    it 'preloads the pipelines with what their web URL and user need' do
      latest_build_infos.each_value do |build_info|
        expect(build_info.association(:pipeline)).to be_loaded
        expect(build_info.pipeline.association(:user)).to be_loaded
        expect(build_info.pipeline.project.association(:namespace)).to be_loaded
        expect(build_info.pipeline.project.namespace.association(:route)).to be_loaded
      end
    end

    it 'returns the newest build info even when it has no pipeline' do
      build_info_without_pipeline = create(:package_build_info, package: other_package)

      expect(latest_build_infos[other_package.id]).to eq(build_info_without_pipeline)
    end

    it 'returns an empty hash without package ids' do
      expect(described_class.latest_per_package([])).to eq({})
    end
  end
end
