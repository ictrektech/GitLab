# frozen_string_literal: true

require 'spec_helper'

RSpec.describe VirtualRegistries::Upstreams::Local::CheckService, :aggregate_failures, feature_category: :virtual_registry do
  using RSpec::Parameterized::TableSyntax

  let_it_be(:package_name) { 'my/company/app/my-app' }
  let_it_be(:package_version) { '1.2.3' }
  let_it_be(:filename) { 'maven-metadata.xml' }
  let_it_be(:top_level_group) { create(:group) }
  let_it_be(:subgroup) { create(:group, parent: top_level_group) }
  let_it_be(:top_level_project) { create(:project, namespace: top_level_group) }
  let_it_be(:subproject) { create(:project, namespace: subgroup) }
  let_it_be(:top_level_package_file) do
    create(:maven_package, name: package_name, version: package_version, project: top_level_project)
      .package_files.find { |pf| pf.file_name == filename }
  end

  let_it_be(:subproject_package_file) do
    create(:maven_package, name: package_name, version: package_version, project: subproject)
      .package_files.find { |pf| pf.file_name == filename }
  end

  let_it_be(:registry) { create(:virtual_registries_packages_maven_registry, group: top_level_group) }
  let_it_be_with_reload(:top_level_group_upstream) do
    create(
      :virtual_registries_packages_maven_local_upstream,
      :local_group,
      local_group: top_level_group,
      group: top_level_group
    )
  end

  let_it_be_with_reload(:top_level_project_upstream) do
    create(
      :virtual_registries_packages_maven_local_upstream,
      local_project: top_level_project,
      group: top_level_group
    )
  end

  let_it_be_with_reload(:subgroup_upstream) do
    create(
      :virtual_registries_packages_maven_local_upstream,
      :local_group,
      local_group: subgroup,
      group: top_level_group
    )
  end

  let_it_be_with_reload(:subproject_upstream) do
    create(
      :virtual_registries_packages_maven_local_upstream,
      local_project: subproject,
      group: top_level_group
    )
  end

  let(:service) { described_class.new(upstreams:, params:) }
  let(:path) { "#{package_name}/#{package_version}/#{filename}" }
  let(:params) { { path: } }

  describe '#execute' do
    subject(:execute) { service.execute }

    # rubocop: disable Layout/LineLength -- table based specs
    where(:upstreams, :expected_upstream, :expected_local_file) do
      [ref(:top_level_project_upstream)] | ref(:top_level_project_upstream) | ref(:top_level_package_file)
      [ref(:subproject_upstream)] | ref(:subproject_upstream) | ref(:subproject_package_file)
      [ref(:subgroup_upstream)] | ref(:subgroup_upstream) | ref(:subproject_package_file)
      [ref(:top_level_group_upstream)] | ref(:top_level_group_upstream) | ref(:subproject_package_file)

      [ref(:top_level_project_upstream), ref(:top_level_group_upstream)] | ref(:top_level_project_upstream) | ref(:top_level_package_file)
      [ref(:subproject_upstream), ref(:top_level_project_upstream)] | ref(:subproject_upstream) | ref(:subproject_package_file)
      [ref(:subproject_upstream), ref(:subgroup_upstream)] | ref(:subproject_upstream) | ref(:subproject_package_file)
      [ref(:subgroup_upstream), ref(:top_level_group_upstream)] | ref(:subgroup_upstream) | ref(:subproject_package_file)
    end
    # rubocop: enable Layout/LineLength

    with_them do
      let(:wrapped_local_file) { ::VirtualRegistries::Local::Upstream::File.from_raw_local_file(expected_local_file) }
      let(:payload) { { upstream: expected_upstream, local_file: wrapped_local_file }.compact_blank }

      it { is_expected.to be_success.and have_attributes(payload:) }
    end

    context 'with a path that is not in local upstreams' do
      let(:path) { "test/#{filename}" }
      let(:upstreams) { [top_level_group_upstream] }

      it_behaves_like 'returning an error service response',
        message: described_class::ERRORS[:file_not_found_on_upstreams].message
    end

    context 'with a matching file without md5' do
      before do
        ::Packages::PackageFile.id_in(top_level_package_file.id).update_all(file_md5: nil)
      end

      context 'with a following upstream' do
        let(:upstreams) { [top_level_project_upstream, subproject_upstream] }

        it 'logs the error, skips the upstream and returns the following one' do
          expect(Gitlab::ErrorTracking).to receive(:log_exception).with(
            an_instance_of(ArgumentError).and(having_attributes(message: "Md5 can't be blank")),
            upstream_id: top_level_project_upstream.id,
            package_file_id: top_level_package_file.id
          )

          expect(execute).to be_success
          expect(execute[:upstream]).to eq(subproject_upstream)
          expect(execute[:local_file]).to have_attributes(
            raw_file_id: subproject_package_file.id,
            md5: subproject_package_file.file_md5
          )
        end
      end

      context 'without a following upstream' do
        let(:upstreams) { [top_level_project_upstream] }

        it_behaves_like 'returning an error service response',
          message: 'File not found on any upstream',
          reason: :file_not_found_on_upstreams
      end

      context 'in FIPS mode', :fips_mode do
        let(:upstreams) { [top_level_project_upstream, subproject_upstream] }

        it 'returns the upstream with the file without md5' do
          expect(Gitlab::ErrorTracking).not_to receive(:log_exception)

          expect(execute).to be_success
          expect(execute[:upstream]).to eq(top_level_project_upstream)
          expect(execute[:local_file]).to have_attributes(raw_file_id: top_level_package_file.id, md5: nil)
        end
      end
    end

    context 'when the file lookup raises an ArgumentError' do
      let(:upstreams) { [top_level_project_upstream, subproject_upstream] }

      before do
        allow_next_instance_of(::Packages::Maven::GroupsAndProjectsPackageFilesFinder) do |finder|
          allow(finder).to receive(:execute).and_raise(ArgumentError, 'lookup failed')
        end
      end

      it 'raises the error instead of treating it as a miss' do
        expect { execute }.to raise_error(ArgumentError, 'lookup failed')
      end
    end

    context 'with a not found finder instance' do
      let(:upstreams) { [top_level_group_upstream] }

      before do
        stub_const("#{described_class}::FINDERS_CLASSES_MAP", {})
      end

      it_behaves_like 'returning an error service response', message: described_class::NO_FINDER_INSTANCE_ERROR.message
    end

    it_behaves_like 'a check upstream service handling no path set'
    it_behaves_like 'a check upstream service handling empty upstreams'
  end
end
